const std = @import("std");
const dvui = @import("dvui");
const SDLBackend = @import("sdl-backend");

const chainmod = @import("chain.zig");
const explorer = @import("explorer.zig");
const logo_bytes = @embedFile("assets/zizz-logo.jpg");

const Tab = enum { overview, send, receive, transactions, addresses };

var status_buf: [160]u8 = undefined;
var status_len: usize = 0;
var show_console: bool = false;
var display_zizz: bool = true;
var current_tab: Tab = .overview;
var log_lines: [32][120]u8 = undefined;
var log_lens: [32]usize = std.mem.zeroes([32]usize);
var log_count: usize = 0;

var splash_frames: u32 = 180; // ~1.5s at 60fps
var node_connected: bool = true;
var send_to: [128]u8 = undefined;
var send_to_len: usize = 0;
var send_amt: [32]u8 = undefined;
var send_amt_len: usize = 0;


pub fn main(init: std.process.Init) !void {
    var backend = try SDLBackend.initWindow(.{
        .io = init.io,
        .environ_map = init.environ_map,
        .size = .{ .w = 1000.0, .h = 680.0 },
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
    explorer.start(&chain, init.io, init.gpa);
    log("ZiZZ wallet started");

    var interrupted = true;
    while (window_open) {
        const nstime = win.beginWait(interrupted);
        try win.begin(nstime);
        try backend.addAllEvents(&win);

        if (splash_frames > 0) {
            splashFrame();
            splash_frames -= 1;
        } else {
            walletFrame(&chain) catch {};
        }

        const end_micros = try win.end(.{});
        const wait_micros = win.waitTime(end_micros);
        interrupted = backend.waitEventTimeout(@min(wait_micros, 16000)) catch true;
    }
}

fn splashFrame() void {
    var root = dvui.box(@src(), .{ .dir = .vertical }, .{ .expand = .both, .background = true, .color_fill = .{ .color = .{ .r = 10, .g = 12, .b = 20, .a = 255 } } });
    defer root.deinit();

    var center = dvui.box(@src(), .{ .dir = .vertical }, .{ .expand = .both, .gravity_y = 0.5 });
    defer center.deinit();

    // Logo image
    _ = dvui.image(@src(), .{ .source = .{ .imageFile = .{ .bytes = logo_bytes, .name = "zizz-logo" } } }, .{ .min_size_content = .{ .w = 480, .h = 320 } });
    

    dvui.label(@src(), "Loading wallet...", .{}, .{ .margin = .{ .x = 0, .y = 12 } });
}

fn log(msg: []const u8) void {
    if (log_count < log_lines.len) {
        const n = @min(msg.len, log_lines[0].len);
        @memcpy(log_lines[log_count][0..n], msg[0..n]);
        log_lens[log_count] = n;
        log_count += 1;
    } else {
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

fn fmtAmount(buf: []u8, sats: i64) []const u8 {
    if (display_zizz) {
        return std.fmt.bufPrint(buf, "{d:.8} ZiZZ", .{ @as(f64, @floatFromInt(sats)) / 100_000_000.0 }) catch "0";
    } else {
        return std.fmt.bufPrint(buf, "{d} sats", .{sats}) catch "0";
    }
}

fn walletFrame(chain: *chainmod.Chain) !void {
    var root = dvui.box(@src(), .{ .dir = .vertical }, .{ .expand = .both });
    defer root.deinit();


    // Menu bar
    {
        var m = dvui.menu(@src(), .horizontal, .{});
        defer m.deinit();
        if (dvui.menuItemLabel(@src(), "File", .{ .submenu = true }, .{})) |r| {
            var fw = dvui.floatingMenu(@src(), .{ .from = r }, .{});
            defer fw.deinit();
            if (dvui.menuItemLabel(@src(), "Generate Block", .{}, .{}) != null) {
                const addr = chain.getNewAddress() catch return;
                _ = chain.generateToAddress(1, addr) catch return;
                setStatus("Mined 1 block");
                m.close();
            }
        }
        if (dvui.menuItemLabel(@src(), "Settings", .{ .submenu = true }, .{})) |r| {
            var fw = dvui.floatingMenu(@src(), .{ .from = r }, .{});
            defer fw.deinit();
            if (dvui.menuItemLabel(@src(), if (display_zizz) "Display: sats" else "Display: ZiZZ", .{}, .{}) != null) {
                display_zizz = !display_zizz;
                m.close();
            }
            if (dvui.menuItemLabel(@src(), if (show_console) "Hide Console" else "Show Console", .{}, .{}) != null) {
                show_console = !show_console;
                m.close();
            }
        }
        if (dvui.menuItemLabel(@src(), "Help", .{ .submenu = true }, .{})) |r| {
            var fw = dvui.floatingMenu(@src(), .{ .from = r }, .{});
            defer fw.deinit();
            if (dvui.menuItemLabel(@src(), "About", .{}, .{}) != null) {
                setStatus("ZiZZ wallet");
                m.close();
            }
        }
    }

    // Tab bar + node status
    {
        var tabs = dvui.box(@src(), .{ .dir = .horizontal }, .{ .expand = .horizontal, .margin = .{ .x = 8, .y = 4 } });
        defer tabs.deinit();
        if (dvui.button(@src(), "Overview", .{}, .{})) current_tab = .overview;
        if (dvui.button(@src(), "Send", .{}, .{})) current_tab = .send;
        if (dvui.button(@src(), "Receive", .{}, .{})) current_tab = .receive;
        if (dvui.button(@src(), "Transactions", .{}, .{})) current_tab = .transactions;
        if (dvui.button(@src(), "Address Book", .{}, .{})) current_tab = .addresses;

        var sp = dvui.box(@src(), .{ .dir = .horizontal }, .{ .expand = .horizontal });
        sp.deinit();

        // Node status indicator
        const status_label = if (node_connected) "Node: connected" else "Node: offline";
        const status_btn = dvui.button(@src(), status_label, .{}, .{});
        if (status_btn) {
            // toggle for demo
            node_connected = !node_connected;
        }
    }
    // Content
    var content = dvui.box(@src(), .{ .dir = .vertical }, .{ .expand = .both, .margin = .{ .x = 12, .y = 8 } });
    defer content.deinit();

    switch (current_tab) {
        .overview => try overviewTab(chain),
        .send => try sendTab(chain),
        .receive => try receiveTab(chain),
        .transactions => try transactionsTab(chain),
        .addresses => try addressesTab(chain),
    }

    // Console
    if (show_console) {
        dvui.label(@src(), "Console", .{}, .{ .margin = .{ .x = 12, .y = 4 } });
        var cscroll = dvui.scrollArea(@src(), .{}, .{ .expand = .horizontal, .min_size_content = .{ .h = 100 }, .margin = .{ .x = 12, .y = 0 } });
        defer cscroll.deinit();
        var i: usize = 0;
        while (i < log_count) : (i += 1) {
            dvui.labelNoFmt(@src(), log_lines[i][0..log_lens[i]], .{}, .{});
        }
    }

    // Status bar
    {
        var bar = dvui.box(@src(), .{ .dir = .horizontal }, .{ .expand = .horizontal, .margin = .{ .x = 8, .y = 4 }, .padding = .{ .x = 8, .y = 4 }, .background = true });
        defer bar.deinit();
        if (status_len > 0) {
            dvui.labelNoFmt(@src(), status_buf[0..status_len], .{}, .{});
        } else {
            var hb: [40]u8 = undefined;
            const hs = std.fmt.bufPrint(&hb, "Height {d}", .{chain.tipHeight()}) catch "Ready";
            dvui.labelNoFmt(@src(), hs, .{}, .{});
        }
    }
}

fn overviewTab(chain: *chainmod.Chain) !void {
    var total: i64 = 0;
    var naddr: usize = 0;
    {
        var it = chain.balances.iterator();
        while (it.next()) |e| {
            total += e.value_ptr.*;
            naddr += 1;
        }
    }
    var row = dvui.box(@src(), .{ .dir = .horizontal }, .{ .expand = .both });
    defer row.deinit();

    {
        var left = dvui.box(@src(), .{ .dir = .vertical }, .{ .expand = .vertical, .padding = .{ .x = 12, .y = 8 }, .background = true });
        defer left.deinit();
        dvui.label(@src(), "Wallet", .{}, .{ .font = .{ .size = 16 } });
        var ab: [48]u8 = undefined;
        dvui.labelNoFmt(@src(), fmtAmount(&ab, total), .{}, .{ .font = .{ .size = 22 } });
        var ub: [32]u8 = undefined;
        const us = std.fmt.bufPrint(&ub, "Addresses: {d}", .{naddr}) catch "";
        dvui.labelNoFmt(@src(), us, .{}, .{});
        var hb: [32]u8 = undefined;
        const hs = std.fmt.bufPrint(&hb, "Height: {d}", .{chain.tipHeight()}) catch "";
        dvui.labelNoFmt(@src(), hs, .{}, .{});
    }

    {
        var right = dvui.box(@src(), .{ .dir = .vertical }, .{ .expand = .both, .margin = .{ .x = 8, .y = 0 }, .padding = .{ .x = 8, .y = 8 } });
        defer right.deinit();
        dvui.label(@src(), "Recent", .{}, .{});
        var it = chain.balances.iterator();
        var shown: usize = 0;
        while (it.next()) |e| {
            if (shown >= 8) break;
            var lb: [120]u8 = undefined;
            var ab: [40]u8 = undefined;
            const line = std.fmt.bufPrint(&lb, "{s}  {s}", .{ e.key_ptr.*, fmtAmount(&ab, e.value_ptr.*) }) catch continue;
            dvui.labelNoFmt(@src(), line, .{}, .{});
            shown += 1;
        }
    }
}

fn sendTab(chain: *chainmod.Chain) !void {
    var form = dvui.box(@src(), .{ .dir = .vertical }, .{ .expand = .horizontal, .margin = .{ .x = 8, .y = 8 } });
    defer form.deinit();

    dvui.label(@src(), "Send", .{}, .{ .font = .{ .size = 16 } });

    dvui.label(@src(), "To address", .{}, .{ .margin = .{ .x = 0, .y = 8 } });
    var to_entry = dvui.textEntry(@src(), .{
        .text = .{ .internal = .{ .limit = 128 } },
        .placeholder = "zizz1...",
    }, .{ .expand = .horizontal });
    defer to_entry.deinit();

    dvui.label(@src(), "Amount", .{}, .{ .margin = .{ .x = 0, .y = 8 } });
    var amt_entry = dvui.textEntry(@src(), .{
        .text = .{ .internal = .{ .limit = 32 } },
        .placeholder = "0.0",
    }, .{ .min_size_content = .{ .w = 160 } });
    defer amt_entry.deinit();

    if (dvui.button(@src(), "Send", .{}, .{ .margin = .{ .x = 0, .y = 10 } })) {
        const to = to_entry.textGet();
        const amt_str = amt_entry.textGet();
        if (to.len == 0 or amt_str.len == 0) {
            setStatus("Enter address and amount");
            return;
        }
        const amt_f = std.fmt.parseFloat(f64, amt_str) catch {
            setStatus("Invalid amount");
            return;
        };
        const sats: i64 = @intFromFloat(amt_f * 100_000_000.0);
        // find a from address with enough
        var from: ?[]const u8 = null;
        var it = chain.balances.iterator();
        while (it.next()) |e| {
            if (e.value_ptr.* >= sats) {
                from = e.key_ptr.*;
                break;
            }
        }
        if (from) |f| {
            chain.sendToAddress(f, to, sats) catch |err| {
                setStatus(@errorName(err));
                return;
            };
            setStatus("Sent");
            
            
        } else {
            setStatus("No address has enough");
        }
    }
}

fn receiveTab(chain: *chainmod.Chain) !void {
    dvui.label(@src(), "Receive", .{}, .{ .font = .{ .size = 16 } });
    if (dvui.button(@src(), "New Receiving Address", .{}, .{})) {
        const addr = chain.getNewAddress() catch return;
        setStatus(addr);
    }
    dvui.label(@src(), "Your addresses", .{}, .{ .margin = .{ .x = 0, .y = 8 } });
    var scroll = dvui.scrollArea(@src(), .{}, .{ .expand = .both });
    defer scroll.deinit();
    var it = chain.balances.iterator();
    var idx: usize = 1;
    while (it.next()) |e| {
        var row = dvui.box(@src(), .{ .dir = .horizontal }, .{ .expand = .horizontal, .margin = .{ .x = 0, .y = 2 }, .padding = .{ .x = 8, .y = 6 }, .background = true });
        defer row.deinit();
        var nbuf: [16]u8 = undefined;
        const ns = std.fmt.bufPrint(&nbuf, "#{d}", .{idx}) catch "#";
        dvui.labelNoFmt(@src(), ns, .{}, .{ .min_size_content = .{ .w = 40 } });
        var abuf: [24]u8 = undefined;
        const short = if (e.key_ptr.*.len > 18) e.key_ptr.*[0..18] else e.key_ptr.*;
        const as = std.fmt.bufPrint(&abuf, "{s}...", .{short}) catch short;
        dvui.labelNoFmt(@src(), as, .{}, .{ .expand = .horizontal });
        var bbuf: [40]u8 = undefined;
        dvui.labelNoFmt(@src(), fmtAmount(&bbuf, e.value_ptr.*), .{}, .{});
        idx += 1;
    }
}

fn transactionsTab(chain: *chainmod.Chain) !void {
    dvui.label(@src(), "Transactions", .{}, .{ .font = .{ .size = 16 } });
    if (chain.blocks.items.len == 0) {
        dvui.label(@src(), "No transactions yet.", .{}, .{ .margin = .{ .x = 0, .y = 8 } });
        return;
    }
    var scroll = dvui.scrollArea(@src(), .{}, .{ .expand = .both });
    defer scroll.deinit();
    var i: usize = chain.blocks.items.len;
    while (i > 0) {
        i -= 1;
        const b = chain.blocks.items[i];
        var row = dvui.box(@src(), .{ .dir = .horizontal }, .{ .expand = .horizontal, .margin = .{ .x = 0, .y = 2 }, .padding = .{ .x = 8, .y = 6 }, .background = true });
        defer row.deinit();
        var hbuf: [16]u8 = undefined;
        const hs = std.fmt.bufPrint(&hbuf, "#{d}", .{b.height}) catch "#";
        dvui.labelNoFmt(@src(), hs, .{}, .{ .min_size_content = .{ .w = 50 } });
        var abuf: [24]u8 = undefined;
        const short = if (b.coinbase_address.len > 16) b.coinbase_address[0..16] else b.coinbase_address;
        const as = std.fmt.bufPrint(&abuf, "{s}...", .{short}) catch short;
        dvui.labelNoFmt(@src(), as, .{}, .{ .expand = .horizontal });
        var sbuf: [40]u8 = undefined;
        dvui.labelNoFmt(@src(), fmtAmount(&sbuf, b.subsidy), .{}, .{});
    }
}

fn addressesTab(chain: *chainmod.Chain) !void {
    dvui.label(@src(), "Address Book", .{}, .{ .font = .{ .size = 16 } });
    var scroll = dvui.scrollArea(@src(), .{}, .{ .expand = .both });
    defer scroll.deinit();
    var it = chain.balances.iterator();
    var idx: usize = 1;
    while (it.next()) |e| {
        var row = dvui.box(@src(), .{ .dir = .horizontal }, .{ .expand = .horizontal, .margin = .{ .x = 0, .y = 2 }, .padding = .{ .x = 8, .y = 6 }, .background = true });
        defer row.deinit();
        var nbuf: [16]u8 = undefined;
        const ns = std.fmt.bufPrint(&nbuf, "#{d}", .{idx}) catch "#";
        dvui.labelNoFmt(@src(), ns, .{}, .{ .min_size_content = .{ .w = 40 } });
        var abuf: [24]u8 = undefined;
        const short = if (e.key_ptr.*.len > 18) e.key_ptr.*[0..18] else e.key_ptr.*;
        const as = std.fmt.bufPrint(&abuf, "{s}...", .{short}) catch short;
        dvui.labelNoFmt(@src(), as, .{}, .{ .expand = .horizontal });
        var bbuf: [40]u8 = undefined;
        dvui.labelNoFmt(@src(), fmtAmount(&bbuf, e.value_ptr.*), .{}, .{});
        idx += 1;
    }
}
