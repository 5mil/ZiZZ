const std = @import("std");
const chainmod = @import("chain.zig");

pub const Peer = struct {
    addr: []const u8,
    port: u16,
    height: u32 = 0,
};

pub const P2P = struct {
    allocator: std.mem.Allocator,
    chain: *chainmod.Chain,
    io: std.Io,
    port: u16,
    peers: std.array_list.Managed(Peer),

    pub fn init(allocator: std.mem.Allocator, chain: *chainmod.Chain, io: std.Io, port: u16) P2P {
        return .{
            .allocator = allocator,
            .chain = chain,
            .io = io,
            .port = port,
            .peers = std.array_list.Managed(Peer).init(allocator),
        };
    }

    pub fn deinit(self: *P2P) void {
        for (self.peers.items) |p| self.allocator.free(p.addr);
        self.peers.deinit();
    }

    pub fn addPeer(self: *P2P, addr: []const u8, port: u16) !void {
        const owned = try self.allocator.dupe(u8, addr);
        try self.peers.append(.{ .addr = owned, .port = port });
    }

    pub fn handshake(self: *P2P, peer: *Peer) void {
        peer.height = self.chain.tipHeight();
    }

    pub fn syncFrom(self: *P2P, peer: *Peer) void {
        if (peer.height > self.chain.tipHeight()) {
            // gap noted
        }
    }

    pub fn broadcastTx(self: *P2P, from: []const u8, to: []const u8, amount: i64) void {
        _ = self;
        _ = from;
        _ = to;
        _ = amount;
    }

    pub fn listen(self: *P2P) !void {
        const addr = try std.Io.net.IpAddress.parse("0.0.0.0", self.port);
        var server = try addr.listen(self.io, .{ .reuse_address = true });
        defer server.deinit(self.io);
        std.debug.print("P2P listening on 0.0.0.0:{d}\\n", .{self.port});
        while (true) {
            var stream = server.accept(self.io) catch continue;
            self.handleStream(&stream) catch {};
            stream.close(self.io);
        }
    }

    fn handleStream(self: *P2P, stream: *std.Io.net.Stream) !void {
        var buf: [256]u8 = undefined;
        var reader = stream.reader(self.io, &buf);
        const n = reader.interface.readSliceShort(&buf) catch return;
        if (n == 0) return;
        const msg = buf[0..n];
        var wbuf: [64]u8 = undefined;
        var writer = stream.writer(self.io, &wbuf);
        if (std.mem.startsWith(u8, msg, "version")) {
            try writer.interface.print("verack {d}\\n", .{self.chain.tipHeight()});
        } else if (std.mem.startsWith(u8, msg, "getblocks")) {
            try writer.interface.print("blocks {d}\\n", .{self.chain.tipHeight()});
        }
        try writer.interface.flush();
    }
};
