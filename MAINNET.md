# ZiZZ MAINNET LAUNCH

**Mainnet is a public test platform.**

People may do with the coins as they will.  
Pure Zig implementation of the Fizzlewick concept.  
Strong, generally basic, intentionally un-fancy.

Not a monetary product. Engineering / play target only.

## 1. Build

```bash
git clone https://github.com/5mil/ZiZZ.git
cd ZiZZ
zig build
```

## 2. Start the mainnet node

```bash
./zig-out/bin/zizz node
# (no --regtest flag)
# RPC listens on 127.0.0.1:8339
# user: zizz
# password: wick-of-the-ancients
```

Optional:
- `--rpcport=8339`

## 3. Wallet + mine

```bash
curl -u zizz:wick-of-the-ancients -d '{"jsonrpc":"2.0","method":"createwallet","params":["wizard"],"id":1}' http://127.0.0.1:8339

ADDR=$(curl -s -u zizz:wick-of-the-ancients -d '{"jsonrpc":"2.0","method":"getnewaddress","params":[],"id":1}' http://127.0.0.1:8339 | jq -r .result)
echo "Address: $ADDR"

# Mine some blocks (easy difficulty genesis)
curl -u zizz:wick-of-the-ancients -d "{\"jsonrpc\":\"2.0\",\"method\":\"generatetoaddress\",\"params\":[25,\"$ADDR\"],\"id\":1}" http://127.0.0.1:8339

curl -u zizz:wick-of-the-ancients -d '{"jsonrpc":"2.0","method":"getbalance","params":[],"id":1}' http://127.0.0.1:8339
curl -u zizz:wick-of-the-ancients -d '{"jsonrpc":"2.0","method":"getblockchaininfo","params":[],"id":1}' http://127.0.0.1:8339
```

## 4. tpool EXTERNAL

```
http://zizz:wick-of-the-ancients@127.0.0.1:8339
```

PoW is sha256d. `getblocktemplate` is available.

## Network Parameters

| Parameter | Value |
|-----------|--------|
| Name | ZiZZ |
| Ticker | ZiZZ |
| Block time | **2 minutes** |
| Difficulty retarget | **1 day** |
| Coinbase maturity | **20 blocks** (~40 min) |
| Magic | `f1 7a 7a 22` |
| P2P / RPC | 8338 / 8339 |
| bech32 | `zizz` |
| Seeds | None (use addnode when P2P lands) |
| Subsidy | Poetic triangle ±20 + slow decay |
| Genesis | Easy difficulty (`0x207fffff`) for immediate launch |

## Design Stance

- Strong but basic Bitcoin-family consensus
- Public test / play / integration platform
- Pure Zig
- No value claims

The wick stays lit. The hash remains.
