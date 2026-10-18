const std = @import("std");
const webui = @import("webui");
const chainmod = @import("chain.zig");

var g_chain: ?*chainmod.Chain = null;
var info_buf: [4096]u8 = undefined;

pub fn main(init: std.process.Init) !void {
    var chain = chainmod.Chain.init(init.gpa, init.io);
    defer chain.deinit();
    try chain.ensureGenesis();
    g_chain = &chain;

    var win = webui.newWindow();
    _ = win.bind("getInfo", getInfo) catch 0;
    _ = win.bind("mineN", mineN) catch 0;
    _ = win.bind("newAddress", newAddress) catch 0;
    _ = win.bind("send", send) catch 0;
    _ = win.bind("listAddrs", listAddrs) catch 0;
    _ = win.bind("listTxs", listTxs) catch 0;

    const splash =
        \\n<!DOCTYPE html><html><head><title>ZiZZ</title>
        \\n<style>body{margin:0;background:#0a0a0f;display:flex;align-items:center;justify-content:center;height:100vh;color:#fff;font-family:system-ui}
        \\n.logo{font-size:64px;font-weight:300;letter-spacing:8px}</style></head>
        \\n<body><div class=logo>ZiZZ</div></body></html>
    ;
    win.show(splash) catch {};
    // brief splash then main
    std.Io.sleep(init.io, .{ .nanoseconds = 800 * std.time.ns_per_ms }, .real) catch {};
    const html = @embedFile("wallet_web.html");
    win.show(html) catch {};
    webui.wait();
}

fn getInfo(e: *webui.Event) void {
    if (g_chain) |c| {
        const s = std.fmt.bufPrint(&info_buf, "{{\"height\":{d},\"balance\":{d},\"utxos\":{d}}}", .{ c.tipHeight(), c.getTotalBalance(), c.utxos.items.len }) catch return;
        returnZ(e, s);
    }
}

fn mineN(e: *webui.Event) void {
    if (g_chain) |c| {
        const n = e.getInt();
        const addr = c.getNewAddress() catch return;
        _ = c.generateToAddress(@intCast(n), addr) catch {};
    }
}

fn newAddress(e: *webui.Event) void {
    if (g_chain) |c| {
        const addr = c.getNewAddress() catch return;
        returnZ(e, addr);
    }
}

fn send(e: *webui.Event) void {
    if (g_chain) |c| {
        const to = e.getString();
        const amt = e.getIntAt(1);
        var it = c.balances.iterator();
        while (it.next()) |ent| {
            if (ent.value_ptr.* >= amt) {
                c.sendToAddress(ent.key_ptr.*, to, amt) catch {};
                return;
            }
        }
    }
}

fn listAddrs(e: *webui.Event) void {
    if (g_chain) |c| {
        var buf: [2048]u8 = undefined;
        var len: usize = 0;
        buf[len] = '[';
        len += 1;
        var it = c.balances.iterator();
        var first = true;
        while (it.next()) |ent| {
            if (!first) {
                buf[len] = ',';
                len += 1;
            }
            first = false;
            const s = std.fmt.bufPrint(buf[len..], "{{\"a\":\"{s}\",\"b\":{d}}}", .{ ent.key_ptr.*, ent.value_ptr.* }) catch break;
            len += s.len;
        }
        buf[len] = ']';
        len += 1;
        returnZ(e, buf[0..len]);
    }
}

fn listTxs(e: *webui.Event) void {
    if (g_chain) |c| {
        var buf: [4096]u8 = undefined;
        var len: usize = 0;
        buf[len] = '[';
        len += 1;
        var i: usize = c.txs.items.len;
        var count: usize = 0;
        while (i > 0 and count < 30) {
            i -= 1;
            const t = c.txs.items[i];
            if (count > 0) {
                buf[len] = ',';
                len += 1;
            }
            const s = std.fmt.bufPrint(buf[len..], "{{\"from\":\"{s}\",\"to\":\"{s}\",\"amt\":{d}}}", .{ t.from, t.to, t.amount }) catch break;
            len += s.len;
            count += 1;
        }
        buf[len] = ']';
        len += 1;
        returnZ(e, buf[0..len]);
    }
}

fn returnZ(e: *webui.Event, s: []const u8) void {
    var zbuf: [4096:0]u8 = undefined;
    const n = @min(s.len, 4095);
    @memcpy(zbuf[0..n], s[0..n]);
    zbuf[n] = 0;
    e.returnString(zbuf[0..n:0]);
}
