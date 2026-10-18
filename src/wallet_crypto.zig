const std = @import("std");
const crypto = std.crypto;
const wallet = @import("wallet.zig");

/// Password-based seed encryption for ZiZZ wallets.
/// KDF: Argon2id  |  AEAD: ChaCha20-Poly1305
/// Replaces the previous XOR "encryption" stub.
///
/// On-disk format (fixed, little-endian fields):
///   magic[8] = "ZiZZWLT1"
///   version:u8 = 1
///   kdf:u8 = 1  (1 = argon2id)
///   m_kib:u32, t:u32, p:u32
///   salt[16]
///   nonce[12]
///   ciphertext[32]  // encrypted HdSeed.bytes
///   tag[16]
/// Total: 98 bytes

pub const magic = "ZiZZWLT1".*;
pub const version: u8 = 1;
pub const kdf_argon2id: u8 = 1;
pub const file_name = "zizz-wallet.enc";
pub const aad = "zizz-seed-v1";

pub const salt_len = 16;
pub const nonce_len = 12;
pub const seed_len = 32;
pub const tag_len = 16;
pub const blob_len = 8 + 1 + 1 + 4 + 4 + 4 + salt_len + nonce_len + seed_len + tag_len; // 98

/// Interactive unlock defaults (~hundreds of ms on a modern desktop).
pub const default_m_kib: u32 = 64 * 1024; // 64 MiB
pub const default_t: u32 = 3;
pub const default_p: u32 = 1;

/// Lower-cost params for unit tests only.
pub const test_m_kib: u32 = 8; // 8 KiB
pub const test_t: u32 = 1;
pub const test_p: u32 = 1;

pub const EncryptedSeed = struct {
    salt: [salt_len]u8,
    nonce: [nonce_len]u8,
    ciphertext: [seed_len]u8,
    tag: [tag_len]u8,
    m_kib: u32,
    t: u32,
    p: u32,

    pub fn serialize(self: EncryptedSeed) [blob_len]u8 {
        var out: [blob_len]u8 = undefined;
        @memcpy(out[0..8], &magic);
        out[8] = version;
        out[9] = kdf_argon2id;
        std.mem.writeInt(u32, out[10..14], self.m_kib, .little);
        std.mem.writeInt(u32, out[14..18], self.t, .little);
        std.mem.writeInt(u32, out[18..22], self.p, .little);
        @memcpy(out[22..38], &self.salt);
        @memcpy(out[38..50], &self.nonce);
        @memcpy(out[50..82], &self.ciphertext);
        @memcpy(out[82..98], &self.tag);
        return out;
    }

    pub fn deserialize(buf: []const u8) !EncryptedSeed {
        if (buf.len < blob_len) return error.TruncatedBlob;
        if (!std.mem.eql(u8, buf[0..8], &magic)) return error.BadMagic;
        if (buf[8] != version) return error.UnsupportedVersion;
        if (buf[9] != kdf_argon2id) return error.UnsupportedKdf;
        return .{
            .m_kib = std.mem.readInt(u32, buf[10..14], .little),
            .t = std.mem.readInt(u32, buf[14..18], .little),
            .p = std.mem.readInt(u32, buf[18..22], .little),
            .salt = buf[22..38].*,
            .nonce = buf[38..50].*,
            .ciphertext = buf[50..82].*,
            .tag = buf[82..98].*,
        };
    }
};

fn deriveKey(
    allocator: std.mem.Allocator,
    passphrase: []const u8,
    salt: []const u8,
    m_kib: u32,
    t: u32,
    p: u32,
) ![32]u8 {
    if (passphrase.len == 0) return error.EmptyPassphrase;
    if (salt.len < 8) return error.SaltTooShort;
    var key: [32]u8 = undefined;
    const params = crypto.pwhash.argon2.Params{
        .t = t,
        .m = m_kib,
        .p = p,
    };
    try crypto.pwhash.argon2.kdf(
        allocator,
        &key,
        passphrase,
        salt,
        params,
        .argon2id,
    );
    return key;
}

/// Encrypt seed with Argon2id(passphrase) + ChaCha20-Poly1305.
pub fn encryptSeed(
    allocator: std.mem.Allocator,
    seed: wallet.HdSeed,
    passphrase: []const u8,
    io: std.Io,
    m_kib: u32,
    t: u32,
    p: u32,
) !EncryptedSeed {
    var salt: [salt_len]u8 = undefined;
    var nonce: [nonce_len]u8 = undefined;
    io.random(&salt);
    io.random(&nonce);

    var key = try deriveKey(allocator, passphrase, &salt, m_kib, t, p);
    defer crypto.secureZero(u8, &key);

    var ciphertext: [seed_len]u8 = undefined;
    var tag: [tag_len]u8 = undefined;
    crypto.aead.chacha_poly.ChaCha20Poly1305.encrypt(
        &ciphertext,
        &tag,
        &seed.bytes,
        aad,
        nonce,
        key,
    );

    return .{
        .salt = salt,
        .nonce = nonce,
        .ciphertext = ciphertext,
        .tag = tag,
        .m_kib = m_kib,
        .t = t,
        .p = p,
    };
}

/// Decrypt; fails closed on wrong passphrase or tampered blob.
pub fn decryptSeed(
    allocator: std.mem.Allocator,
    enc: EncryptedSeed,
    passphrase: []const u8,
) !wallet.HdSeed {
    var key = try deriveKey(allocator, passphrase, &enc.salt, enc.m_kib, enc.t, enc.p);
    defer crypto.secureZero(u8, &key);

    var plain: [seed_len]u8 = undefined;
    crypto.aead.chacha_poly.ChaCha20Poly1305.decrypt(
        &plain,
        &enc.ciphertext,
        enc.tag,
        aad,
        enc.nonce,
        key,
    ) catch return error.AuthenticationFailed;

    return .{ .bytes = plain };
}

pub fn encryptSeedDefault(
    allocator: std.mem.Allocator,
    seed: wallet.HdSeed,
    passphrase: []const u8,
    io: std.Io,
) !EncryptedSeed {
    return encryptSeed(allocator, seed, passphrase, io, default_m_kib, default_t, default_p);
}

pub fn saveToFile(
    allocator: std.mem.Allocator,
    enc: EncryptedSeed,
    path: []const u8,
    io: std.Io,
) !void {
    _ = allocator;
    const blob = enc.serialize();
    var f = try std.Io.Dir.cwd().createFile(io, path, .{ .truncate = true });
    defer f.close(io);
    var buf: [128]u8 = undefined;
    var w = f.writer(io, &buf);
    try w.interface.writeAll(&blob);
    try w.interface.flush();
}

pub fn loadFromFile(
    path: []const u8,
    io: std.Io,
) !EncryptedSeed {
    var f = try std.Io.Dir.cwd().openFile(io, path, .{});
    defer f.close(io);
    var rbuf: [128]u8 = undefined;
    var reader = f.reader(io, &rbuf);
    var blob: [blob_len]u8 = undefined;
    const n = try reader.interface.readAll(&blob);
    if (n < blob_len) return error.TruncatedBlob;
    return EncryptedSeed.deserialize(&blob);
}

pub fn encryptAndSave(
    allocator: std.mem.Allocator,
    seed: wallet.HdSeed,
    passphrase: []const u8,
    io: std.Io,
) !void {
    const enc = try encryptSeedDefault(allocator, seed, passphrase, io);
    try saveToFile(allocator, enc, file_name, io);
}

pub fn loadAndDecrypt(
    allocator: std.mem.Allocator,
    passphrase: []const u8,
    io: std.Io,
) !wallet.HdSeed {
    const enc = try loadFromFile(file_name, io);
    return decryptSeed(allocator, enc, passphrase);
}

pub fn fileExists(io: std.Io) bool {
    var f = std.Io.Dir.cwd().openFile(io, file_name, .{}) catch return false;
    f.close(io);
    return true;
}

test "roundtrip argon2id + chacha20poly1305" {
    const allocator = std.testing.allocator;
    // Deterministic fake Io.random for the test via manual encrypt path
    var seed = wallet.HdSeed{ .bytes = .{
        1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16,
        17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32,
    } };
    var salt: [salt_len]u8 = .{9} ** salt_len;
    var nonce: [nonce_len]u8 = .{7} ** nonce_len;

    var key = try deriveKey(allocator, "correct horse battery staple", &salt, test_m_kib, test_t, test_p);
    defer crypto.secureZero(u8, &key);

    var ciphertext: [seed_len]u8 = undefined;
    var tag: [tag_len]u8 = undefined;
    crypto.aead.chacha_poly.ChaCha20Poly1305.encrypt(&ciphertext, &tag, &seed.bytes, aad, nonce, key);

    const enc = EncryptedSeed{
        .salt = salt,
        .nonce = nonce,
        .ciphertext = ciphertext,
        .tag = tag,
        .m_kib = test_m_kib,
        .t = test_t,
        .p = test_p,
    };

    const blob = enc.serialize();
    const parsed = try EncryptedSeed.deserialize(&blob);
    const out = try decryptSeed(allocator, parsed, "correct horse battery staple");
    try std.testing.expectEqualSlices(u8, &seed.bytes, &out.bytes);

    // wrong password must fail
    try std.testing.expectError(error.AuthenticationFailed, decryptSeed(allocator, parsed, "wrong"));
}

test "tamper fails auth" {
    const allocator = std.testing.allocator;
    var salt: [salt_len]u8 = .{1} ** salt_len;
    var nonce: [nonce_len]u8 = .{2} ** nonce_len;
    const seed_bytes = [_]u8{0xab} ** seed_len;
    var key = try deriveKey(allocator, "pw", &salt, test_m_kib, test_t, test_p);
    defer crypto.secureZero(u8, &key);
    var ct: [seed_len]u8 = undefined;
    var tag: [tag_len]u8 = undefined;
    crypto.aead.chacha_poly.ChaCha20Poly1305.encrypt(&ct, &tag, &seed_bytes, aad, nonce, key);
    ct[0] ^= 0x01; // flip a ciphertext bit
    const enc = EncryptedSeed{
        .salt = salt,
        .nonce = nonce,
        .ciphertext = ct,
        .tag = tag,
        .m_kib = test_m_kib,
        .t = test_t,
        .p = test_p,
    };
    try std.testing.expectError(error.AuthenticationFailed, decryptSeed(allocator, enc, "pw"));
}
