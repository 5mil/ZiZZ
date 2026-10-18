const std = @import("std");
const chainmod = @import("chain.zig");

pub fn start(chain: *chainmod.Chain, io: std.Io, allocator: std.mem.Allocator) void {
    const thread = std.Thread.spawn(.{}, run, .{ chain, io, allocator }) catch return;
    thread.detach();
}

fn run(chain: *chainmod.Chain, io: std.Io, allocator: std.mem.Allocator) void {
    const addr = std.Io.net.IpAddress.parseIp4("127.0.0.1", 8337) catch return;
    var server = addr.listen(io, .{ .reuse_address = true }) catch return;
    defer server.deinit();

    while (true) {
        var stream = server.accept(io) catch continue;
        defer stream.close(io);
        handle(io, &stream, chain, allocator) catch {};
    }
}

fn handle(io: std.Io, stream: *std.Io.net.Stream, chain: *chainmod.Chain, allocator: std.mem.Allocator) !void {
    var rbuf: [1024]u8 = undefined;
    var reader = stream.reader(io, &rbuf);
    const n = reader.interface.readSliceShort(&rbuf) catch return;
    const req = rbuf[0..n];

    const is_json = std.mem.indexOf(u8, req, "GET /api") != null;

    var body = std.array_list.Managed(u8).init(allocator);
    defer body.deinit();

    if (is_json) {
        try body.appendSlice("{\"height\":");
        var hbuf: [16]u8 = undefined;
        const hs = std.fmt.bufPrint(&hbuf, "{d}", .{chain.tipHeight()}) catch "0";
        try body.appendSlice(hs);
        try body.appendSlice(",\"blocks\":[");
        var i: usize = 0;
        while (i < chain.blocks.items.len and i < 50) : (i += 1) {
            if (i > 0) try body.appendSlice(",");
            const b = chain.blocks.items[chain.blocks.items.len - 1 - i];
            try body.appendSlice("{\"h\":");
            const h = std.fmt.bufPrint(&hbuf, "{d}", .{b.height}) catch "0";
            try body.appendSlice(h);
            try body.appendSlice(",\"a\":\"");
            try body.appendSlice(b.coinbase_address);
            try body.appendSlice("\"}");
        }
        try body.appendSlice("]}");
    } else {
        try body.appendSlice("<!DOCTYPE html><html><head><title>ZiZZ Explorer</title>");
        try body.appendSlice("<style>body{font-family:system-ui;background:#0a0a0f;color:#e8e8f0;padding:20px}input{padding:8px;background:#16161f;color:#fff;border:1px solid #2a2a3e;border-radius:6px}table{width:100%;border-collapse:collapse}td,th{padding:8px;border-bottom:1px solid #222}");
        try body.appendSlice("table{width:100%;border-collapse:collapse}td,th{padding:8px;border-bottom:1px solid #333}");
        try body.appendSlice("</style></head><body>");
        try body.appendSlice("<h1>ZiZZ Explorer</h1>");
        try body.appendSlice("<input id=q placeholder=\"height, address, or txid\" oninput=\"filter()\">");
        try body.appendSlice("<p>Height: <span id=h></span></p>");
        try body.appendSlice("<h1>ZiZZ Explorer</h1>");
        try body.appendSlice("<p>Height: <span id=h></span></p>");
        try body.appendSlice("<table><thead><tr><th>Height</th><th>Address</th></tr></thead><tbody id=t></tbody></table>");
        try body.appendSlice("<script>");
        try body.appendSlice("async function load(){const r=await fetch('/api');const d=await r.json();");
        try body.appendSlice("document.getElementById('h').textContent=d.height;");
        try body.appendSlice("document.getElementById('t').innerHTML=d.blocks.map(b=>`<tr><td>${b.h}</td><td>${b.a}</td></tr>`).join('');}");
        try body.appendSlice("load();setInterval(load,2000);");
        try body.appendSlice("</script></body></html>");
    }

    var resp: [256]u8 = undefined;
    const ctype = if (is_json) "application/json" else "text/html";
    const header = std.fmt.bufPrint(&resp, "HTTP/1.1 200 OK\r\nContent-Type: {s}\r\nContent-Length: {d}\r\nConnection: close\r\n\r\n", .{ ctype, body.items.len }) catch return;
    var w = stream.writer(io, &resp);
    w.interface.writeAll(header) catch return;
    w.interface.writeAll(body.items) catch return;
}
