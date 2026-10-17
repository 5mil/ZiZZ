const std = @import("std");
const dvui = @import("dvui");
const SDLBackend = @import("sdl-backend");

const chainmod = @import("chain.zig");

var status_buf: [160]u8 = undefined;
var status_len: usize = 0;
var show_console: bool = false;
var display_zizz: bool = true;
var log_lines: [32][120]u8 = undefined;
var log_lens: [32]usize = std.mem.zeroes([32]usize);
var log_count: usize = 0;

pub fn main(init: std.process.Init) !void {
    var backend = try SDLBackend.initWindow(.{
        .io = init.io,
        .environ_map = init.environ_map,
        .size = .{ .w = 960.0, .h = 700.0 },
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
    log("ZiZZ wallet started");

    var interrupted = true;
    while (window_open) {
        const nstime = win.beginWait(interrupted);
        try win.begin(nstime);

        walletFrame(&chain) catch {};

        const end_micros = try win.end(.{});
        const wait_micros = win.waitTime(end_micros);
        interrupted = backend.waitEventTimeout(wait_micros) catch true;
    }
}

fn log(msg: []const u8) void {
    if (log_count < log_lines.len) {
        const n = @min(msg.len, log_lines[0].len);
        @memcpy(log_lines[log_count][0..n], msg[0..n]);
        log_lens[log_count] = n;
        log_count += 1;
    } else {
        // shift
        var i: usize = 0;
        while (i < log_lines.len - 1) : (i += 1) {
            log_lines[i] = log_lines[i + 1];
            log_lens[i] = log_lens[i + 1];
        }
        const n = @min(msg.len, log_lines[0].len);
        @memcpy(log_lines[log_lines.len - 1][0..n], msg[0..n]);
        log_lens[log_lines.len - 1] = n;
    }
}

fn setStatus(msg: []const u8) void {
    const n = @min(msg.len, status_buf.len);
    @memcpy(status_buf[0..n], msg[0..n]);
    status_len = n;
    log(msg);
}

fn walletFrame(chain: *chainmod.Chain) !void {
    var root = dvui.box(@src(), .{ .dir = .vertical }, .{
        .expand = .both,
        .margin = .{ .x = 16, .y = 12 },
    });
    defer root.deinit();

    // Menu bar
    {
        var menu = dvui.menu(@src(), .horizontal, .{});
        defer menu.deinit();
        if (dvui.menuItemLabel(@src(), "Wallet", .{ .submenu = true }, .{})) |r| {
            var fm = dvui.floatingMenu(@src(), .{ .from = r }, .{});
            defer fm.deinit();
            if (dvui.menuItemLabel(@src(), "Generate Block", .{}, .{})) |_| {
                const addr = chain.getNewAddress() catch return;
                _ = chain.generateToAddress(1, addr) catch return;
                setStatus("Mined 1 block");
            }
            if (dvui.menuItemLabel(@src(), "New Address", .{}, .{})) |_| {
                _ = chain.getNewAddress() catch return;
                setStatus("New address");
            }
        }
        if (dvui.menuItemLabel(@src(), "Preferences", .{ .submenu = true }, .{})) |r| {
            var fm = dvui.floatingMenu(@src(), .{ .from = r }, .{});
            defer fm.deinit();
            if (dvui.menuItemLabel(@src(), if (display_zizz) "Show sats" else "Show ZiZZ", .{}, .{})) |_| {
                display_zizz = !display_zizz;
            }
        }

        if (dvui.menuItemLabel(@src(), "Window", .{ .submenu = true }, .{})) |r| {
            var fm = dvui.floatingMenu(@src(), .{ .from = r }, .{});
            defer fm.deinit();
            if (dvui.menuItemLabel(@src(), if (show_console) "Hide Console" else "Show Console", .{}, .{})) |_| {
                show_console = !show_console;
            }
        }
    }

    // Header
    {
        var h = dvui.box(@src(), .{ .dir = .horizontal }, .{ .expand = .horizontal, .margin = .{ .x = 0, .y = 8 } });
        defer h.deinit();
        dvui.label(@src(), "ZiZZ", .{}, .{ .font = .{ .size = 24 } });
        var sp = dvui.box(@src(), .{ .dir = .horizontal }, .{ .expand = .horizontal });
        sp.deinit();
        var hb: [32]u8 = undefined;
        const hs = std.fmt.bufPrint(&hb, "Height {d}", .{chain.tipHeight()}) catch "?";
        dvui.labelNoFmt(@src(), hs, .{}, .{});
    }

    // Balance
    var total: i64 = 0;
    {
        var it = chain.balances.iterator();
        while (it.next()) |e| total += e.value_ptr.*;
    }
    {
        var card = dvui.box(@src(), .{ .dir = .vertical }, .{
            .expand = .horizontal,
            .margin = .{ .x = 0, .y = 8 },
            .padding = .{ .x = 14, .y = 12 },
            .background = true,
        });
        defer card.deinit();
        dvui.label(@src(), "Balance", .{}, .{});
        var tb: [48]u8 = undefined;
        const ts = if (display_zizz) std.fmt.bufPrint(&tb, "{d:.8} ZiZZ", .{@as(f64, @floatFromInt(total)) / 100_000_000.0}) catch "0" else std.fmt.bufPrint(&tb, "{d} sats", .{total}) catch "0";
        dvui.labelNoFmt(@src(), ts, .{}, .{ .font = .{ .size = 26 } });
    }

    // Buttons
    {
        var row = dvui.box(@src(), .{ .dir = .horizontal }, .{ .expand = .horizontal, .margin = .{ .x = 0, .y = 4 } });
        defer row.deinit();
        if (dvui.button(@src(), "Generate Block", .{}, .{})) {
            const addr = chain.getNewAddress() catch return;
            _ = chain.generateToAddress(1, addr) catch return;
            setStatus("Mined 1 block");
        }
        if (dvui.button(@src(), "New Address", .{}, .{})) {
            _ = chain.getNewAddress() catch return;
            setStatus("New address");
        }
        if (dvui.button(@src(), if (show_console) "Hide Console" else "Console", .{}, .{})) {
            show_console = !show_console;
        }
    }

    // Addresses
    dvui.label(@src(), "Addresses", .{}, .{ .margin = .{ .x = 0, .y = 8 } });
    {
        var scroll = dvui.scrollArea(@src(), .{}, .{ .expand = .both, .min_size_content = .{ .h = 160 } });
        defer scroll.deinit();
        var it = chain.balances.iterator();
        while (it.next()) |entry| {
            var row = dvui.box(@src(), .{ .dir = .horizontal }, .{
                .expand = .horizontal,
                .margin = .{ .x = 0, .y = 2 },
                .padding = .{ .x = 8, .y = 6 },
                .background = true,
            });
            defer row.deinit();
            var ab: [80]u8 = undefined;
            const as = std.fmt.bufPrint(&ab, "{s}", .{entry.key_ptr.*}) catch continue;
            dvui.labelNoFmt(@src(), as, .{}, .{ .expand = .horizontal });
            var bb: [40]u8 = undefined;
            const bs = if (display_zizz) std.fmt.bufPrint(&bb, "{d:.8}", .{@as(f64, @floatFromInt(entry.value_ptr.*)) / 100_000_000.0}) catch continue else std.fmt.bufPrint(&bb, "{d}", .{entry.value_ptr.*}) catch continue;
            dvui.labelNoFmt(@src(), bs, .{}, .{});
        }
    }

    // Console panel
    if (show_console) {
        dvui.label(@src(), "Console", .{}, .{ .margin = .{ .x = 0, .y = 8 } });
        var cscroll = dvui.scrollArea(@src(), .{}, .{ .expand = .horizontal, .min_size_content = .{ .h = 140 }, .background = true });
        defer cscroll.deinit();
        var i: usize = 0;
        while (i < log_count) : (i += 1) {
            dvui.labelNoFmt(@src(), log_lines[i][0..log_lens[i]], .{}, .{});
        }
    }

    if (status_len > 0 and !show_console) {
        dvui.labelNoFmt(@src(), status_buf[0..status_len], .{}, .{ .margin = .{ .x = 0, .y = 6 } });
    }
}
