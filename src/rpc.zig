const std = @import("std");
const consensus = @import("consensus.zig");
const chainmod = @import("chain.zig");
const hashmod = @import("hash.zig");

pub const RpcServer = struct {
    allocator: std.mem.Allocator,
    chain: *chainmod.Chain,
    port: u16,
    user: []const u8,
    password: []const u8,
    chain_name: []const u8,

    pub fn init(allocator: std.mem.Allocator, chain: *chainmod.Chain, port: u16, chain_name: []const u8) RpcServer {
        return .{
            .allocator = allocator,
            .chain = chain,
            .port = port,
            .user = "zizz",
            .password = "wick-of-the-ancients",
            .chain_name = chain_name,
        };
    }

    pub fn start(self: *RpcServer) !void {
        const address = try std.net.Address.parseIp("127.0.0.1", self.port);
        var server = try address.listen(.{ .reuse_address = true });
        defer server.deinit();

        std.debug.print("ZiZZ RPC listening on 127.0.0.1:{d} (user={s})\n", .{ self.port, self.user });
        std.debug.print("Point tpool EXTERNAL at: http://{s}:{s}@127.0.0.1:{d}\n", .{ self.user, self.password, self.port });

        while (true) {
            const conn = server.accept() catch |err| {
                std.debug.print("accept error: {}\n", .{err});
                continue;
            };
            self.handleConnection(conn) catch |err| {
                std.debug.print("handle error: {}\n", .{err});
            };
        }
    }

    fn handleConnection(self: *RpcServer, conn: std.net.Server.Connection) !void {
        defer conn.stream.close();

        var buf: [8192]u8 = undefined;
        const n = try conn.stream.read(&buf);
        if (n == 0) return;

        const req = buf[0..n];
        const body_start = std.mem.indexOf(u8, req, "\r\n\r\n") orelse return;
        const body = req[body_start + 4 ..];

        var response: []const u8 = undefined;
        if (std.mem.indexOf(u8, body, "\"method\"") == null) {
            response = "{\"error\":\"invalid request\"}";
        } else {
            response = self.dispatch(body) catch "{\"error\":\"dispatch failed\"}";
        }

        const http_resp = try std.fmt.allocPrint(self.allocator,
            \\HTTP/1.1 200 OK
            \\Content-Type: application/json
            \\Content-Length: {d}
            \\Connection: close
            \\
            \\{s}
        , .{ response.len, response });
        defer self.allocator.free(http_resp);
        _ = try conn.stream.writeAll(http_resp);
    }

    fn dispatch(self: *RpcServer, body: []const u8) ![]const u8 {
        const method = extractMethod(body) orelse return try self.allocator.dupe(u8, "{\"jsonrpc\":\"2.0\",\"error\":{\"code\":-32600,\"message\":\"invalid request\"},\"id\":null}");

        if (std.mem.eql(u8, method, "getblockchaininfo")) {
            return try self.rpcGetBlockchainInfo();
        } else if (std.mem.eql(u8, method, "getblockcount")) {
            return try self.rpcGetBlockCount();
        } else if (std.mem.eql(u8, method, "getbestblockhash")) {
            return try self.rpcGetBestBlockHash();
        } else if (std.mem.eql(u8, method, "getnewaddress")) {
            return try self.rpcGetNewAddress();
        } else if (std.mem.eql(u8, method, "getbalance")) {
            return try self.rpcGetBalance();
        } else if (std.mem.eql(u8, method, "generatetoaddress")) {
            return try self.rpcGenerateToAddress(body);
        } else if (std.mem.eql(u8, method, "getblocktemplate")) {
            return try self.rpcGetBlockTemplate();
        } else if (std.mem.eql(u8, method, "createwallet")) {
            return try self.allocator.dupe(u8, "{\"jsonrpc\":\"2.0\",\"result\":{\"name\":\"wizard\"},\"id\":1}");
        } else {
            return try std.fmt.allocPrint(self.allocator, "{{\"jsonrpc\":\"2.0\",\"error\":{{\"code\":-32601,\"message\":\"method not found: {s}\"}},\"id\":1}}", .{method});
        }
    }

    fn extractMethod(body: []const u8) ?[]const u8 {
        const needle = "\"method\":\"";
        const idx = std.mem.indexOf(u8, body, needle) orelse return null;
        const from = idx + needle.len;
        const end = std.mem.indexOfPos(u8, body, from, "\"") orelse return null;
        return body[from..end];
    }

    fn rpcGetBlockchainInfo(self: *RpcServer) ![]const u8 {
        const height = self.chain.tipHeight();
        const hex = self.chain.tipHashHex();
        return try std.fmt.allocPrint(self.allocator,
            \\{{"jsonrpc":"2.0","result":{{"chain":"{s}","blocks":{d},"headers":{d},"bestblockhash":"{s}","difficulty":1,"verificationprogress":1,"chainwork":"0000000000000000000000000000000000000000000000000000000000000001","pruned":false,"softforks":[]}},"id":1}}
        , .{ self.chain_name, height, height, &hex });
    }

    fn rpcGetBlockCount(self: *RpcServer) ![]const u8 {
        return try std.fmt.allocPrint(self.allocator, "{{\"jsonrpc\":\"2.0\",\"result\":{d},\"id\":1}}", .{self.chain.tipHeight()});
    }

    fn rpcGetBestBlockHash(self: *RpcServer) ![]const u8 {
        const hex = self.chain.tipHashHex();
        return try std.fmt.allocPrint(self.allocator, "{{\"jsonrpc\":\"2.0\",\"result\":\"{s}\",\"id\":1}}", .{&hex});
    }

    fn rpcGetNewAddress(self: *RpcServer) ![]const u8 {
        const addr = try self.chain.getNewAddress();
        return try std.fmt.allocPrint(self.allocator, "{{\"jsonrpc\":\"2.0\",\"result\":\"{s}\",\"id\":1}}", .{addr});
    }

    fn rpcGetBalance(self: *RpcServer) ![]const u8 {
        const total = self.chain.getTotalBalance();
        const zizz = consensus.subsidyToZiZZ(total);
        var buf: [64]u8 = undefined;
        const result_str = try std.fmt.bufPrint(&buf, "{d:.8}", .{zizz});
        return try std.fmt.allocPrint(self.allocator, "{s}{s}{s}", .{ 
            "{\"jsonrpc\":\"2.0\",\"result\":", 
            result_str, 
            ",\"id\":1}" 
        });
    }

    fn rpcGenerateToAddress(self: *RpcServer, body: []const u8) ![]const u8 {
        var n: u32 = 1;
        var addr: []const u8 = "zizz1default";

        if (std.mem.indexOf(u8, body, "\"params\":[")) |p| {
            const after = body[p + 10 ..];
            if (std.fmt.parseInt(u32, std.mem.trim(u8, after[0 .. std.mem.indexOfScalar(u8, after, ',') orelse 4], " \""), 10)) |parsed| {
                n = parsed;
            } else |_| {}
            if (std.mem.indexOf(u8, after, "\"")) |q1| {
                const rest = after[q1 + 1 ..];
                if (std.mem.indexOf(u8, rest, "\"")) |q2| {
                    addr = rest[0..q2];
                }
            }
        }

        const hashes = try self.chain.generateToAddress(n, addr);
        defer self.allocator.free(hashes);

        var list = std.ArrayList(u8).init(self.allocator);
        try list.appendSlice("[");
        for (hashes, 0..) |h, i| {
            if (i > 0) try list.appendSlice(",");
            try list.appendSlice("\"");
            try list.appendSlice(&h);
            try list.appendSlice("\"");
        }
        try list.appendSlice("]");
        const list_slice = try list.toOwnedSlice();
        defer self.allocator.free(list_slice);

        return try std.fmt.allocPrint(self.allocator, "{{\"jsonrpc\":\"2.0\",\"result\":{s},\"id\":1}}", .{list_slice});
    }

    fn rpcGetBlockTemplate(self: *RpcServer) ![]const u8 {
        const height = self.chain.tipHeight() + 1;
        const prev = self.chain.tipHashHex();
        const subsidy = consensus.getBlockSubsidy(height);
        return try std.fmt.allocPrint(self.allocator,
            \\{{"jsonrpc":"2.0","result":{{"version":1,"previousblockhash":"{s}","transactions":[],"coinbasevalue":{d},"target":"7fffff0000000000000000000000000000000000000000000000000000000000","mintime":0,"curtime":{d},"bits":"207fffff","height":{d},"noncerange":"00000000ffffffff","sigoplimit":80000,"sizelimit":4000000}},"id":1}}
        , .{ &prev, subsidy, @as(u32, @intCast(std.time.timestamp())), height });
    }
};
