const std = @import("std");
const webui = @import("webui");
const chainmod = @import("chain.zig");

var g_chain: ?*chainmod.Chain = null;
var info_buf: [128]u8 = undefined;

pub fn main(init: std.process.Init) !void {
    var chain = chainmod.Chain.init(init.gpa, init.io);
    defer chain.deinit();
    try chain.ensureGenesis();
    g_chain = &chain;

    var win = webui.newWindow();
    _ = win.bind("getInfo", getInfo) catch 0;
    _ = win.bind("mine", mine) catch 0;
    _ = win.bind("newAddress", newAddress) catch 0;

    const html =
        \\<!DOCTYPE html><html><head><title>ZiZZ</title>
        \\<style>body{font-family:sans-serif;background:#111;color:#eee;padding:20px}
        \\button{margin:6px;padding:8px 16px;background:#333;color:#fff;border:0;border-radius:4px;cursor:pointer}
        \\</style></head><body>
        \\<h1>ZiZZ Wallet</h1>
        \\<p>Height: <span id=h>0</span></p>
        \\<p>Balance: <span id=b>0</span></p>
        \\<button onclick="mineN()">Mine 1</button>
        \\<button onclick="newAddr()">New Address</button>
        \\<p><a href="http://127.0.0.1:8337" target=_blank>Open Explorer</a></p>
        \\<script>
        \\async function refresh(){try{const r=await getInfo();const d=JSON.parse(r);document.getElementById('h').textContent=d.height;document.getElementById('b').textContent=d.balance;}catch(e){}}
        \\async function mineN(){await mine();refresh();}
        \\async function newAddr(){const a=await newAddress();alert(a);refresh();}
        \\setInterval(refresh,2000);refresh();
        \\</script></body></html>
    ;
    win.show(html) catch {};
    webui.wait();
}

fn getInfo(e: *webui.Event) void {
    if (g_chain) |c| {
        const s = std.fmt.bufPrint(&info_buf, "{{\"height\":{d},\"balance\":{d}}}", .{ c.tipHeight(), c.getTotalBalance() }) catch "{\"height\":0,\"balance\":0}";
        var zbuf: [128:0]u8 = undefined;
        @memcpy(zbuf[0..s.len], s);
        zbuf[s.len] = 0;
        e.returnString(zbuf[0..s.len:0]);
    } else {
        e.returnString("{\"height\":0,\"balance\":0}");
    }
}

fn mine(_: *webui.Event) void {
    if (g_chain) |c| {
        const addr = c.getNewAddress() catch return;
        _ = c.generateToAddress(1, addr) catch {};
    }
}

fn newAddress(e: *webui.Event) void {
    if (g_chain) |c| {
        const addr = c.getNewAddress() catch {
            e.returnString("error");
            return;
        };
        var abuf: [128:0]u8 = undefined;
        const n = @min(addr.len, 127);
        @memcpy(abuf[0..n], addr[0..n]);
        abuf[n] = 0;
        e.returnString(abuf[0..n:0]);
    } else {
        e.returnString("error");
    }
}
