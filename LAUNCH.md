# ZiZZ LAUNCH

Primary path: **regtest / local play**.

This chain is kept alive as a stable testing target for tpool and other projects.  
Pure Zig implementation of the Fizzlewick concept.

## 1. Build

```bash
git clone https://github.com/5mil/ZiZZ.git
cd ZiZZ
zig build
```

## 2. Start the regtest node

```bash
./zig-out/bin/zizz node --regtest
# RPC listens on 127.0.0.1:18448
# user: zizz
# password: wick-of-the-ancients
```

Optional flags:
- `--rpcport=18448` (default)

## 3. Wallet + mine (another terminal)

```bash
# Create a wallet (no-op in this build, but accepted)
curl -u zizz:wick-of-the-ancients -d '{"jsonrpc":"2.0","method":"createwallet","params":["wizard"],"id":1}' http://127.0.0.1:18448

# Get a new address
ADDR=$(curl -s -u zizz:wick-of-the-ancients -d '{"jsonrpc":"2.0","method":"getnewaddress","params":[],"id":1}' http://127.0.0.1:18448 | jq -r .result)
echo "Address: $ADDR"

# Mine 10 blocks
curl -u zizz:wick-of-the-ancients -d "{\"jsonrpc\":\"2.0\",\"method\":\"generatetoaddress\",\"params\":[10,\"$ADDR\"],\"id\":1}" http://127.0.0.1:18448

# Check balance
curl -u zizz:wick-of-the-ancients -d '{"jsonrpc":"2.0","method":"getbalance","params":[],"id":1}' http://127.0.0.1:18448

# Chain info
curl -u zizz:wick-of-the-ancients -d '{"jsonrpc":"2.0","method":"getblockchaininfo","params":[],"id":1}' http://127.0.0.1:18448
```

## 4. tpool EXTERNAL

```
http://zizz:wick-of-the-ancients@127.0.0.1:18448
```

`getblocktemplate` is implemented (minimal) so stock miners and tpool can pull templates.  
PoW is sha256d.

## Params

| Item              | Value                                      |
|-------------------|--------------------------------------------|
| Name              | ZiZZ                                       |
| Ticker            | ZiZZ                                       |
| Role              | Long-lived test chain                      |
| PoW               | sha256d                                    |
| P2P (regtest)     | 18447                                      |
| RPC (regtest)     | 18448                                      |
| Datadir           | zizz (in-memory in this launch build)      |
| Subsidy           | base 50 ±20 triangle (period 2100) + slow decay |
| Magic             | f1 7a 7a 22                                |
| bech32            | zizz                                       |

The ledger stays open for testing.  
Not a monetary product. Engineering target only.

The wick stays lit. The hash remains.
