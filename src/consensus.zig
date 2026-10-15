const std = @import("std");

/// Amount in sats (1 ZiZZ = 100_000_000 sats)
pub const Amount = i64;
pub const COIN: Amount = 100_000_000;

/// Fizzlewick-inspired poetic subsidy for ZiZZ.
/// Integer only. Triangle wave ±20 on base 50, period 2100, + slow ~5% decay every 100k blocks.
pub fn getBlockSubsidy(height: u32) Amount {
    const PERIOD: u32 = 2100;
    const BASE: Amount = 50 * COIN;
    const AMP: Amount = 20 * COIN;

    // Slow decay: ~5% every 100_000 blocks (integer)
    const epochs: u32 = height / 100_000;
    var base: Amount = BASE;
    var i: u32 = 0;
    while (i < epochs and i < 40) : (i += 1) {
        base = @divFloor(base * 19, 20);
    }

    const phase: u32 = height % PERIOD;
    const half: u32 = PERIOD / 2;
    const t: u32 = if (phase <= half) phase else (PERIOD - phase);
    // wave = -AMP + (2 * AMP * t) / half
    const wave: Amount = -AMP + @divFloor(2 * AMP * @as(Amount, @intCast(t)), @as(Amount, @intCast(half)));

    var subsidy: Amount = base + wave;
    if (subsidy < 0) subsidy = 0;
    return subsidy;
}

/// Approximate ZiZZ (not sats) for display
pub fn subsidyToZiZZ(sats: Amount) f64 {
    return @as(f64, @floatFromInt(sats)) / @as(f64, @floatFromInt(COIN));
}

/// Chain identity parameters
pub const ChainParams = struct {
    name: []const u8 = "ZiZZ",
    ticker: []const u8 = "ZiZZ",
    magic: [4]u8 = .{ 0xf1, 0x7a, 0x7a, 0x22 }, // distinct from FIZZ f1 7a 7a 1f
    // Mainnet ports (public test platform)
    default_p2p_port: u16 = 8338,
    default_rpc_port: u16 = 8339,
    // Regtest ports
    regtest_p2p_port: u16 = 18447,
    regtest_rpc_port: u16 = 18448,
    datadir: []const u8 = "zizz",
    bech32_hrp: []const u8 = "zizz",
    pow_target_spacing: u32 = 120, // 2 minutes
    pow_target_timespan: u32 = 24 * 60 * 60, // 1 day retarget
    coinbase_maturity: u32 = 20,
    subsidy_period: u32 = 2100,
};

pub const PARAMS = ChainParams{};

test "poetic subsidy samples" {
    const expect = std.testing.expectApproxEqAbs;

    // h=0 → ~30
    try expect(subsidyToZiZZ(getBlockSubsidy(0)), 30.0, 0.01);
    // h=1050 → ~70
    try expect(subsidyToZiZZ(getBlockSubsidy(1050)), 70.0, 0.01);
    // h=2100 → ~30
    try expect(subsidyToZiZZ(getBlockSubsidy(2100)), 30.0, 0.01);
}
