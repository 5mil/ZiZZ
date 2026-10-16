# ZiZZ

**Durable Bitcoin-family test chain — pure Zig.**

Straight reimplementation of the Fizzlewick concept.  
**Strong, generally basic, intentionally un-fancy.**

Mined by tpool on sha256d.  
Not a monetary product and not an investment.

*"Lo, another ledger of flickering wicks. Mine if you must, but mind the smoke."*

— some second-rate ancient wizard, probably

## What this is

| Item | Value |
|------|-------|
| **Name** | ZiZZ |
| **Ticker** | ZiZZ |
| **Role** | Public mainnet test / play / integration platform |
| **PoW** | sha256d |
| **Architecture** | Pure Zig. UTXO-style balances, headers, RPC shape preserved |
| **Datadir** | zizz |
| **Mainnet P2P/RPC** | 8338 / 8339 |
| **Regtest P2P/RPC** | 18447 / 18448 |
| **Magic** | `f1 7a 7a 22` |
| **bech32** | `zizz` |
| **Block time** | 2 minutes |
| **Coinbase maturity** | 20 blocks |

Subsidy is **not** pure halvings — see poetic schedule below.

## Design stance

- **Strong but basic.** Reliable Bitcoin-family consensus, clear RPC, ordinary sha256d.
- Pure Zig (std only). No C++ Bitcoin Core dependency.
- Public test platform. Live mainnet for testing, experimentation, and whatever people choose to do with the coins.
- No monetary claims.

## Poetic subsidy

Integer triangle wave ±20 on base 50, period 2100, plus slow integer decay (~5% every 100 000 blocks).  
Pure integer sats; no float consensus math.

| height | approx ZiZZ |
|--------|-------------|
| 0      | 30          |
| 1050   | 70          |
| 2100   | 30          |
| 100000 | ~58         |
| 210000 | ~25         |

## Build & Run

Requires Zig 0.17+.

```bash
git clone https://github.com/5mil/ZiZZ.git
cd ZiZZ
zig build

## GUI Wallet

```bash
zig build wallet          # Linux/macOS
./zig-out/bin/zizz-wallet
```

Windows binary: `releases/zizz-wallet-windows-x86_64.exe` (dvui + SDL3)
./zig-out/bin/zizz --help
```

### CLI Commands

```bash
./zig-out/bin/zizz subsidy 0      # ~30 ZiZZ
./zig-out/bin/zizz subsidy 1050   # ~70 ZiZZ
./zig-out/bin/zizz info
./zig-out/bin/zizz genesis
./zig-out/bin/zizz hash "hello"
```

## Launch

### Mainnet (public test platform)

See **[MAINNET.md](MAINNET.md)**.

```bash
./zig-out/bin/zizz node
```

```
http://zizz:wick-of-the-ancients@127.0.0.1:8339
```

### Regtest

See **[LAUNCH.md](LAUNCH.md)**.

```bash
./zig-out/bin/zizz node --regtest
```

## Status

Mainnet-ready (minimal node):

- Poetic subsidy
- In-memory chain + simple balances
- JSON-RPC: `getblockchaininfo`, `getblockcount`, `getbestblockhash`, `getnewaddress`, `getbalance`, `generatetoaddress`, `createwallet`, `getblocktemplate`
- Compatible with tpool EXTERNAL and curl / bitcoin-cli style clients
- 2-minute blocks, 20-block coinbase maturity, easy genesis

See [ROADMAP.md](ROADMAP.md) for next steps (real UTXO, P2P, persistence, full wallet).

The wick stays lit. The hash remains.

---

Companion to [FIZZ](https://github.com/fivemil/FIZZ) (C++ Bitcoin Core fork). This is the Zig reimplementation of the same concept.
