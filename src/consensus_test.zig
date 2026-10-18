const std = @import("std");
const consensus = @import("consensus.zig");

test "subsidy at height 0 is 50 ZiZZ" {
    const s = consensus.getBlockSubsidy(0);
    try std.testing.expectEqual(@as(consensus.Amount, 50 * consensus.COIN), s);
}

test "subsidy never negative" {
    var h: u32 = 0;
    while (h < 10000) : (h += 100) {
        try std.testing.expect(consensus.getBlockSubsidy(h) >= 0);
    }
}

test "difficulty adjusts" {
    const bits: u32 = 0x207fffff;
    const harder = consensus.adjustDifficulty(bits, 10, 100);
    const easier = consensus.adjustDifficulty(bits, 1000, 100);
    try std.testing.expect(harder < bits);
    try std.testing.expect(easier > bits);
}
