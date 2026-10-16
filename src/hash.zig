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

/// Convert 32-byte hash to lowercase hex string (64 chars).
pub fn hashToHex(hash: [32]u8) [64]u8 {
    return std.fmt.bytesToHex(&hash, .lower);
}

test "sha256d empty" {
    const h = sha256d("");
    _ = h;
}

test "hex roundtrip length" {
    const h = sha256d("test");
    const hex = hashToHex(h);
    try std.testing.expectEqual(@as(usize, 64), hex.len);
}
