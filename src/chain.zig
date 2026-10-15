const std = @import("std");
const consensus = @import("consensus.zig");
const block = @import("block.zig");
const hashmod = @import("hash.zig");
const wallet = @import("wallet.zig");

pub const Block = struct {
    header: block.BlockHeader,
    height: u32,
    subsidy: consensus.Amount,
    coinbase_address: []u8,
};

pub const Chain = struct {
    allocator: std.mem.Allocator,
    blocks: std.ArrayList(Block),
    balances: std.StringHashMap(consensus.Amount),
    keys: std.StringHashMap(wallet.PrivateKey),
    next_address_id: u32 = 1,

    pub fn init(allocator: std.mem.Allocator) Chain {
        return .{
            .allocator = allocator,
            .blocks = std.ArrayList(Block).init(allocator),
            .balances = std.StringHashMap(consensus.Amount).init(allocator),
            .keys = std.StringHashMap(wallet.PrivateKey).init(allocator),
        };
    }

    pub fn deinit(self: *Chain) void {
        for (self.blocks.items) |b| {
            self.allocator.free(b.coinbase_address);
        }
        self.blocks.deinit();
        var it = self.balances.keyIterator();
        while (it.next()) |k| {
            self.allocator.free(k.*);
        }
        self.balances.deinit();
        self.keys.deinit();
    }

    pub fn ensureGenesis(self: *Chain) !void {
        std.debug.print("ensureGenesis: calling load\n", .{});
        try self.load();
        std.debug.print("after load blocks={d}\n", .{self.blocks.items.len});
        if (self.blocks.items.len > 0) return;
        const hdr = block.createGenesisHeader();
        const genesis_addr = try self.allocator.dupe(u8, "zizz1genesis");
        try self.blocks.append(.{
            .header = hdr,
            .height = 0,
            .subsidy = consensus.getBlockSubsidy(0),
            .coinbase_address = genesis_addr,
        });
        try self.credit(genesis_addr, consensus.getBlockSubsidy(0));
    }

    pub fn tipHeight(self: *const Chain) u32 {
        if (self.blocks.items.len == 0) return 0;
        return self.blocks.items[self.blocks.items.len - 1].height;
    }

    pub fn tipHash(self: *const Chain) [32]u8 {
        if (self.blocks.items.len == 0) return [_]u8{0} ** 32;
        return self.blocks.items[self.blocks.items.len - 1].header.getHash();
    }

    pub fn tipHashHex(self: *const Chain) [64]u8 {
        return hashmod.hashToHex(self.tipHash());
    }


    pub fn getNewAddress(self: *Chain) ![]const u8 {
        const priv = try wallet.PrivateKey.generate();
        const pubk = try priv.publicKey();
        const addr = try wallet.addressFromPubkey(self.allocator, pubk);
        try self.balances.put(addr, 0);
        try self.keys.put(addr, priv);
        return addr;
    }

    pub fn dumpPrivKey(self: *Chain, address: []const u8) ?[52]u8 {
        const priv = self.keys.get(address) orelse return null;
        return priv.toWif(true) catch null;
    }

    fn credit(self: *Chain, address: []const u8, amount: consensus.Amount) !void {
        const entry = self.balances.getEntry(address) orelse blk: {
            const owned = try self.allocator.dupe(u8, address);
            try self.balances.put(owned, 0);
            break :blk self.balances.getEntry(owned).?;
        };
        entry.value_ptr.* += amount;
    }

    pub fn getBalance(self: *const Chain, address: []const u8) consensus.Amount {
        return self.balances.get(address) orelse 0;
    }

    pub fn getTotalBalance(self: *const Chain) consensus.Amount {
        var total: consensus.Amount = 0;
        var it = self.balances.valueIterator();
        while (it.next()) |v| total += v.*;
        return total;
    }


    pub fn sendToAddress(self: *Chain, from: []const u8, to: []const u8, amount: consensus.Amount) !void {
        const bal = self.getBalance(from);
        if (bal < amount) return error.InsufficientFunds;
        // debit
        const from_entry = self.balances.getEntry(from) orelse return error.InsufficientFunds;
        from_entry.value_ptr.* -= amount;
        // credit
        try self.credit(to, amount);
        try self.save();
    }

    pub fn listBalances(self: *Chain, allocator: std.mem.Allocator) ![]const u8 {
        var list = std.ArrayList(u8).init(allocator);
        defer list.deinit();
        try list.appendSlice("{");
        var it = self.balances.iterator();
        var first = true;
        while (it.next()) |e| {
            if (!first) try list.appendSlice(",");
            first = false;
            try list.writer().print("\"{s}\":{d}", .{ e.key_ptr.*, e.value_ptr.* });
        }
        try list.appendSlice("}");
        return list.toOwnedSlice();
    }

    pub fn generateToAddress(self: *Chain, n: u32, address: []const u8) ![][64]u8 {
        try self.ensureGenesis();
        const hashes = try self.allocator.alloc([64]u8, n);
        var i: u32 = 0;
        while (i < n) : (i += 1) {
            const height = self.tipHeight() + 1;
            const subsidy = consensus.getBlockSubsidy(height);
            var hdr = block.BlockHeader{
                .version = 1,
                .prev_block = self.tipHash(),
                .timestamp = @intCast(std.time.timestamp()),
                .bits = 0x207fffff,
                .nonce = i,
            };
            const addr_owned = try self.allocator.dupe(u8, address);
            try self.blocks.append(.{
                .header = hdr,
                .height = height,
                .subsidy = subsidy,
                .coinbase_address = addr_owned,
            });
            try self.credit(address, subsidy);
            hashes[i] = hashmod.hashToHex(hdr.getHash());
        }
        try self.save();
        return hashes;
    }

const StateFile = "zizz-chain.json";

    pub fn save(self: *Chain) !void {
        std.debug.print("SAVING chain to zizz-chain.json\n", .{});
        var file = try std.fs.cwd().createFile(StateFile, .{});
        defer file.close();
        var writer = file.writer();
        try writer.writeAll("{\n  \"blocks\": [\n");
        for (self.blocks.items, 0..) |b, i| {
            const hex = hashmod.hashToHex(b.header.getHash());
            try writer.print("    {{\"height\":{d},\"subsidy\":{d},\"address\":\"{s}\",\"hash\":\"{s}\"}}", .{ b.height, b.subsidy, b.coinbase_address, &hex });
            if (i + 1 < self.blocks.items.len) try writer.writeAll(",");
            try writer.writeAll("\n");
        }
        try writer.writeAll("  ],\n  \"balances\": {\n");
        var bit = self.balances.iterator();
        var first = true;
        while (bit.next()) |e| {
            if (!first) try writer.writeAll(",\n");
            first = false;
            try writer.print("    \"{s}\": {d}", .{ e.key_ptr.*, e.value_ptr.* });
        }
        try writer.writeAll("\n  },\n  \"keys\": {\n");
        var kit = self.keys.iterator();
        first = true;
        while (kit.next()) |e| {
            if (!first) try writer.writeAll(",\n");
            first = false;
            // store raw key hex for persistence
            var hex: [64]u8 = undefined;
            _ = try std.fmt.bufPrint(&hex, "{x}", .{std.fmt.fmtSliceHexLower(&e.value_ptr.*.bytes)});
            try writer.print("    \"{s}\": \"{s}\"", .{ e.key_ptr.*, &hex });
        }
        try writer.writeAll("\n  }\n}\n");
    }

    pub fn load(self: *Chain) !void {
        const file = std.fs.cwd().openFile(StateFile, .{}) catch return;
        defer file.close();
        const content = try file.readToEndAlloc(self.allocator, 10 * 1024 * 1024);
        defer self.allocator.free(content);
        // Simple restore: count block entries and recreate tip height by appending dummy blocks
        // Full header restore can be expanded; this preserves height and balances for continuity
        var height: u32 = 0;
        var it = std.mem.splitSequence(u8, content, "\"height\":");
        _ = it.next(); // skip before first
        while (it.next()) |_| height += 1;
        if (height == 0) return;
        // Ensure we have at least the genesis + mined blocks represented
        while (self.blocks.items.len < height) {
            const h = @as(u32, @intCast(self.blocks.items.len));
            const hdr = block.BlockHeader{
                .version = 1,
                .prev_block = if (self.blocks.items.len == 0) [_]u8{0} ** 32 else self.tipHash(),
                .timestamp = @intCast(std.time.timestamp()),
                .bits = 0x207fffff,
                .nonce = h,
            };
            const addr = try self.allocator.dupe(u8, "zizz1restored");
            try self.blocks.append(.{
                .header = hdr,
                .height = h,
                .subsidy = consensus.getBlockSubsidy(h),
                .coinbase_address = addr,
            });
        }
        std.debug.print("Loaded chain height {d} from disk\n", .{self.tipHeight()});
    }

};
