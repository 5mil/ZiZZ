const std = @import("std");
const consensus = @import("consensus.zig");
const block = @import("block.zig");
const hashmod = @import("hash.zig");
const wallet = @import("wallet.zig");
const txmod = @import("tx.zig");

pub const Block = struct {
    header: block.BlockHeader,
    height: u32,
    subsidy: consensus.Amount,
    coinbase_address: []u8,
};

pub const Utxo = struct {
    id: u64,
    address: []const u8,
    amount: consensus.Amount,
    spent: bool = false,
};

pub const Chain = struct {
    allocator: std.mem.Allocator,
    blocks: std.array_list.Managed(Block),
    balances: std.StringHashMap(consensus.Amount),
    keys: std.StringHashMap(wallet.PrivateKey),
    txs: std.array_list.Managed(txmod.Tx),
    utxos: std.array_list.Managed(Utxo),
    next_utxo: u64 = 1,
    io: std.Io,
    next_address_id: u32 = 1,

    pub fn init(allocator: std.mem.Allocator, io: std.Io) Chain {
        return .{
            .allocator = allocator,
            .blocks = std.array_list.Managed(Block).init(allocator),
            .balances = std.StringHashMap(consensus.Amount).init(allocator),
            .keys = std.StringHashMap(wallet.PrivateKey).init(allocator),
            .txs = std.array_list.Managed(txmod.Tx).init(allocator),
            .utxos = std.array_list.Managed(Utxo).init(allocator),
            .io = io,
        };
    }

    pub fn deinit(self: *Chain) void {
        for (self.blocks.items) |b| {
            self.allocator.free(b.coinbase_address);
        }
        self.blocks.deinit();
        var it = self.balances.keyIterator();
        while (it.next()) |k| {
            self.allocator.free(k.*);
        }
        self.balances.deinit();
        self.keys.deinit();
    }

    pub fn ensureGenesis(self: *Chain) !void {
        std.debug.print("ensureGenesis: calling load\n", .{});
        try self.load();
        std.debug.print("after load blocks={d}\n", .{self.blocks.items.len});
        if (self.blocks.items.len > 0) return;
        const hdr = block.createGenesisHeader();
        const genesis_addr = try self.allocator.dupe(u8, "zizz1genesis");
        try self.blocks.append(.{
            .header = hdr,
            .height = 0,
            .subsidy = consensus.getBlockSubsidy(0),
            .coinbase_address = genesis_addr,
        });
        try self.credit(genesis_addr, consensus.getBlockSubsidy(0));
    }

    pub fn tipHeight(self: *const Chain) u32 {
        if (self.blocks.items.len == 0) return 0;
        return self.blocks.items[self.blocks.items.len - 1].height;
    }

    pub fn tipHash(self: *const Chain) [32]u8 {
        if (self.blocks.items.len == 0) return std.mem.zeroes([32]u8);
        return self.blocks.items[self.blocks.items.len - 1].header.getHash();
    }

    pub fn tipHashHex(self: *const Chain) [64]u8 {
        return hashmod.hashToHex(self.tipHash());
    }


    pub fn getNewAddress(self: *Chain) ![]const u8 {
        const priv = try wallet.PrivateKey.generate(self.io);
        const pubk = try priv.publicKey();
        const addr = try wallet.addressFromPubkey(self.allocator, pubk);
        try self.balances.put(addr, 0);
        try self.keys.put(addr, priv);
        return addr;
    }

    pub fn dumpPrivKey(self: *Chain, address: []const u8) ?[52]u8 {
        const priv = self.keys.get(address) orelse return null;
        return priv.toWif(true) catch null;
    }

    fn credit(self: *Chain, address: []const u8, amount: consensus.Amount) !void {
        const entry = self.balances.getEntry(address) orelse blk: {
            const owned = try self.allocator.dupe(u8, address);
            try self.balances.put(owned, 0);
            break :blk self.balances.getEntry(owned).?;
        };
        entry.value_ptr.* += amount;
        const addr_owned = try self.allocator.dupe(u8, address);
        try self.utxos.append(.{ .id = self.next_utxo, .address = addr_owned, .amount = amount });
        self.next_utxo += 1;
    }

    fn selectUtxos(self: *Chain, address: []const u8, need: consensus.Amount) ![]Utxo {
        var selected = std.array_list.Managed(Utxo).init(self.allocator);
        var total: consensus.Amount = 0;
        for (self.utxos.items) |*u| {
            if (u.spent) continue;
            if (!std.mem.eql(u8, u.address, address)) continue;
            try selected.append(u.*);
            total += u.amount;
            if (total >= need) break;
        }
        if (total < need) {
            selected.deinit();
            return error.InsufficientFunds;
        }
        return selected.toOwnedSlice();
    }

    pub fn getBalance(self: *const Chain, address: []const u8) consensus.Amount {
        return self.balances.get(address) orelse 0;
    }

    pub fn getTotalBalance(self: *const Chain) consensus.Amount {
        var total: consensus.Amount = 0;
        var it = self.balances.valueIterator();
        while (it.next()) |v| total += v.*;
        return total;
    }


    pub fn sendToAddress(self: *Chain, from: []const u8, to: []const u8, amount: consensus.Amount) !void {
        const bal = self.getBalance(from);
        if (bal < amount) return error.InsufficientFunds;
        const priv = self.keys.get(from) orelse return error.NoKey;
        const selected = try self.selectUtxos(from, amount);
        defer self.allocator.free(selected);
        var total: consensus.Amount = 0;
        for (selected) |u| total += u.amount;
        var t = txmod.Tx{ .from = from, .to = to, .amount = amount, .fee = 0 };
        try t.sign(priv);
        // mark spent
        for (selected) |u| {
            for (self.utxos.items) |*live| {
                if (live.id == u.id) live.spent = true;
            }
        }
        const from_entry = self.balances.getEntry(from) orelse return error.InsufficientFunds;
        from_entry.value_ptr.* -= amount;
        try self.credit(to, amount);
        // change
        const change = total - amount;
        if (change > 0) {
            try self.credit(from, change);
        }
        try self.txs.append(t);
        try self.save();
    }

    pub fn listTxs(self: *Chain, allocator: std.mem.Allocator) ![]const u8 {
        var list = std.array_list.Managed(u8).init(allocator);
        defer list.deinit();
        try list.appendSlice("[");
        var i: usize = self.txs.items.len;
        var n: usize = 0;
        while (i > 0 and n < 30) {
            i -= 1;
            const t = self.txs.items[i];
            if (n > 0) try list.appendSlice(",");
            const piece = try std.fmt.allocPrint(allocator, "{{\"from\":\"{s}\",\"to\":\"{s}\",\"amt\":{d}}}", .{ t.from, t.to, t.amount });
            defer allocator.free(piece);
            try list.appendSlice(piece);
            n += 1;
        }
        try list.appendSlice("]");
        return list.toOwnedSlice();
    }

    pub fn listBalances(self: *Chain, allocator: std.mem.Allocator) ![]const u8 {
        var list = std.array_list.Managed(u8).init(allocator);
        defer list.deinit();
        try list.appendSlice("{");
        var it = self.balances.iterator();
        var first = true;
        while (it.next()) |e| {
            if (!first) try list.appendSlice(",");
            first = false;
            const piece = try std.fmt.allocPrint(allocator, "\"{s}\":{d}", .{ e.key_ptr.*, e.value_ptr.* });
            defer allocator.free(piece);
            try list.appendSlice(piece);
        }
        try list.appendSlice("}");
        return list.toOwnedSlice();
    }

    pub fn generateToAddress(self: *Chain, n: u32, address: []const u8) ![][64]u8 {
        try self.ensureGenesis();
        const hashes = try self.allocator.alloc([64]u8, n);
        var i: u32 = 0;
        while (i < n) : (i += 1) {
            const height = self.tipHeight() + 1;
            const subsidy = consensus.getBlockSubsidy(height);
            var hdr = block.BlockHeader{
                .version = 1,
                .prev_block = self.tipHash(),
                .timestamp = @intCast(@divTrunc(std.Io.Clock.real.now(self.io).nanoseconds, std.time.ns_per_s)),
                .bits = 0x207fffff,
                .nonce = i,
            };
            const addr_owned = try self.allocator.dupe(u8, address);
            try self.blocks.append(.{
                .header = hdr,
                .height = height,
                .subsidy = subsidy,
                .coinbase_address = addr_owned,
            });
            try self.credit(address, subsidy);
            hashes[i] = hashmod.hashToHex(hdr.getHash());
        }
        try self.save();
        return hashes;
    }


    const LogFile = "zizz-blocks.log";
    const SnapFile = "zizz-snapshot.json";
    const TmpFile = "zizz-snapshot.tmp";

    pub fn save(self: *Chain) !void {
        // append-only log of blocks
        var logf = try std.Io.Dir.cwd().createFile(self.io, LogFile, .{ .truncate = true });
        defer logf.close(self.io);
        var lbuf: [8192]u8 = undefined;
        var lw = logf.writer(self.io, &lbuf);
        for (self.blocks.items) |b| {
            const hex = hashmod.hashToHex(b.header.getHash());
            try lw.interface.print("{d}|{d}|{s}|{s}\n", .{ b.height, b.subsidy, b.coinbase_address, &hex });
        }
        try lw.interface.flush();

        // atomic snapshot
        var tmp = try std.Io.Dir.cwd().createFile(self.io, TmpFile, .{ .truncate = true });
        var tbuf: [8192]u8 = undefined;
        var tw = tmp.writer(self.io, &tbuf);
        try tw.interface.writeAll("{\"blocks\":");
        var hbuf: [16]u8 = undefined;
        const hs = std.fmt.bufPrint(&hbuf, "{d}", .{self.tipHeight()}) catch "0";
        try tw.interface.writeAll(hs);
        try tw.interface.writeAll(",\"balances\":{");
        var bit = self.balances.iterator();
        var first = true;
        while (bit.next()) |e| {
            if (!first) try tw.interface.writeAll(",");
            first = false;
            try tw.interface.print("\"{s}\":{d}", .{ e.key_ptr.*, e.value_ptr.* });
        }
        try tw.interface.writeAll("}}\n");
        try tw.interface.flush();
        tmp.close(self.io);
        try std.Io.Dir.rename(std.Io.Dir.cwd(), TmpFile, std.Io.Dir.cwd(), SnapFile, self.io);
    }

    pub fn load(self: *Chain) !void {
        // prefer log replay
        var logf = std.Io.Dir.cwd().openFile(self.io, LogFile, .{}) catch {
            return self.loadSnapshot();
        };
        defer logf.close(self.io);
        var rbuf: [8192]u8 = undefined;
        var reader = logf.reader(self.io, &rbuf);
        const content = reader.interface.allocRemaining(self.allocator, .unlimited) catch return self.loadSnapshot();
        defer self.allocator.free(content);
        var lines = std.mem.splitScalar(u8, content, '\n');
        while (lines.next()) |line| {
            if (line.len == 0) continue;
            var parts = std.mem.splitScalar(u8, line, '|');
            const hstr = parts.next() orelse continue;
            const sstr = parts.next() orelse continue;
            const addr = parts.next() orelse continue;
            _ = parts.next(); // hash
            const height = std.fmt.parseInt(u32, hstr, 10) catch continue;
            const subsidy = std.fmt.parseInt(consensus.Amount, sstr, 10) catch continue;
            const hdr = block.BlockHeader{
                .version = 1,
                .prev_block = if (self.blocks.items.len == 0) std.mem.zeroes([32]u8) else self.tipHash(),
                .timestamp = 0,
                .bits = 0x207fffff,
                .nonce = height,
            };
            const addr_owned = try self.allocator.dupe(u8, addr);
            try self.blocks.append(.{
                .header = hdr,
                .height = height,
                .subsidy = subsidy,
                .coinbase_address = addr_owned,
            });
            try self.credit(addr, subsidy);
        }
        if (self.utxos.items.len == 0) {
            var it = self.balances.iterator();
            while (it.next()) |e| {
                if (e.value_ptr.* > 0) {
                    const addr_owned = try self.allocator.dupe(u8, e.key_ptr.*);
                    try self.utxos.append(.{ .id = self.next_utxo, .address = addr_owned, .amount = e.value_ptr.* });
                    self.next_utxo += 1;
                }
            }
        }
    }

    fn loadSnapshot(self: *Chain) !void {
        var file = std.Io.Dir.cwd().openFile(self.io, SnapFile, .{}) catch return;
        defer file.close(self.io);
        var buf: [4096]u8 = undefined;
        var reader = file.reader(self.io, &buf);
        const content = reader.interface.allocRemaining(self.allocator, .unlimited) catch return;
        defer self.allocator.free(content);
        // minimal: just count blocks from snapshot height
        if (std.mem.indexOf(u8, content, "\"blocks\":")) |i| {
            var end = i + 9;
            while (end < content.len and content[end] >= '0' and content[end] <= '9') end += 1;
            const h = std.fmt.parseInt(u32, content[i+9..end], 10) catch 0;
            var n: u32 = 0;
            while (n < h) : (n += 1) {
                const hdr = block.BlockHeader{ .nonce = n };
                const addr = try self.allocator.dupe(u8, "zizz1snap");
                try self.blocks.append(.{ .header = hdr, .height = n, .subsidy = consensus.getBlockSubsidy(n), .coinbase_address = addr });
            }
        }
    }

    pub fn resetAndRemine(self: *Chain, n: u32, address: []const u8) !void {
        for (self.blocks.items) |b| self.allocator.free(b.coinbase_address);
        self.blocks.clearRetainingCapacity();
        var it = self.balances.keyIterator();
        while (it.next()) |k| self.allocator.free(k.*);
        self.balances.clearRetainingCapacity();
        _ = std.Io.Dir.cwd().deleteFile(self.io, LogFile) catch {};
        _ = std.Io.Dir.cwd().deleteFile(self.io, SnapFile) catch {};
        try self.ensureGenesis();
        _ = try self.generateToAddress(n, address);
    }

};
