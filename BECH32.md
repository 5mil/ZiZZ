# ZiZZ bech32 addresses

## Status
Native segwit addresses are **BIP-173 / BIP-350** compliant and copy-paste safe.

| Type | Encoding | Witness | Program | Example shape |
|------|----------|---------|---------|---------------|
| **P2WPKH** | Bech32 | v0 | 20-byte HASH160(compressed pubkey) | `zizz1q…` |
| **P2WSH** | Bech32 | v0 | 32-byte SHA256(script) | `zizz1q…` (longer) |
| **P2TR** | Bech32m | v1 | 32-byte x-only pubkey | `zizz1p…` |

HRP: **`zizz`** (separator `1`).

## Why this is copy-paste safe
- Charset excludes `1 b i o` (ambiguous) — BIP-173 alphabet only.
- 6-character checksum detects typos / truncation almost always.
- Mixed case rejected; decode is case-normalized.
- Wrong HRP / wrong encoding (bech32 vs bech32m) rejected.
- `sendtoaddress` refuses invalid destinations (`error.InvalidAddress`).

## Code
- `src/ripemd160.zig` — RIPEMD-160 + `hash160` = RIPEMD160(SHA256(.))
- `src/bech32.zig` — encode/decode, `encodeSegwit`, `isValidZizzAddress`
- `src/wallet.zig` — `addressFromPubkey` (P2WPKH), `addressP2trFromXOnly`, `isValidAddress`

## Not yet
- Full script VM / spending paths for P2WPKH and P2TR
- BIP32 derivation / descriptor wallets
- Electrum/Core interop beyond address string format

