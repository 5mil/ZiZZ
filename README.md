# ZiZZ

A durable Bitcoin-family test chain implemented **entirely in Zig**.

Same concept as [Fizzlewick (FIZZ)](https://github.com/fivemil/FIZZ): a long-lived test / play / integration chain kept alive for ongoing work on [tpool](https://github.com/5mil/tpool) and other projects.

**Strong, generally basic, intentionally un-fancy.** Straight Bitcoin Core spirit in pure Zig: UTXO model, headers-first, clear RPC shape, ordinary sha256d PoW.

Mined by tpool on sha256d / port 3333. Not a monetary product and not an investment.

*"Lo, another ledger of flickering wicks. Mine if you must, but mind the smoke."*  
— some second-rate ancient wizard, probably

## What this is

| Item | Value |
|------|--------|
| **Name** | ZiZZ |
| **Ticker** | ZiZZ |
| **Role** | Long-lived test / play / integration chain |
| **PoW** | sha256d |
| **Language** | Pure Zig |
| **Architecture** | Bitcoin-family consensus (UTXO, headers, RPC) |
| **Datadir** | `zizz` |
| **Ports (regtest)** | P2P 18447, RPC 18448 |

Subsidy is **not** pure halvings — see poetic schedule below.

## Design stance

- **Strong but basic.** Reliable Bitcoin-family consensus, clear RPC, ordinary sha256d.
- **Perpetual for testing.** Live tests beat spinning up ephemeral regtest every time.
- **Transparent ledger.** Same spirit as tpool.
- **No value claims.** Engineering target, not speculation.
- **Zero external dependencies.** Pure Zig standard library.

## Poetic subsidy

Implemented in `src/consensus.zig` as `getBlockSubsidy`.

- Base 50 ZiZZ
- Triangle-wave ±20 ZiZZ, period 2100 blocks
- Slow integer decay (~5% every 100 000 blocks)
- Pure integer sats; no float consensus math

| height | approx ZiZZ |
|--------|-------------|
| 0 | 30 |
| 1050 | 70 |
| 2100 | 30 |
| 100000 | ~58 |
| 210000 | ~25 |

## Build & Run

Requires Zig 0.13+ (tested with recent master/0.14).

```bash
git clone https://github.com/5mil/ZiZZ.git
cd ZiZZ
zig build
./zig-out/bin/zizz --help
```

### Example

```bash
./zig-out/bin/zizz subsidy 0
./zig-out/bin/zizz subsidy 1050
./zig-out/bin/zizz info
```

## Launch (future)

Primary path: **regtest / local play**.  
This chain is kept alive as a stable testing target for tpool and other projects.

```
# Planned conf (~/.zizz/zizz.conf)
regtest=1
server=1
rpcuser=zizz
rpcpassword=wick-of-the-ancients
rpcport=18448
port=18447
daemon=1
txindex=1
fallbackfee=0.0001
```

## Status

Early foundation. Core consensus parameters, poetic subsidy, and CLI scaffolding are in place. Full P2P, validation, wallet, and RPC are under active construction in pure Zig.

The wick stays lit. The hash remains.

---

Companion to [FIZZ](https://github.com/fivemil/FIZZ) (C++ Bitcoin Core fork). This is the Zig reimplementation of the same concept.
