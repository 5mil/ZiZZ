# ZiZZ wallet encryption

## Design
Password-based encryption of the HD seed:

1. **Argon2id** derives a 32-byte key from the user passphrase + random salt.
2. **ChaCha20-Poly1305** encrypts the 32-byte seed (AEAD: confidentiality + integrity).

This replaces the former XOR-with-passphrase stub, which was not encryption.

## File format (`zizz-wallet.enc`)
| Offset | Size | Field |
|--------|------|-------|
| 0 | 8 | magic `ZiZZWLT1` |
| 8 | 1 | version `1` |
| 9 | 1 | kdf `1` = argon2id |
| 10 | 4 | m_kib (LE) |
| 14 | 4 | t (LE) |
| 18 | 4 | p (LE) |
| 22 | 16 | salt |
| 38 | 12 | nonce |
| 50 | 32 | ciphertext |
| 82 | 16 | Poly1305 tag |

Total **98 bytes**. AAD string: `zizz-seed-v1`.

## Default KDF params
- m = 65536 KiB (64 MiB)
- t = 3
- p = 1

Params are stored in the file so future re-encrypt can raise costs.

## API (`src/wallet_crypto.zig`)
- `encryptSeed` / `decryptSeed`
- `encryptAndSave` / `loadAndDecrypt` (uses `zizz-wallet.enc`)
- `fileExists`
- Unit tests: round-trip + wrong password + tamper → `AuthenticationFailed`

## Web wallet
Preferences tab:
- **Encrypt & lock** — write `zizz-wallet.enc`, wipe seed from RAM
- **Unlock** — decrypt into memory
- **Lock** — wipe RAM seed (file remains)

## Threat model (honest)
| Threat | Mitigated? |
|--------|------------|
| Disk steal + strong passphrase | Yes (offline KDF cost + AEAD) |
| Tampered wallet file | Yes (auth tag) |
| Wrong password | Fail closed |
| RAM scrape while unlocked | No |
| RPC dumpprivkey while unlocked | No (separate control) |

Not a substitute for RPC auth, consensus PoW, or a third-party audit.
