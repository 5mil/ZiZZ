const std = @import("std");
const dvui = @import("dvui");
const SDLBackend = @import("sdl-backend");
const chainmod = @import("chain.zig");

var splash_frames: u32 = 60;

pub fn main(init: std.process.Init) !void {
    var backend = try SDLBackend.initWindow(.{
        .io = init.io,
        .environ_map = init.environ_map,
        .size = .{ .w = 800.0, .h = 600.0 },
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
        try backend.addAllEvents(&win);

        if (splash_frames > 0) {
            var root = dvui.box(@src(), .{ .dir = .vertical }, .{ .expand = .both });
            defer root.deinit();
            dvui.label(@src(), "ZiZZ", .{}, .{ .font = .{ .size = 48 } });
            dvui.label(@src(), "Loading...", .{}, .{});
            splash_frames -= 1;
        } else {
            var root = dvui.box(@src(), .{ .dir = .vertical }, .{ .expand = .both, .margin = .{ .x = 16, .y = 16 } });
            defer root.deinit();
            dvui.label(@src(), "ZiZZ Wallet", .{}, .{ .font = .{ .size = 24 } });
            var total: i64 = 0;
            var it = chain.balances.iterator();
            while (it.next()) |e| total += e.value_ptr.*;
            var buf: [48]u8 = undefined;
            const s = std.fmt.bufPrint(&buf, "{d:.8} ZiZZ", .{@as(f64, @floatFromInt(total)) / 100_000_000.0}) catch "0";
            dvui.labelNoFmt(@src(), s, .{}, .{ .font = .{ .size = 28 } });
            if (dvui.button(@src(), "Generate Block", .{}, .{})) {
                const addr = chain.getNewAddress() catch continue;
                _ = chain.generateToAddress(1, addr) catch {};
            }
        }

        const end_micros = try win.end(.{});
        const wait_micros = win.waitTime(end_micros);
        interrupted = backend.waitEventTimeout(@min(wait_micros, 16000)) catch true;
    }
}
