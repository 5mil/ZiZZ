const std = @import("std");
const hashmod = @import("hash.zig");
const consensus = @import("consensus.zig");

/// Minimal Bitcoin-style block header (80 bytes).
pub const BlockHeader = struct {
    version: i32 = 1,
    prev_block: [32]u8 = std.mem.zeroes([32]u8),
    merkle_root: [32]u8 = std.mem.zeroes([32]u8),
    timestamp: u32 = 0,
    bits: u32 = 0x207fffff, // easy difficulty for testnet/regtest
    nonce: u32 = 0,

    pub fn serialize(self: BlockHeader, buf: *[80]u8) void {
        std.mem.writeInt(i32, buf[0..4], self.version, .little);
        @memcpy(buf[4..36], &self.prev_block);
        @memcpy(buf[36..68], &self.merkle_root);
        std.mem.writeInt(u32, buf[68..72], self.timestamp, .little);
        std.mem.writeInt(u32, buf[72..76], self.bits, .little);
        std.mem.writeInt(u32, buf[76..80], self.nonce, .little);
    }

    pub fn getHash(self: BlockHeader) [32]u8 {
        var buf: [80]u8 = undefined;
        self.serialize(&buf);
        return hashmod.sha256d(&buf);
    }
};

/// Create a simple genesis header with the wizard message baked into the merkle conceptually.
/// (Full coinbase tx would go here in a complete node.)
pub fn createGenesisHeader() BlockHeader {
    return BlockHeader{
        .version = 1,
        .timestamp = 1728835200, // ~ Oct 2024 style timestamp for launch
        .bits = 0x207fffff,
        .nonce = 0,
        // merkle_root would be of the genesis coinbase containing the message
        // "Lo, another ledger of flickering wicks. Mine if you must, but mind the smoke."
    };
}

test "genesis header hashes" {
    const h = createGenesisHeader();
    const hsh = h.getHash();
    _ = hsh;
    // In a full implementation we would assert against a mined genesis hash
}
