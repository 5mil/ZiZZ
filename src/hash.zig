const std = @import("std");

/// Double SHA-256 (sha256d) used for Bitcoin-family PoW and block hashes.
pub fn sha256d(data: []const u8) [32]u8 {
    var hasher1 = std.crypto.hash.sha2.Sha256.init(.{});
    hasher1.update(data);
    var mid: [32]u8 = undefined;
    hasher1.final(&mid);

    var hasher2 = std.crypto.hash.sha2.Sha256.init(.{});
    hasher2.update(&mid);
    var result: [32]u8 = undefined;
    hasher2.final(&result);
    return result;
}

pub fn hashToHex(hash: [32]u8) [64]u8 {
    var hex: [64]u8 = undefined;
    _ = std.fmt.bufPrint(&hex, "{x}", .{std.fmt.fmtSliceHexLower(&hash)}) catch unreachable;
    return hex;
}

test "sha256d empty" {
    // Just ensure it runs; known value can be added later
    const h = sha256d("");
    _ = h;
}
