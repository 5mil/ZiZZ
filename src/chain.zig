const std = @import("std");
const consensus = @import("consensus.zig");
const block = @import("block.zig");
const hashmod = @import("hash.zig");

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
    next_address_id: u32 = 1,

    pub fn init(allocator: std.mem.Allocator) Chain {
        return .{
            .allocator = allocator,
            .blocks = std.ArrayList(Block).init(allocator),
            .balances = std.StringHashMap(consensus.Amount).init(allocator),
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
    }

    pub fn ensureGenesis(self: *Chain) !void {
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
        const id = self.next_address_id;
        self.next_address_id += 1;
        const addr = try std.fmt.allocPrint(self.allocator, "zizz1regtest{d}", .{id});
        try self.balances.put(addr, 0);
        return addr;
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
        return hashes;
    }
};
