const std = @import("std");
const consensus = @import("consensus.zig");
const block = @import("block.zig");
const hash = @import("hash.zig");
const chainmod = @import("chain.zig");
const rpcmod = @import("rpc.zig");

pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const args = try init.minimal.args.toSlice(allocator);

    if (args.len < 2) {
        printHelp();
        return;
    }

    const cmd = args[1];

    if (std.mem.eql(u8, cmd, "node")) {
        try runNode(allocator, args, init.io);
    } else if (std.mem.eql(u8, cmd, "subsidy")) {
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
            \\Mainnet P2P/RPC: {d}/{d}
            \\Regtest P2P/RPC: {d}/{d}
            \\Datadir: {s}
            \\HRP:     {s}
            \\Block time: {d}s   Retarget: {d}s
            \\Coinbase maturity: {d}
            \\Subsidy: poetic triangle ±20 on base 50, period 2100 + slow decay
            \\PoW:     sha256d
            \\Not a monetary product. Engineering target only.
            \\
        , .{
            p.name,
            p.ticker,
            p.magic[0],
            p.magic[1],
            p.magic[2],
            p.magic[3],
            p.default_p2p_port,
            p.default_rpc_port,
            p.regtest_p2p_port,
            p.regtest_rpc_port,
            p.datadir,
            p.bech32_hrp,
            p.pow_target_spacing,
            p.pow_target_timespan,
            p.coinbase_maturity,
        });
    } else if (std.mem.eql(u8, cmd, "genesis")) {
        const hdr = block.createGenesisHeader();
        const hsh = hdr.getHash();
        const hex = hash.hashToHex(hsh);
        std.debug.print("Genesis header hash: {s}\n", .{&hex});
        std.debug.print("Timestamp: {d}\n", .{hdr.timestamp});
        std.debug.print("Bits: 0x{x}\n", .{hdr.bits});
        std.debug.print("Message: Lo, another ledger of flickering wicks. Mine if you must, but mind the smoke.\n", .{});
    } else if (std.mem.eql(u8, cmd, "hash")) {
        if (args.len < 3) {
            std.debug.print("Usage: zizz hash <hex-or-string>\n", .{});
            return;
        }
        const hsh = hash.sha256d(args[2]);
        const hex = hash.hashToHex(hsh);
        std.debug.print("sha256d: {s}\n", .{&hex});
    } else if (std.mem.eql(u8, cmd, "--help") or std.mem.eql(u8, cmd, "-h") or std.mem.eql(u8, cmd, "help")) {
        printHelp();
    } else {
        std.debug.print("Unknown command: {s}\n", .{cmd});
        printHelp();
    }
}

fn runNode(allocator: std.mem.Allocator, args: []const []const u8, io: std.Io) !void {
    var regtest = false;
    var port: u16 = consensus.PARAMS.default_rpc_port;

    for (args[2..]) |arg| {
        if (std.mem.eql(u8, arg, "--regtest")) {
            regtest = true;
            port = consensus.PARAMS.regtest_rpc_port;
        } else if (std.mem.startsWith(u8, arg, "--rpcport=")) {
            port = try std.fmt.parseInt(u16, arg["--rpcport=".len..], 10);
        }
    }

    var chain = chainmod.Chain.init(allocator, io);
    defer chain.deinit();
    std.debug.print("calling ensureGenesis\n", .{});
    try chain.ensureGenesis();
    std.debug.print("ensureGenesis done, height={d}\n", .{chain.tipHeight()});

    const mode = if (regtest) "regtest" else "mainnet";
    std.debug.print("ZiZZ {s} node starting (in-memory chain)\n", .{mode});
    std.debug.print("Genesis tip: {s}\n", .{&chain.tipHashHex()});
    std.debug.print("RPC port: {d}\n", .{port});

    const chain_name = if (regtest) "regtest" else "main";
    var server = rpcmod.RpcServer.init(allocator, &chain, port, chain_name, io);
    try server.start();
}

fn printHelp() void {
    std.debug.print(
        \\ZiZZ — pure Zig Bitcoin-family durable test chain
        \\
        \\Usage:
        \\  zizz node [--regtest] [--rpcport=N]       Start node (mainnet by default)
        \\  zizz subsidy <height>                     Compute poetic block subsidy
        \\  zizz info                                  Show chain identity
        \\  zizz genesis                               Show genesis header hash
        \\  zizz hash <data>                           Compute sha256d
        \\  zizz --help                                This message
        \\
        \\Mainnet launch:
        \\  ./zig-out/bin/zizz node
        \\  See MAINNET.md
        \\
        \\Regtest:
        \\  ./zig-out/bin/zizz node --regtest
        \\
        \\The wick stays lit.
        \\
    , .{});
}
