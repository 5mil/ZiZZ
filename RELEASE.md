# ZiZZ Release Notes

## Status
Experimental. Not for real value. Crypto is unaudited — test coins only.

## Binaries
- `releases/zizz-web-windows-x86_64.exe` — Windows wallet (webview)
- `releases/zizz-wallet-windows-x86_64.exe` — Windows wallet (dvui, legacy)
- `releases/zizz-wallet-windows-aarch64.exe` — Windows ARM
- Build from source for Linux/macOS: `zig build -Doptimize=ReleaseSafe`

## What's in this release
- Local chain with append-only log and atomic snapshot
- Signed transactions and UTXO set
- Minimal P2P (handshake, getblocks)
- HD wallet, labels
- **Valid BIP-173/350 bech32 addresses** (P2WPKH `zizz1q…`, P2TR `zizz1p…`); copy-paste checksum
- **Wallet seed encryption: Argon2id KDF + ChaCha20-Poly1305 AEAD** (file `zizz-wallet.enc`)
- Difficulty adjustment and P2PKH verification
- Webview wallet with explorer tab, continuous mining, hashrate
- Local explorer on :8337 with search

## Wallet encryption
- **KDF:** Argon2id (default m=64 MiB, t=3, p=1; stored in blob)
- **AEAD:** ChaCha20-Poly1305 with random salt + nonce
- **AAD:** `zizz-seed-v1`
- **File:** `zizz-wallet.enc` (98-byte fixed layout, magic `ZiZZWLT1`)
- Encrypt & lock, Unlock, Lock from Preferences in the web wallet
- Wrong passphrase / tampered file → authentication failure (fail closed)
- XOR passphrase stub **removed**

See `src/wallet_crypto.zig` and `WALLET_ENCRYPTION.md`.

## Known limitations
- No full block sync between peers yet
- No installer; binaries only
- Single-file chain; no pruning
- Address *format* is BIP-173-shaped with HRP `zizz` (not Bitcoin HRP `bc`)
- Not compatible with Bitcoin
- Encryption protects seed at rest only (not RAM while unlocked; not a formal audit)

## Running
```
./zizz-web.exe
```
Explorer: http://127.0.0.1:8337
RPC: http://127.0.0.1:8339
