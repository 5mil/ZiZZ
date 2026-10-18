# ZiZZ Release Notes

## Status
Experimental. Not for real value. Crypto is unaudited.

## Binaries
- `releases/zizz-web-windows-x86_64.exe` — Windows wallet (webview)
- `releases/zizz-wallet-windows-x86_64.exe` — Windows wallet (dvui, legacy)
- `releases/zizz-wallet-windows-aarch64.exe` — Windows ARM
- Build from source for Linux/macOS: `zig build -Doptimize=ReleaseSafe`

## What's in this release
- Local chain with append-only log and atomic snapshot
- Signed transactions and UTXO set
- Minimal P2P (handshake, getblocks)
- HD wallet, labels, passphrase encryption stub
- Difficulty adjustment and P2PKH verification
- Webview wallet with explorer tab, continuous mining, hashrate
- Local explorer on :8337 with search

## Known limitations
- No full block sync between peers yet
- Encryption is XOR, not a proper KDF
- No installer; binaries only
- Single-file chain; no pruning
- Not compatible with Bitcoin

## Running
```
./zizz-web.exe
```
Explorer: http://127.0.0.1:8337
RPC: http://127.0.0.1:8339
