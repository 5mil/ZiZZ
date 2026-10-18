const std = @import("std");
const webui = @import("webui");
const chainmod = @import("chain.zig");
const wallet = @import("wallet.zig");
const wallet_crypto = @import("wallet_crypto.zig");

var g_chain: ?*chainmod.Chain = null;
var g_io: ?std.Io = null;
var g_allocator: ?std.mem.Allocator = null;
var info_buf: [4096]u8 = undefined;
var status_buf: [256]u8 = undefined;

/// When true, seed is present in memory for key derivation.
var unlocked: bool = true;

pub fn main(init: std.process.Init) !void {
    var chain = chainmod.Chain.init(init.gpa, init.io);
    defer chain.deinit();
    try chain.ensureGenesis();
    g_chain = &chain;
    g_io = init.io;
    g_allocator = init.gpa;
    unlocked = true;

    var win = webui.newWindow();
    _ = win.bind("getInfo", getInfo) catch 0;
    _ = win.bind("mineN", mineN) catch 0;
    _ = win.bind("newAddress", newAddress) catch 0;
    _ = win.bind("send", send) catch 0;
    _ = win.bind("listAddrs", listAddrs) catch 0;
    _ = win.bind("listTxs", listTxs) catch 0;
    _ = win.bind("encryptWallet", encryptWallet) catch 0;
    _ = win.bind("unlockWallet", unlockWallet) catch 0;
    _ = win.bind("lockWallet", lockWallet) catch 0;
    _ = win.bind("walletCryptoStatus", walletCryptoStatus) catch 0;

    const splash =
        \\n<!DOCTYPE html><html><head><title>ZiZZ</title>
        \\n<style>body{margin:0;background:#0a0a0f;display:flex;align-items:center;justify-content:center;height:100vh;color:#fff;font-family:system-ui}
        \\n.logo{font-size:64px;font-weight:300;letter-spacing:8px}</style></head>
        \\n<body><div class=logo>ZiZZ</div></body></html>
    ;
    win.show(splash) catch {};
    std.Io.sleep(init.io, .{ .nanoseconds = 800 * std.time.ns_per_ms }, .real) catch {};
    const html = @embedFile("wallet_web.html");
    win.show(html) catch {};
    webui.wait();
}

fn requireUnlocked() bool {
    return unlocked;
}

fn getInfo(e: *webui.Event) void {
    if (g_chain) |c| {
        const s = std.fmt.bufPrint(&info_buf, "{{\"height\":{d},\"balance\":{d},\"utxos\":{d},\"unlocked\":{},\"enc_file\":{}}}", .{
            c.tipHeight(),
            c.getTotalBalance(),
            c.utxos.items.len,
            unlocked,
            if (g_io) |io| wallet_crypto.fileExists(io) else false,
        }) catch return;
        returnZ(e, s);
    }
}

fn mineN(e: *webui.Event) void {
    if (!requireUnlocked()) return;
    if (g_chain) |c| {
        const n = e.getInt();
        const addr = c.getNewAddress() catch return;
        _ = c.generateToAddress(@intCast(n), addr) catch {};
    }
}

fn newAddress(e: *webui.Event) void {
    if (!requireUnlocked()) {
        returnZ(e, "error:wallet locked");
        return;
    }
    if (g_chain) |c| {
        const addr = c.getNewAddress() catch return;
        returnZ(e, addr);
    }
}

fn send(e: *webui.Event) void {
    if (!requireUnlocked()) return;
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

/// Encrypt current seed to zizz-wallet.enc (Argon2id + ChaCha20-Poly1305) and wipe RAM seed.
fn encryptWallet(e: *webui.Event) void {
    const passphrase = e.getString();
    const allocator = g_allocator orelse {
        returnZ(e, "error:no allocator");
        return;
    };
    const io = g_io orelse {
        returnZ(e, "error:no io");
        return;
    };
    const c = g_chain orelse {
        returnZ(e, "error:no chain");
        return;
    };
    if (passphrase.len < 8) {
        returnZ(e, "error:passphrase too short (min 8)");
        return;
    }
    // Ensure seed exists
    if (c.seed == null) {
        c.seed = wallet.HdSeed.generate(io) catch {
            returnZ(e, "error:seed generate failed");
            return;
        };
    }
    const seed = c.seed.?;
    wallet_crypto.encryptAndSave(allocator, seed, passphrase, io) catch {
        returnZ(e, "error:encrypt failed");
        return;
    };
    // Wipe in-memory seed after successful encrypt-at-rest
    if (c.seed) |*s| s.wipe();
    c.seed = null;
    unlocked = false;
    returnZ(e, "ok:encrypted");
}

/// Load zizz-wallet.enc and decrypt into chain.seed
fn unlockWallet(e: *webui.Event) void {
    const passphrase = e.getString();
    const allocator = g_allocator orelse {
        returnZ(e, "error:no allocator");
        return;
    };
    const io = g_io orelse {
        returnZ(e, "error:no io");
        return;
    };
    const c = g_chain orelse {
        returnZ(e, "error:no chain");
        return;
    };
    if (!wallet_crypto.fileExists(io)) {
        returnZ(e, "error:no wallet file");
        return;
    }
    const seed = wallet_crypto.loadAndDecrypt(allocator, passphrase, io) catch {
        returnZ(e, "error:auth failed");
        return;
    };
    c.seed = seed;
    unlocked = true;
    returnZ(e, "ok:unlocked");
}

/// Wipe seed from RAM (file remains).
fn lockWallet(e: *webui.Event) void {
    if (g_chain) |c| {
        if (c.seed) |*s| s.wipe();
        c.seed = null;
    }
    unlocked = false;
    returnZ(e, "ok:locked");
}

fn walletCryptoStatus(e: *webui.Event) void {
    const io = g_io;
    const has_file = if (io) |i| wallet_crypto.fileExists(i) else false;
    const s = std.fmt.bufPrint(&status_buf, "{{\"unlocked\":{},\"enc_file\":{},\"kdf\":\"argon2id\",\"aead\":\"chacha20poly1305\",\"file\":\"{s}\"}}", .{
        unlocked,
        has_file,
        wallet_crypto.file_name,
    }) catch return;
    returnZ(e, s);
}

fn returnZ(e: *webui.Event, s: []const u8) void {
    var zbuf: [4096:0]u8 = undefined;
    const n = @min(s.len, 4095);
    @memcpy(zbuf[0..n], s[0..n]);
    zbuf[n] = 0;
    e.returnString(zbuf[0..n:0]);
}
