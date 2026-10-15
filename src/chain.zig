const std = @import("std");
const consensus = @import("consensus.zig");
const block = @import("block.zig");
const hash = @import("hash.zig");

pub const Block = struct {
    header: block.BlockHeader,
    height: u32,
    subsidy: consensus.Amount,
    // Simplified: no full txs yet, just coinbase reward tracked via height
};

pub const Chain = struct {
    allocator: std.mem.Allocator,
    blocks: std.ArrayList(Block),
    // Simple address -> balance (sats). Addresses are arbitrary strings for regtest.
    balances: std.StringHashMap(consensus.Amount),

    pub fn init(allocator: std.mem.Allocator) !Chain {
        var self = Chain{
            .allocator = allocator,
            .blocks = std.ArrayList(Block).init(allocator),
            .balances = std.StringHashMap(consensus.Amount).init(allocator),
        };
        // Genesis
        const genesis = block.createGenesisHeader();
        try self.blocks.append(.{
            .header = genesis,
            .height = 0,
            .subsidy = 0,
        });
        return self;
    }

    pub fn deinit(self: *Chain) void {
        self.blocks.deinit();
        var it = self.balances.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.balances.deinit();
    }

    pub fn height(self: *const Chain) u32 {
        return @intCast(self.blocks.items.len - 1);
    }

    pub fn tipHash(self: *const Chain) [32]u8 {
        return self.blocks.items[self.blocks.items.len - 1].header.getHash();
    }

    /// Mine nblocks to the given address (regtest style, no real PoW work beyond nonce increment).
    pub fn generateToAddress(self: *Chain, nblocks: u32, address: []const u8) !void {
        var i: u32 = 0;
        while (i < nblocks) : (i += 1) {
            const next_height = self.height() + 1;
            const subsidy = consensus.getBlockSubsidy(next_height);

            var hdr = block.BlockHeader{
                .version = 1,
                .prev_block = self.tipHash(),
                .timestamp = @intCast(std.time.timestamp()),
                .bits = 0x207fffff, // easy
                .nonce = 0,
            };
            // Fake merkle for now
            hdr.merkle_root = hash.sha256d(address);

            // "Mine" by finding a nonce that meets easy bits (trivial for 0x207fffff)
            while (true) {
                const h = hdr.getHash();
                // Very loose check for demo: any nonce works for this bits
                if (true) break;
                hdr.nonce += 1;
            }

            try self.blocks.append(.{
                .header = hdr,
                .height = next_height,
                .subsidy = subsidy,
            });

            // Credit the address
            const gop = try self.balances.getOrPut(try self.allocator.dupe(u8, address));
            if (!gop.found_existing) {
                gop.value_ptr.* = 0;
            }
            gop.value_ptr.* += subsidy;
        }
    }

    pub fn getBalance(self: *const Chain, address: []const u8) consensus.Amount {
        return self.balances.get(address) orelse 0;
    }

    pub fn getBlockHash(self: *const Chain, height: u32) ?[32]u8 {
        if (height >= self.blocks.items.len) return null;
        return self.blocks.items[height].header.getHash();
    }
};
