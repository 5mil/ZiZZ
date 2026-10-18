# ZiZZ Roadmap

Goal: A durable, production-quality Bitcoin-family full node implemented **entirely in Zig**, matching the Fizzlewick / FIZZ concept.

## Done (foundation)

- [x] Poetic subsidy function (integer triangle wave + decay)
- [x] Chain identity parameters (magic, ports, HRP, datadir)
- [x] sha256d double-SHA256
- [x] Basic 80-byte block header + genesis stub
- [x] CLI: subsidy, info, genesis, hash
- [x] Mainnet / regtest modes with correct ports and chain name
- [x] MAINNET.md launch docs
- [x] Pure Zig, zero external deps
- [x] MIT license, build system

## Next (core consensus & structures)

- [ ] Full transaction serialization / deserialization
- [ ] UTXO set (in-memory + persistent)
- [ ] Script interpreter (P2PKH, P2WPKH at minimum)
- [ ] Block validation (headers + full)
- [ ] Merkle root computation
- [ ] Difficulty adjustment (1-day timespan, 2-min blocks)
- [ ] Coinbase maturity = 20
- [ ] Proper genesis block (mined with wizard message)

## Networking

- [ ] P2P protocol (version, verack, inv, getdata, headers, block)
- [ ] Peer management
- [ ] Compact block / headers-first sync

## RPC & tooling

- [ ] JSON-RPC server (getblockchaininfo, getblock, generatetoaddress, etc.)
- [ ] Wallet (basic HD or simple key management)
- [ ] Config file parser
- [ ] Daemon mode

## Mining interface

- [ ] getblocktemplate / submitblock compatible with tpool
- [ ] sha256d stratum-friendly

## Quality

- [ ] Extensive unit tests against known Bitcoin vectors
- [ ] Fuzzing
- [ ] Documentation
- [ ] CI

The same durable-test stance as FIZZ: strong but basic, no monetary claims, kept alive for real integration work.

The wick stays lit.

## Wallet security

- [x] Argon2id + ChaCha20-Poly1305 seed encryption (`wallet_crypto.zig`)
- [x] Remove XOR passphrase stub
- [ ] BIP39 mnemonic backup
- [ ] RPC unlock gate for dumpprivkey
