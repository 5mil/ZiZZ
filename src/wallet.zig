const std = @import("std");
const crypto = std.crypto;
const ecdsa = crypto.sign.ecdsa;
const Secp256k1 = crypto.ecc.Secp256k1;

pub const PrivateKey = struct {
    bytes: [32]u8,

    pub fn generate() !PrivateKey {
        var key: [32]u8 = undefined;
        crypto.random.bytes(&key);
        // Ensure non-zero
        if (std.mem.eql(u8, &key, &std.mem.zeroes([32]u8))) key[0] = 1;
        return .{ .bytes = key };
    }

    pub fn toWif(self: PrivateKey, compressed: bool) ![52]u8 {
        var buf: [52]u8 = undefined;
        var payload: [34]u8 = undefined;
        payload[0] = 0x80; // mainnet
        @memcpy(payload[1..33], &self.bytes);
        if (compressed) payload[33] = 0x01 else payload[33] = 0x00;
        const checksum = hash160Checksum(payload[0..34]);
        var full: [38]u8 = undefined;
        @memcpy(full[0..34], &payload);
        @memcpy(full[34..38], checksum[0..4]);
        _ = try base58Encode(&full, &buf);
        return buf;
    }

    pub fn publicKey(self: PrivateKey) ![33]u8 {
        const sk = try ecdsa.EcdsaSecp256k1Sha256.SecretKey.fromBytes(self.bytes);
        const kp = try ecdsa.EcdsaSecp256k1Sha256.KeyPair.fromSecretKey(sk);
        const compressed = kp.public_key.toCompressedSec1();
        var out: [33]u8 = undefined;
        @memcpy(&out, &compressed);
        return out;
    }
};

fn hash160Checksum(data: []const u8) [32]u8 {
    var sha = crypto.hash.sha2.Sha256.init(.{});
    sha.update(data);
    var mid: [32]u8 = undefined;
    sha.final(&mid);
    var sha2 = crypto.hash.sha2.Sha256.init(.{});
    sha2.update(&mid);
    var final: [32]u8 = undefined;
    sha2.final(&final);
    return final;
}

// Minimal base58 (Bitcoin alphabet)
fn base58Encode(data: []const u8, out: []u8) !usize {
    const alphabet = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";
    var zeros: usize = 0;
    while (zeros < data.len and data[zeros] == 0) zeros += 1;
    const size = (data.len - zeros) * 138 / 100 + 1;
    const b58 = try std.heap.page_allocator.alloc(u8, size);
    defer std.heap.page_allocator.free(b58);
    @memset(b58, 0);
    for (data[zeros..]) |b| {
        var carry: u32 = b;
        for (b58, 0..) |*d, i| {
            carry += @as(u32, d.*) << 8;
            d.* = @truncate(carry % 58);
            carry /= 58;
            if (i == size - 1) break;
        }
    }
    var i: usize = 0;
    while (i < size and b58[size - 1 - i] == 0) i += 1;
    var j: usize = 0;
    while (j < zeros) : (j += 1) out[j] = '1';
    var k: usize = 0;
    while (k < size - i) : (k += 1) {
        out[zeros + k] = alphabet[b58[size - 1 - i - k]];
    }
    return zeros + (size - i);
}

pub fn addressFromPubkey(allocator: std.mem.Allocator, pubkey: [33]u8) ![]u8 {
    var sha = crypto.hash.sha2.Sha256.init(.{});
    sha.update(&pubkey);
    var h: [32]u8 = undefined;
    sha.final(&h);
    return try std.fmt.allocPrint(allocator, "zizz1{x}", .{std.fmt.bytesToHex(h[0..20], .lower)});
}
