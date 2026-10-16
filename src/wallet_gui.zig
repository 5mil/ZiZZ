const std = @import("std");
const dvui = @import("dvui");
const SDLBackend = @import("sdl-backend");

const chainmod = @import("chain.zig");

var send_to_buf: [128]u8 = undefined;
var send_to_len: usize = 0;
var send_amt_buf: [32]u8 = undefined;
var send_amt_len: usize = 0;
var status_msg: [160]u8 = undefined;
var status_len: usize = 0;

pub fn main(init: std.process.Init) !void {
    if (@import("builtin").os.tag == .windows) {
        dvui.Backend.Common.windowsAttachConsole() catch {};
    }

    var backend = try SDLBackend.initWindow(.{
        .io = init.io,
        .environ_map = init.environ_map,
        .size = .{ .w = 980.0, .h = 720.0 },
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

fn setStatus(msg: []const u8) void {
    const n = @min(msg.len, status_msg.len);
    @memcpy(status_msg[0..n], msg[0..n]);
    status_len = n;
}

fn walletFrame(chain: *chainmod.Chain) !void {
    var root = dvui.box(@src(), .{ .dir = .vertical }, .{
        .expand = .both,
        .margin = .{ .x = 16, .y = 16 },
        .background = true,
        .color_fill = .{ .color = .{ .r = 28, .g = 30, .b = 36, .a = 255 } },
    });
    defer root.deinit();

    // Header
    {
        var header = dvui.box(@src(), .{ .dir = .horizontal }, .{ .expand = .horizontal });
        defer header.deinit();
        dvui.label(@src(), "ZiZZ", .{}, .{ .font = .{ .size = 28 } });
        var spacer = dvui.box(@src(), .{ .dir = .horizontal }, .{ .expand = .horizontal });
        spacer.deinit();
        var hbuf: [40]u8 = undefined;
        const hs = std.fmt.bufPrint(&hbuf, "Height  {d}", .{chain.tipHeight()}) catch "Height  ?";
        dvui.labelNoFmt(@src(), hs, .{}, .{});
    }

    // Total balance card
    var total: i64 = 0;
    {
        var it = chain.balances.iterator();
        while (it.next()) |e| total += e.value_ptr.*;
    }
    {
        var card = dvui.box(@src(), .{ .dir = .vertical }, .{
            .expand = .horizontal,
            .margin = .{ .x = 0, .y = 12 },
            .padding = .{ .x = 16, .y = 16 },
            .background = true,
            .color_fill = .{ .color = .{ .r = 42, .g = 48, .b = 62, .a = 255 } },
        });
        defer card.deinit();
        dvui.label(@src(), "Total Balance", .{}, .{});
        var tbuf: [48]u8 = undefined;
        const ts = std.fmt.bufPrint(&tbuf, "{d} sats", .{total}) catch "0 sats";
        dvui.labelNoFmt(@src(), ts, .{}, .{ .font = .{ .size = 32 } });
    }

    // Actions
    {
        var actions = dvui.box(@src(), .{ .dir = .horizontal }, .{ .expand = .horizontal, .margin = .{ .x = 0, .y = 8 } });
        defer actions.deinit();
        if (dvui.button(@src(), "Generate Block", .{}, .{})) {
            const addr = try chain.getNewAddress();
            _ = try chain.generateToAddress(1, addr);
            setStatus("Mined 1 block to new address");
        }
        if (dvui.button(@src(), "New Address", .{}, .{})) {
            _ = try chain.getNewAddress();
            setStatus("Created new address");
        }
    }

    // Address list
    dvui.label(@src(), "Addresses", .{}, .{ .margin = .{ .x = 0, .y = 8 } });
    {
        var scroll = dvui.scrollArea(@src(), .{}, .{ .expand = .both, .min_size_content = .{ .h = 220 } });
        defer scroll.deinit();
        var it = chain.balances.iterator();
        while (it.next()) |entry| {
            var row = dvui.box(@src(), .{ .dir = .horizontal }, .{
                .expand = .horizontal,
                .margin = .{ .x = 0, .y = 4 },
                .padding = .{ .x = 12, .y = 10 },
                .background = true,
                .color_fill = .{ .color = .{ .r = 36, .g = 40, .b = 50, .a = 255 } },
            });
            defer row.deinit();
            var abuf: [80]u8 = undefined;
            const as = std.fmt.bufPrint(&abuf, "{s}", .{entry.key_ptr.*}) catch continue;
            dvui.labelNoFmt(@src(), as, .{}, .{ .expand = .horizontal });
            var bbuf: [40]u8 = undefined;
            const bs = std.fmt.bufPrint(&bbuf, "{d} sats", .{entry.value_ptr.*}) catch continue;
            dvui.labelNoFmt(@src(), bs, .{}, .{});
        }
    }

    // Send form
    dvui.label(@src(), "Send", .{}, .{ .margin = .{ .x = 0, .y = 10 } });
    {
        var form = dvui.box(@src(), .{ .dir = .horizontal }, .{ .expand = .horizontal });
        defer form.deinit();
        var to_entry = dvui.textEntry(@src(), .{
            .text = .{ .buffer = send_to_buf[0..send_to_len] },
            .placeholder = "to address",
        }, .{ .expand = .horizontal });
        defer to_entry.deinit();
        send_to_len = to_entry.len;

        var amt_entry = dvui.textEntry(@src(), .{
            .text = .{ .buffer = send_amt_buf[0..send_amt_len] },
            .placeholder = "amount",
        }, .{ .min_size_content = .{ .w = 120 } });
        defer amt_entry.deinit();
        send_amt_len = amt_entry.len;

        if (dvui.button(@src(), "Send", .{}, .{})) {
            const to = send_to_buf[0..send_to_len];
            const amt_str = send_amt_buf[0..send_amt_len];
            const amt = std.fmt.parseInt(u64, amt_str, 10) catch {
                setStatus("Invalid amount");
                return;
            };
            // send from first address that has enough
            var from: ?[]const u8 = null;
            var it = chain.balances.iterator();
            while (it.next()) |e| {
                if (e.value_ptr.* >= amt) {
                    from = e.key_ptr.*;
                    break;
                }
            }
            if (from) |f| {
                chain.sendToAddress(f, to, @intCast(amt)) catch |err| {
                    setStatus(@errorName(err));
                    return;
                };
                setStatus("Sent");
                send_to_len = 0;
                send_amt_len = 0;
            } else {
                setStatus("No address has enough");
            }
        }
    }

    if (status_len > 0) {
        dvui.labelNoFmt(@src(), status_msg[0..status_len], .{}, .{ .margin = .{ .x = 0, .y = 8 } });
    }
}
