const std = @import("std");
const consensus = @import("consensus.zig");
const wallet = @import("wallet.zig");
const crypto = std.crypto;
const ecdsa = crypto.sign.ecdsa;

pub const Tx = struct {
    from: []const u8,
    to: []const u8,
    amount: consensus.Amount,
    fee: consensus.Amount = 0,
    sig: [64]u8 = std.mem.zeroes([64]u8),

    pub fn hash(self: Tx) [32]u8 {
        var buf: [256]u8 = undefined;
        const s = std.fmt.bufPrint(&buf, "{s}|{s}|{d}|{d}", .{ self.from, self.to, self.amount, self.fee }) catch "";
        var hasher = crypto.hash.sha2.Sha256.init(.{});
        hasher.update(s);
        var out: [32]u8 = undefined;
        hasher.final(&out);
        return out;
    }

    pub fn sign(self: *Tx, priv: wallet.PrivateKey) !void {
        const h = self.hash();
        const sk = try ecdsa.EcdsaSecp256k1Sha256.SecretKey.fromBytes(priv.bytes);
        const kp = try ecdsa.EcdsaSecp256k1Sha256.KeyPair.fromSecretKey(sk);
        const sig = try kp.sign(&h, null);
        @memcpy(&self.sig, &sig.toBytes());
    }

    pub fn verify(self: Tx, pubkey: [33]u8) bool {
        const h = self.hash();
        const pk = ecdsa.EcdsaSecp256k1Sha256.PublicKey.fromSec1(&pubkey) catch return false;
        const sig = ecdsa.EcdsaSecp256k1Sha256.Signature.fromBytes(self.sig);
        pk.verify(&h, sig) catch return false;
        return true;
    }
};
