const std = @import("std");
const consensus = @import("consensus.zig");
const block = @import("block.zig");
const hash = @import("hash.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        printHelp();
        return;
    }

    const cmd = args[1];

    if (std.mem.eql(u8, cmd, "subsidy")) {
        if (args.len < 3) {
            std.debug.print("Usage: zizz subsidy <height>\n", .{});
            return;
        }
        const height = try std.fmt.parseInt(u32, args[2], 10);
        const sats = consensus.getBlockSubsidy(height);
        const zizz = consensus.subsidyToZiZZ(sats);
        std.debug.print("height {d}: {d} sats (~{d:.2} ZiZZ)\n", .{ height, sats, zizz });
    } else if (std.mem.eql(u8, cmd, "info")) {
        const p = consensus.PARAMS;
        std.debug.print(
            \\ZiZZ — durable Bitcoin-family test chain (pure Zig)
            \\Name:    {s}
            \\Ticker:  {s}
            \\Magic:   {x:0>2}{x:0>2}{x:0>2}{x:0>2}
            \\P2P:     {d}
            \\RPC:     {d}
            \\Datadir: {s}
            \\HRP:     {s}
            \\Block time target: {d}s
            \\Subsidy: poetic triangle ±20 on base 50, period 2100 + slow decay
            \\PoW:     sha256d
            \\Not a monetary product. Engineering target only.
        , .{
            p.name,
            p.ticker,
            p.magic[0],
            p.magic[1],
            p.magic[2],
            p.magic[3],
            p.default_p2p_port,
            p.default_rpc_port,
            p.datadir,
            p.bech32_hrp,
            p.pow_target_spacing,
        });
    } else if (std.mem.eql(u8, cmd, "genesis")) {
        const hdr = block.createGenesisHeader();
        const hsh = hdr.hash();
        const hex = hash.hashToHex(hsh);
        std.debug.print("Genesis header hash: {s}\n", .{hex});
        std.debug.print("Timestamp: {d}\n", .{hdr.timestamp});
        std.debug.print("Bits: 0x{x}\n", .{hdr.bits});
        std.debug.print("Message: Lo, another ledger of flickering wicks. Mine if you must, but mind the smoke.\n", .{});
    } else if (std.mem.eql(u8, cmd, "hash")) {
        if (args.len < 3) {
            std.debug.print("Usage: zizz hash <hex-or-string>\n", .{});
            return;
        }
        // Simple: hash the raw argument bytes as demo
        const hsh = hash.sha256d(args[2]);
        const hex = hash.hashToHex(hsh);
        std.debug.print("sha256d: {s}\n", .{hex});
    } else if (std.mem.eql(u8, cmd, "--help") or std.mem.eql(u8, cmd, "-h") or std.mem.eql(u8, cmd, "help")) {
        printHelp();
    } else {
        std.debug.print("Unknown command: {s}\n", .{cmd});
        printHelp();
    }
}

fn printHelp() void {
    std.debug.print(
        \\ZiZZ — pure Zig Bitcoin-family durable test chain
        \\
        \\Usage:
        \\  zizz subsidy <height>   Compute poetic block subsidy at height
        \\  zizz info               Show chain identity and parameters
        \\  zizz genesis            Show genesis header hash
        \\  zizz hash <data>        Compute sha256d of a string
        \\  zizz --help             This message
        \\
        \\Example:
        \\  zizz subsidy 0
        \\  zizz subsidy 1050
        \\  zizz info
        \\  zizz genesis
        \\
        \\The wick stays lit.
    , .{});
}

test "modules" {
    _ = consensus;
    _ = block;
    _ = hash;
}
