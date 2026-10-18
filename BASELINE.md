# ZiZZ Baseline (Phase 0)

## Persistence
- Block log: `zizz-blocks.log` (append-only, source of truth)
- Snapshot: `zizz-snapshot.json` (cache, atomic write via temp+rename)
- On startup: replay log to rebuild balances; fall back to snapshot if no log

## RPC (port 8339)
- getblockchaininfo, getblockcount, getbestblockhash
- getnewaddress, getbalance, listbalances
- generatetoaddress, sendtoaddress, dumpprivkey
- createwallet

## CLI
- `zizz node` — start node
- `zizz reset [addr] [n]` — reset chain and remine n blocks (default 20)
- `zizz info`, `zizz subsidy <h>`, `zizz genesis`, `zizz hash`

## Webview wallet
- Tabs: Overview, Send, Receive, Transactions, Mining, Addresses, Explorer
- Local explorer on :8337

## GUI (dvui, legacy)
- Same tabs plus Console and Nodes panel in Settings
