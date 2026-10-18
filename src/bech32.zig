//! BIP-173 Bech32 and BIP-350 Bech32m for native segwit addresses.
//! HRP for ZiZZ mainnet: "zizz"
//! - P2WPKH: witver 0 + 20-byte program → Bech32
//! - P2WSH:  witver 0 + 32-byte program → Bech32
//! - P2TR:   witver 1 + 32-byte x-only  → Bech32m

const std = @import("std");

pub const hrp_main = "zizz";
pub const charset = "qpzry9x8gf2tvdw0s3jn54khce6mua7l";

const gen = [_]u32{ 0x3b6a57b2, 0x26508e6d, 0x1ea119fa, 0x3d4233dd, 0x2a1462b3 };

pub const Encoding = enum {
    bech32, // BIP173 constant 1
    bech32m, // BIP350 constant 0x2bc830a3
};

fn polymod(values: []const u5) u32 {
    var chk: u32 = 1;
    for (values) |v| {
        const b = chk >> 25;
        chk = ((chk & 0x1ffffff) << 5) ^ @as(u32, v);
        inline for (0..5) |i| {
            if (((b >> i) & 1) != 0) chk ^= gen[i];
        }
    }
    return chk;
}

fn hrpExpand(hrp: []const u8, out: []u5) usize {
    var i: usize = 0;
    for (hrp) |c| {
        out[i] = @intCast(c >> 5);
        i += 1;
    }
    out[i] = 0;
    i += 1;
    for (hrp) |c| {
        out[i] = @intCast(c & 31);
        i += 1;
    }
    return i;
}

fn encodingConstant(enc: Encoding) u32 {
    return switch (enc) {
        .bech32 => 1,
        .bech32m => 0x2bc830a3,
    };
}

/// Convert 8-bit bytes to 5-bit groups (pad with zeros).
pub fn convertBits(
    out: []u5,
    data: []const u8,
    from_bits: u6,
    to_bits: u6,
    pad: bool,
) !usize {
    var acc: u32 = 0;
    var bits: u6 = 0;
    var n: usize = 0;
    const maxv: u32 = (@as(u32, 1) << to_bits) - 1;
    for (data) |value| {
        acc = (acc << from_bits) | value;
        bits += from_bits;
        while (bits >= to_bits) {
            bits -= to_bits;
            if (n >= out.len) return error.NoSpace;
            out[n] = @intCast((acc >> bits) & maxv);
            n += 1;
        }
    }
    if (pad) {
        if (bits > 0) {
            if (n >= out.len) return error.NoSpace;
            out[n] = @intCast((acc << @as(u6, @intCast(to_bits - bits))) & maxv);
            n += 1;
        }
    } else if (bits >= from_bits or ((acc << @as(u6, @intCast(to_bits - bits))) & maxv) != 0) {
        return error.InvalidPadding;
    }
    return n;
}

fn createChecksum(hrp: []const u8, data: []const u5, enc: Encoding, out: *[6]u5) void {
    var values: [200]u5 = undefined;
    const hn = hrpExpand(hrp, values[0..]);
    @memcpy(values[hn..][0..data.len], data);
    const total = hn + data.len + 6;
    @memset(values[hn + data.len ..][0..6], 0);
    const mod = polymod(values[0..total]) ^ encodingConstant(enc);
    var i: usize = 0;
    while (i < 6) : (i += 1) {
        out[i] = @intCast((mod >> @intCast(5 * (5 - i))) & 31);
    }
}

fn verifyChecksum(hrp: []const u8, data: []const u5) ?Encoding {
    var values: [200]u5 = undefined;
    const hn = hrpExpand(hrp, values[0..]);
    if (hn + data.len > values.len) return null;
    @memcpy(values[hn..][0..data.len], data);
    const pm = polymod(values[0 .. hn + data.len]);
    if (pm == encodingConstant(.bech32)) return .bech32;
    if (pm == encodingConstant(.bech32m)) return .bech32m;
    return null;
}

/// Encode HRP + 5-bit data payload (no witver yet) with checksum.
pub fn encode(hrp: []const u8, data: []const u5, enc: Encoding, out: []u8) ![]const u8 {
    if (hrp.len < 1 or hrp.len > 83) return error.InvalidHrp;
    for (hrp) |c| {
        if (c < 33 or c > 126) return error.InvalidHrp;
        if (c >= 'A' and c <= 'Z') return error.InvalidHrp; // lowercase only
    }
    var chk: [6]u5 = undefined;
    createChecksum(hrp, data, enc, &chk);
    var n: usize = 0;
    if (out.len < hrp.len + 1 + data.len + 6) return error.NoSpace;
    @memcpy(out[0..hrp.len], hrp);
    n = hrp.len;
    out[n] = '1';
    n += 1;
    for (data) |d| {
        out[n] = charset[d];
        n += 1;
    }
    for (chk) |d| {
        out[n] = charset[d];
        n += 1;
    }
    return out[0..n];
}

pub const Decoded = struct {
    hrp: []const u8,
    data: []const u5, // includes witver as first element for segwit
    encoding: Encoding,
};

/// Decode a bech32/bech32m string into HRP and 5-bit data (data includes checksum stripped).
pub fn decode(addr: []const u8, hrp_out: []u8, data_out: []u5) !struct { hrp_len: usize, data_len: usize, encoding: Encoding } {
    if (addr.len < 8 or addr.len > 90) return error.InvalidLength;
    var has_lower = false;
    var has_upper = false;
    for (addr) |c| {
        if (c < 33 or c > 126) return error.InvalidChar;
        if (c >= 'a' and c <= 'z') has_lower = true;
        if (c >= 'A' and c <= 'Z') has_upper = true;
    }
    if (has_lower and has_upper) return error.MixedCase;

    // find last '1'
    var sep: ?usize = null;
    var i: usize = 0;
    while (i < addr.len) : (i += 1) {
        if (addr[i] == '1' or addr[i] == '1') sep = i; // always '1'
        if (addr[i] == '1') sep = i;
    }
    // correct loop:
    sep = null;
    i = 0;
    while (i < addr.len) : (i += 1) {
        if (addr[i] == '1') sep = i;
    }
    const sep_i = sep orelse return error.NoSeparator;
    if (sep_i < 1 or sep_i + 7 > addr.len) return error.InvalidSeparator;

    const hrp_raw = addr[0..sep_i];
    if (hrp_raw.len > hrp_out.len) return error.NoSpace;
    for (hrp_raw, 0..) |c, j| {
        const lc: u8 = if (c >= 'A' and c <= 'Z') c + 32 else c;
        hrp_out[j] = lc;
    }

    const data_part = addr[sep_i + 1 ..];
    if (data_part.len < 6) return error.InvalidChecksum;
    const values_len = data_part.len;
    if (values_len > data_out.len) return error.NoSpace;

    var values: [90]u5 = undefined;
    for (data_part, 0..) |c, j| {
        const lc: u8 = if (c >= 'A' and c <= 'Z') c + 32 else c;
        const idx = std.mem.indexOfScalar(u8, charset, lc) orelse return error.InvalidChar;
        values[j] = @intCast(idx);
    }

    const enc = verifyChecksum(hrp_out[0..hrp_raw.len], values[0..values_len]) orelse return error.InvalidChecksum;
    const data_len = values_len - 6;
    @memcpy(data_out[0..data_len], values[0..data_len]);
    return .{ .hrp_len = hrp_raw.len, .data_len = data_len, .encoding = enc };
}

/// Encode a native segwit address.
pub fn encodeSegwit(hrp: []const u8, witver: u5, program: []const u8, out: []u8) ![]const u8 {
    if (witver > 16) return error.InvalidWitnessVersion;
    if (program.len < 2 or program.len > 40) return error.InvalidProgramLength;
    if (witver == 0 and program.len != 20 and program.len != 32) return error.InvalidProgramLength;
    if (witver == 0 and program.len == 20) {
        // P2WPKH ok
    }

    var prog5: [65]u5 = undefined;
    const n5 = try convertBits(prog5[0..], program, 8, 5, true);
    var data: [66]u5 = undefined;
    data[0] = witver;
    @memcpy(data[1 .. 1 + n5], prog5[0..n5]);

    const enc: Encoding = if (witver == 0) .bech32 else .bech32m;
    return encode(hrp, data[0 .. 1 + n5], enc, out);
}

/// 5-bit → 8-bit
fn convertBits5to8(out: []u8, data: []const u5, pad: bool) !usize {
    var acc: u32 = 0;
    var bits: u6 = 0;
    var n: usize = 0;
    const maxv: u32 = 255;
    for (data) |value| {
        acc = (acc << 5) | @as(u32, value);
        bits += 5;
        while (bits >= 8) {
            bits -= 8;
            if (n >= out.len) return error.NoSpace;
            out[n] = @intCast((acc >> bits) & maxv);
            n += 1;
        }
    }
    if (!pad) {
        if (bits >= 5 or ((acc << @as(u6, @intCast(8 - bits))) & maxv) != 0) return error.InvalidPadding;
    }
    return n;
}

pub fn decodeSegwitAddress(addr: []const u8, hrp_expect: []const u8, program_out: []u8) !struct { witver: u5, program_len: usize } {
    var hrp_buf: [84]u8 = undefined;
    var data5: [90]u5 = undefined;
    const d = try decode(addr, &hrp_buf, &data5);
    if (!std.mem.eql(u8, hrp_buf[0..d.hrp_len], hrp_expect)) return error.WrongHrp;
    if (d.data_len < 1) return error.InvalidData;
    const witver: u5 = data5[0];
    if (witver > 16) return error.InvalidWitnessVersion;
    if (witver == 0 and d.encoding != .bech32) return error.WrongEncoding;
    if (witver != 0 and d.encoding != .bech32m) return error.WrongEncoding;

    const plen = try convertBits5to8(program_out, data5[1..d.data_len], false);
    if (plen < 2 or plen > 40) return error.InvalidProgramLength;
    if (witver == 0 and plen != 20 and plen != 32) return error.InvalidProgramLength;
    return .{ .witver = witver, .program_len = plen };
}

/// True if `addr` is a valid lowercase `zizz1…` segwit address (checksum + rules).
pub fn isValidZizzAddress(addr: []const u8) bool {
    var prog: [40]u8 = undefined;
    _ = decodeSegwitAddress(addr, hrp_main, &prog) catch return false;
    return true;
}

test "bech32 bip173 empty hrp example style" {
    // Encode witver 0 + 20 zero bytes as smoke test of checksum length
    var prog = [_]u8{0} ** 20;
    var buf: [90]u8 = undefined;
    const s = try encodeSegwit("bc", 0, &prog, &buf);
    try std.testing.expect(s.len > 10);
    try std.testing.expect(std.mem.startsWith(u8, s, "bc1"));
    var outp: [40]u8 = undefined;
    const d = try decodeSegwitAddress(s, "bc", &outp);
    try std.testing.expectEqual(@as(u5, 0), d.witver);
    try std.testing.expectEqual(@as(usize, 20), d.program_len);
}

test "zizz p2wpkh roundtrip" {
    var prog: [20]u8 = .{
        0x75, 0x1e, 0x76, 0xe8, 0x19, 0x91, 0x96, 0xd4, 0x54, 0x94,
        0x1c, 0x45, 0xd1, 0xb3, 0xa3, 0x23, 0xf1, 0x43, 0x3b, 0xd6,
    };
    var buf: [90]u8 = undefined;
    const s = try encodeSegwit(hrp_main, 0, &prog, &buf);
    try std.testing.expect(std.mem.startsWith(u8, s, "zizz1q"));
    try std.testing.expect(isValidZizzAddress(s));
    var outp: [40]u8 = undefined;
    const d = try decodeSegwitAddress(s, hrp_main, &outp);
    try std.testing.expectEqualSlices(u8, &prog, outp[0..d.program_len]);
}

test "zizz p2tr bech32m" {
    var prog: [32]u8 = .{0xab} ** 32;
    var buf: [90]u8 = undefined;
    const s = try encodeSegwit(hrp_main, 1, &prog, &buf);
    try std.testing.expect(std.mem.startsWith(u8, s, "zizz1p"));
    try std.testing.expect(isValidZizzAddress(s));
    // typo should fail
    var bad_buf: [90]u8 = undefined;
    @memcpy(bad_buf[0..s.len], s);
    bad_buf[s.len - 2] = if (bad_buf[s.len - 2] == 'q') 'p' else 'q';
    try std.testing.expect(!isValidZizzAddress(bad_buf[0..s.len]));
}
