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
        _ = self;
        std.debug.print("ZiZZ RPC temporarily disabled during Zig 0.17 port (std.net moved to std.Io).\n", .{});
        std.debug.print("CLI commands (info, subsidy, genesis, hash) work. Node RPC will return.\n", .{});
        return;
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
        } else if (std.mem.eql(u8, method, "dumpprivkey")) {
            return try self.rpcDumpPrivKey(body);
        } else if (std.mem.eql(u8, method, "sendtoaddress")) {
            return try self.rpcSendToAddress(body);
        } else if (std.mem.eql(u8, method, "listbalances")) {
            return try self.rpcListBalances();
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

        var list = std.array_list.Managed(u8).init(self.allocator);
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

    fn rpcDumpPrivKey(self: *RpcServer, body: []const u8) ![]const u8 {
        // Find the address string inside params array
        // Look for zizz1 address in the body
        const needle = "zizz1";
        const pos = std.mem.indexOf(u8, body, needle) orelse return error.BadParam;
        var end = pos + needle.len;
        while (end < body.len and body[end] != '"' and body[end] != ']' and body[end] != ',') : (end += 1) {}
        const addr = body[pos..end];
        std.debug.print("DUMP lookup addr: {s}\n", .{addr});
        std.debug.print("keys count: {d}\n", .{self.chain.keys.count()});
        if (self.chain.dumpPrivKey(addr)) |wif| {
            return try std.fmt.allocPrint(self.allocator, "{{\"jsonrpc\":\"2.0\",\"result\":\"{s}\",\"id\":1}}", .{&wif});
        }
        return try self.allocator.dupe(u8, "{\"jsonrpc\":\"2.0\",\"error\":{\"code\":-5,\"message\":\"no key\"},\"id\":1}");
    }

    fn rpcGetBlockTemplate(self: *RpcServer) ![]const u8 {
        const height = self.chain.tipHeight() + 1;
        const prev = self.chain.tipHashHex();
        const subsidy = consensus.getBlockSubsidy(height);
        return try std.fmt.allocPrint(self.allocator,
            \\{{"jsonrpc":"2.0","result":{{"version":1,"previousblockhash":"{s}","transactions":[],"coinbasevalue":{d},"target":"7fffff0000000000000000000000000000000000000000000000000000000000","mintime":0,"curtime":{d},"bits":"207fffff","height":{d},"noncerange":"00000000ffffffff","sigoplimit":80000,"sizelimit":4000000}},"id":1}}
        , .{ &prev, subsidy, @as(u32, @intCast(std.time.timestamp())), height });
    }

    fn rpcSendToAddress(self: *RpcServer, body: []const u8) ![]const u8 {
        // crude parse: params:["from","to",amount]
        const from = extractQuoted(body, 0) orelse return error.BadParam;
        const to = extractQuoted(body, 1) orelse return error.BadParam;
        const amt_str = extractNumber(body) orelse return error.BadParam;
        std.debug.print("SEND from={s} to={s} amt_str={s}\n", .{from, to, amt_str});
        const amount = std.fmt.parseInt(consensus.Amount, amt_str, 10) catch return error.BadParam;
        self.chain.sendToAddress(from, to, amount) catch |err| {
            const msg = if (err == error.InsufficientFunds) "insufficient funds" else "send failed";
            return try std.fmt.allocPrint(self.allocator, "{{\"jsonrpc\":\"2.0\",\"error\":{{\"code\":-6,\"message\":\"{s}\"}},\"id\":1}}", .{msg});
        };
        return try self.allocator.dupe(u8, "{\"jsonrpc\":\"2.0\",\"result\":\"sent\",\"id\":1}");
    }

    fn rpcListBalances(self: *RpcServer) ![]const u8 {
        const json = try self.chain.listBalances(self.allocator);
        defer self.allocator.free(json);
        return try std.fmt.allocPrint(self.allocator, "{{\"jsonrpc\":\"2.0\",\"result\":{s},\"id\":1}}", .{json});
    }

    fn extractQuoted(body: []const u8, n: usize) ?[]const u8 {
        const params = std.mem.indexOf(u8, body, "\"params\"") orelse return null;
        var count: usize = 0;
        var i: usize = params;
        while (i < body.len) : (i += 1) {
            if (body[i] == '"') {
                const qstart = i + 1;
                i += 1;
                while (i < body.len and body[i] != '"') : (i += 1) {}
                if (i >= body.len) return null;
                // skip the "params" key itself
                if (std.mem.eql(u8, body[qstart..i], "params")) continue;
                if (count == n) return body[qstart..i];
                count += 1;
            }
        }
        return null;
    }

    fn extractNumber(body: []const u8) ?[]const u8 {
        // After the second address quote, find the next integer
        const params = std.mem.indexOf(u8, body, "\"params\"") orelse return null;
        var quotes: usize = 0;
        var i = params;
        while (i < body.len) : (i += 1) {
            if (body[i] == '"') {
                quotes += 1;
                if (quotes == 4) { // end of second address
                    i += 1;
                    while (i < body.len and (body[i] == ',' or body[i] == ' ' or body[i] == ':')) : (i += 1) {}
                    if (i < body.len and body[i] >= '0' and body[i] <= '9') {
                        const nstart = i;
                        while (i < body.len and body[i] >= '0' and body[i] <= '9') : (i += 1) {}
                        return body[nstart..i];
                    }
                }
            }
        }
        return null;
    }

};
