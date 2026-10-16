const std = @import("std");
const dvui = @import("dvui");
const SDLBackend = @import("sdl-backend");

const chainmod = @import("chain.zig");

var status_buf: [160]u8 = undefined;
var status_len: usize = 0;

pub fn main(init: std.process.Init) !void {
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

        walletFrame(&chain) catch {};

        const end_micros = try win.end(.{});
        const wait_micros = win.waitTime(end_micros);
        interrupted = backend.waitEventTimeout(wait_micros) catch true;
    }
}

fn setStatus(msg: []const u8) void {
    const n = @min(msg.len, status_buf.len);
    @memcpy(status_buf[0..n], msg[0..n]);
    status_len = n;
}

fn walletFrame(chain: *chainmod.Chain) !void {
    var root = dvui.box(@src(), .{ .dir = .vertical }, .{
        .expand = .both,
        .margin = .{ .x = 20, .y = 16 },
    });
    defer root.deinit();

    // Header
    {
        var h = dvui.box(@src(), .{ .dir = .horizontal }, .{ .expand = .horizontal });
        defer h.deinit();
        dvui.label(@src(), "ZiZZ", .{}, .{ .font = .{ .size = 26 } });
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
            .margin = .{ .x = 0, .y = 14 },
            .padding = .{ .x = 16, .y = 14 },
            .background = true,
        });
        defer card.deinit();
        dvui.label(@src(), "Balance", .{}, .{});
        var tb: [48]u8 = undefined;
        const ts = std.fmt.bufPrint(&tb, "{d} sats", .{total}) catch "0";
        dvui.labelNoFmt(@src(), ts, .{}, .{ .font = .{ .size = 28 } });
    }

    // Buttons
    {
        var row = dvui.box(@src(), .{ .dir = .horizontal }, .{ .expand = .horizontal, .margin = .{ .x = 0, .y = 6 } });
        defer row.deinit();
        if (dvui.button(@src(), "Generate Block", .{}, .{})) {
            const addr = chain.getNewAddress() catch {
                setStatus("address error");
                return;
            };
            _ = chain.generateToAddress(1, addr) catch {
                setStatus("generate failed");
                return;
            };
            setStatus("Mined 1 block");
        }
        if (dvui.button(@src(), "New Address", .{}, .{})) {
            _ = chain.getNewAddress() catch {
                setStatus("address error");
                return;
            };
            setStatus("New address created");
        }
    }

    // Addresses
    dvui.label(@src(), "Addresses", .{}, .{ .margin = .{ .x = 0, .y = 10 } });
    {
        var scroll = dvui.scrollArea(@src(), .{}, .{ .expand = .both, .min_size_content = .{ .h = 200 } });
        defer scroll.deinit();
        var it = chain.balances.iterator();
        while (it.next()) |entry| {
            var row = dvui.box(@src(), .{ .dir = .horizontal }, .{
                .expand = .horizontal,
                .margin = .{ .x = 0, .y = 3 },
                .padding = .{ .x = 10, .y = 8 },
                .background = true,
            });
            defer row.deinit();
            var ab: [80]u8 = undefined;
            const as = std.fmt.bufPrint(&ab, "{s}", .{entry.key_ptr.*}) catch continue;
            dvui.labelNoFmt(@src(), as, .{}, .{ .expand = .horizontal });
            var bb: [40]u8 = undefined;
            const bs = std.fmt.bufPrint(&bb, "{d}", .{entry.value_ptr.*}) catch continue;
            dvui.labelNoFmt(@src(), bs, .{}, .{});
        }
    }

    if (status_len > 0) {
        dvui.labelNoFmt(@src(), status_buf[0..status_len], .{}, .{ .margin = .{ .x = 0, .y = 8 } });
    }
}
