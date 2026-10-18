//! RIPEMD-160 (Dobbertin, Bosselaers, Preneel) — needed for Bitcoin HASH160.
//! Zig std.crypto has no RIPEMD-160; this is a compact, tested port for address derivation.

const std = @import("std");

pub const digest_length = 20;
pub const block_length = 64;

const KL = [_]u32{
    0x00000000, 0x5a827999, 0x6ed9eba1, 0x8f1bbcdc, 0xa953fd4e,
};
const KR = [_]u32{
    0x50a28be6, 0x5c4dd124, 0x6d703ef3, 0x7a6d76e9, 0x00000000,
};

const RL = [_]u8{
    0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15,
    7, 4, 13, 1, 10, 6, 15, 3, 12, 0, 9, 5, 2, 14, 11, 8,
    3, 10, 14, 4, 9, 15, 8, 1, 2, 7, 0, 6, 13, 11, 5, 12,
    1, 9, 11, 10, 0, 8, 12, 4, 13, 3, 7, 15, 14, 5, 6, 2,
    4, 0, 5, 9, 7, 12, 2, 10, 14, 1, 3, 8, 11, 6, 15, 13,
};
const RR = [_]u8{
    5, 14, 7, 0, 9, 2, 11, 4, 13, 6, 15, 8, 1, 10, 3, 12,
    6, 11, 3, 7, 0, 13, 5, 10, 14, 15, 8, 12, 4, 9, 1, 2,
    15, 5, 1, 3, 7, 14, 6, 9, 11, 8, 12, 2, 10, 0, 4, 13,
    8, 6, 4, 1, 3, 11, 15, 0, 5, 12, 2, 13, 9, 7, 10, 14,
    12, 15, 10, 4, 1, 5, 8, 7, 6, 2, 13, 14, 0, 3, 9, 11,
};
const SL = [_]u8{
    11, 14, 15, 12, 5, 8, 7, 9, 11, 13, 14, 15, 6, 7, 9, 8,
    7, 6, 8, 13, 11, 9, 7, 15, 7, 12, 15, 9, 11, 7, 13, 12,
    11, 13, 6, 7, 14, 9, 13, 15, 14, 8, 13, 6, 5, 12, 7, 5,
    11, 12, 14, 15, 14, 15, 9, 8, 9, 14, 5, 6, 8, 6, 5, 12,
    9, 15, 5, 11, 6, 8, 13, 12, 5, 12, 13, 14, 11, 8, 5, 6,
};
const SR = [_]u8{
    8, 9, 9, 11, 13, 15, 15, 5, 7, 7, 8, 11, 14, 14, 12, 6,
    9, 13, 15, 7, 12, 8, 9, 11, 7, 7, 12, 7, 6, 15, 13, 11,
    9, 7, 15, 11, 8, 6, 6, 14, 12, 13, 5, 14, 13, 13, 7, 5,
    15, 5, 8, 11, 14, 14, 6, 14, 6, 9, 12, 9, 12, 5, 15, 8,
    8, 5, 12, 9, 12, 5, 14, 6, 8, 13, 6, 5, 15, 13, 11, 11,
};

inline fn f(j: usize, x: u32, y: u32, z: u32) u32 {
    return switch (j / 16) {
        0 => x ^ y ^ z,
        1 => (x & y) | (~x & z),
        2 => (x | ~y) ^ z,
        3 => (x & z) | (y & ~z),
        else => x ^ (y | ~z),
    };
}

inline fn rotl(x: u32, n: u32) u32 {
    return (x << @intCast(n)) | (x >> @intCast(32 - n));
}

fn processBlock(h: *[5]u32, block: *const [64]u8) void {
    var x: [16]u32 = undefined;
    var i: usize = 0;
    while (i < 16) : (i += 1) {
        x[i] = std.mem.readInt(u32, block[i * 4 ..][0..4], .little);
    }

    var al = h[0];
    var bl = h[1];
    var cl = h[2];
    var dl = h[3];
    var el = h[4];
    var ar = h[0];
    var br = h[1];
    var cr = h[2];
    var dr = h[3];
    var er = h[4];

    var j: usize = 0;
    while (j < 80) : (j += 1) {
        var t = al +% f(j, bl, cl, dl) +% x[RL[j]] +% KL[j / 16];
        t = rotl(t, SL[j]) +% el;
        al = el;
        el = dl;
        dl = rotl(cl, 10);
        cl = bl;
        bl = t;

        t = ar +% f(79 - j, br, cr, dr) +% x[RR[j]] +% KR[j / 16];
        t = rotl(t, SR[j]) +% er;
        ar = er;
        er = dr;
        dr = rotl(cr, 10);
        cr = br;
        br = t;
    }

    const t = h[1] +% cl +% dr;
    h[1] = h[2] +% dl +% er;
    h[2] = h[3] +% el +% ar;
    h[3] = h[4] +% al +% br;
    h[4] = h[0] +% bl +% cr;
    h[0] = t;
}

pub const Ripemd160 = struct {
    h: [5]u32,
    buf: [64]u8,
    buf_len: usize,
    total_len: u64,

    pub fn init() Ripemd160 {
        return .{
            .h = .{ 0x67452301, 0xefcdab89, 0x98badcfe, 0x10325476, 0xc3d2e1f0 },
            .buf = undefined,
            .buf_len = 0,
            .total_len = 0,
        };
    }

    pub fn update(self: *Ripemd160, data: []const u8) void {
        var input = data;
        self.total_len +%= input.len;
        if (self.buf_len > 0) {
            const need = 64 - self.buf_len;
            const take = @min(need, input.len);
            @memcpy(self.buf[self.buf_len .. self.buf_len + take], input[0..take]);
            self.buf_len += take;
            input = input[take..];
            if (self.buf_len == 64) {
                processBlock(&self.h, self.buf[0..64]);
                self.buf_len = 0;
            }
        }
        while (input.len >= 64) {
            processBlock(&self.h, input[0..64]);
            input = input[64..];
        }
        if (input.len > 0) {
            @memcpy(self.buf[0..input.len], input);
            self.buf_len = input.len;
        }
    }

    pub fn final(self: *Ripemd160, out: *[20]u8) void {
        const bit_len = self.total_len * 8;
        // padding
        var pad: [128]u8 = undefined;
        @memset(&pad, 0);
        pad[0] = 0x80;
        const pad_len: usize = if (self.buf_len < 56) 56 - self.buf_len else 120 - self.buf_len;
        self.update(pad[0..pad_len]);
        var len_bytes: [8]u8 = undefined;
        std.mem.writeInt(u64, &len_bytes, bit_len, .little);
        self.update(&len_bytes);
        var i: usize = 0;
        while (i < 5) : (i += 1) {
            std.mem.writeInt(u32, out[i * 4 ..][0..4], self.h[i], .little);
        }
    }

    pub fn hash(data: []const u8, out: *[20]u8) void {
        var r = init();
        r.update(data);
        r.final(out);
    }
};

/// HASH160 = RIPEMD160(SHA256(data)) — Bitcoin address hash.
pub fn hash160(data: []const u8, out: *[20]u8) void {
    var sha = std.crypto.hash.sha2.Sha256.init(.{});
    sha.update(data);
    var mid: [32]u8 = undefined;
    sha.final(&mid);
    Ripemd160.hash(&mid, out);
}

test "ripemd160 empty" {
    var out: [20]u8 = undefined;
    Ripemd160.hash("", &out);
    const expect = [_]u8{ 0x9c, 0x11, 0x85, 0xa5, 0xc5, 0xe9, 0xfc, 0x54, 0x61, 0x28, 0x08, 0x97, 0x7e, 0xe8, 0xf5, 0x48, 0xb2, 0x25, 0x8d, 0x31 };
    try std.testing.expectEqualSlices(u8, &expect, &out);
}

test "ripemd160 abc" {
    var out: [20]u8 = undefined;
    Ripemd160.hash("abc", &out);
    const expect = [_]u8{ 0x8e, 0xb2, 0x08, 0xf7, 0xe0, 0x5d, 0x98, 0x7a, 0x9b, 0x04, 0x4a, 0x8e, 0x98, 0xc6, 0xb0, 0x87, 0xf1, 0x5a, 0x0b, 0xfc };
    try std.testing.expectEqualSlices(u8, &expect, &out);
}
