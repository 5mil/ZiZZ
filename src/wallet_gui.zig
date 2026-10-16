const std = @import("std");
const dvui = @import("dvui");
const SDLBackend = @import("sdl-backend");

const chainmod = @import("chain.zig");

pub fn main(init: std.process.Init) !void {
    if (@import("builtin").os.tag == .windows) {
        dvui.Backend.Common.windowsAttachConsole() catch {};
    }

    var backend = try SDLBackend.initWindow(.{
        .io = init.io,
        .environ_map = init.environ_map,
        .size = .{ .w = 900.0, .h = 640.0 },
        .vsync = true,
        .title = "ZiZZ Wallet",
    });
    defer backend.deinit();

    var window_open = true;
    var win = try dvui.Window.init(@src(), init.gpa, backend.backend(), .{
        .theme = dvui.Theme.builtin.adwaita_dark,
        .open_flag = &window_open,
    });
    defer win.deinit();

    var chain = chainmod.Chain.init(init.gpa, init.io);
    defer chain.deinit();
    try chain.ensureGenesis();

    var interrupted = true;
    while (window_open) {
        const nstime = win.beginWait(interrupted);
        try win.begin(nstime);

        try walletFrame(&chain);

        const end_micros = try win.end(.{});
        const wait_micros = win.waitTime(end_micros);
        interrupted = try backend.waitEventTimeout(wait_micros);
    }
}

fn walletFrame(chain: *chainmod.Chain) !void {
    var vbox = dvui.box(@src(), .{ .dir = .vertical }, .{ .expand = .both, .margin = .{ .x = 12, .y = 12 } });
    defer vbox.deinit();

    dvui.label(@src(), "ZiZZ Wallet", .{}, .{});

    var height_buf: [32]u8 = undefined;
    const height_str = std.fmt.bufPrint(&height_buf, "Height: {d}", .{chain.tipHeight()}) catch "Height: ?";
    dvui.labelNoFmt(@src(), height_str, .{}, .{});

    if (dvui.button(@src(), "Generate 1 Block", .{}, .{})) {
        const addr = try chain.getNewAddress();
        _ = try chain.generateToAddress(1, addr);
    }

    if (dvui.button(@src(), "New Address", .{}, .{})) {
        _ = try chain.getNewAddress();
    }

    dvui.label(@src(), "Balances", .{}, .{});

    var it = chain.balances.iterator();
    while (it.next()) |entry| {
        var buf: [160]u8 = undefined;
        const line = std.fmt.bufPrint(&buf, "{s}: {d} sats", .{ entry.key_ptr.*, entry.value_ptr.* }) catch continue;
        dvui.labelNoFmt(@src(), line, .{}, .{});
    }
}
