# Base Mainnet DAO Upgrade Validation Report

## Scope

This report covers the 20 Base Mainnet DAOs in `test/forking/top-daos.json`.
The fork was pinned to block `51766395` and all runs used:

```sh
FORK_BLOCK_BASE=51766395 DAO_CHAINS=base-mainnet REGISTER_MISSING=true forge test --match-path test/forking/TestDAOsSystemUpgrade.t.sol -vv
```

`REGISTER_MISSING=true` registers missing Manager upgrade pairs only inside the
local fork. No live chain state is changed.

The test validates:

- The five proxy implementation slots.
- Treasury ownership of Token, MetadataRenderer, Auction, and Governor.
- Governor ownership of Treasury.
- Token supply, sampled token owners, and sampled token URI hashes.
- Auction, Treasury, Governor, and MetadataRenderer state.
- Proposal creation, proposal replacement, voting, queueing, execution, and a
  non-zero `proposalUpdatablePeriod` update.

Ten deterministic random token IDs are sampled. The test checks `ownerOf()` and
`tokenURI()` only for those candidates and never enumerates the full token set.

## Expected Implementations

| Component | Implementation |
| --- | --- |
| Token | `0xA97ab235Bc6234B871ffBE688cd478B743F6ac07` |
| MetadataRenderer | `0x63D1f81efb4c47eBFA77Dc9841932C360C39d6CE` |
| Auction | `0xe0f2982e725f90fA0394eEB8BEcC3C1aaa0CD6a1` |
| Treasury | `0x5eF26412F6b3EA35099F53BA9a032Ec15a4B77A4` |
| Governor | `0x04515024ad1F9bD097Db4983914A23A6dcB65751` |

Base Mainnet DAOs whose current MetadataRenderer implementation is
`0x83A9B0aaC8d38A7C8cCbbE8Ee8B103610BD8A790` are intentionally not upgraded
to the V3 MetadataRenderer. This is the deployed `MerklePropertyIPFS`
implementation exception. Metadata state is still checked for preservation.

## Missing Registrations

The independently isolated runs found these missing pairs for rank 7,
`Based Management One`:

| Component | Current | Expected |
| --- | --- | --- |
| Token | `0x127F22a79D123780F7E9FF38578d16a78799c131` | `0xA97ab235Bc6234B871ffBE688cd478B743F6ac07` |
| Auction | `0x639dC4bDcAA16dd626Eaa6A1480a852D5427252C` | `0xe0f2982e725f90fA0394eEB8BEcC3C1aaa0CD6a1` |
| Governor | `0x46E4eaE74254346867bBF53E7D30BAa6F6C8cD5a` | `0x04515024ad1F9bD097Db4983914A23A6dcB65751` |

The fork-only registration path successfully registered all three pairs, and
the rank 7 upgrade and governance flow passed.

## Per-DAO Results

| Rank | DAO | Result |
| ---: | --- | --- |
| 1 | Collective Nouns | Pass |
| 2 | Gnars | Pass |
| 3 | Purple | Pass |
| 4 | member | Pass |
| 5 | BASED DAO | Fail: proposal unsuccessful |
| 6 | Builder | Pass |
| 7 | Based Management One | Pass after 3 local registrations |
| 8 | OUNCE | Pass |
| 9 | Based Fellas | Pass |
| 10 | the park dao | Pass |
| 11 | City Nouns | Fail: token supply/auction transition mismatch |
| 12 | NounsDAO Africa | Pass |
| 13 | Lil Toadz DAO | Pass |
| 14 | MAD BANANA DAO on BASE | Pass |
| 15 | mferbuilderDAO | Pass |
| 16 | SkateHive | Pass |
| 17 | Based Associates | Pass |
| 18 | Coppa Nouns | Pass |
| 19 | Kendama DAO | Unverified: RPC storage timeout |
| 20 | Based Reaper | Pass |

## Failure Details

### Rank 11: City Nouns

The upgrade flow reached the following implementation pairs before failing:

| Component | Current | Expected |
| --- | --- | --- |
| Token | `0xE77e4FA003b2cC07ad10a9D1dB216Cae5Ed14d3f` | `0xA97ab235Bc6234B871ffBE688cd478B743F6ac07` |
| MetadataRenderer | `0xB4Ca85D61f7fcCe0d176Fdb743860daBF3FC03f9` | `0x63D1f81efb4c47eBFA77Dc9841932C360C39d6CE` |
| Auction | `0xf958872ceb73bA7d0acA0c7a9905119BCb371dEC` | `0xe0f2982e725f90fA0394eEB8BEcC3C1aaa0CD6a1` |
| Treasury | `0xaf75199b91AEDBe2B99476899782C5Bb507393E0` | `0x5eF26412F6b3EA35099F53BA9a032Ec15a4B77A4` |
| Governor | `0x9Af9f31BAE469c13528B458E007A7EA965BD14bB` | `0x04515024ad1F9bD097Db4983914A23A6dcB65751` |

Failure details:

- Expected token supply: `58`; actual token supply: `59`.
- Expected next auction token ID: `66`; actual token ID: `71`.
- The failure occurs during the settled-auction transition check.

### Rank 5: BASED DAO

The implementation pairs were the same as rank 2. Upgrade state checks passed,
but the added governance flow ended in state `Defeated` (`3`) instead of
`Succeeded` (`4`). The sampled holders did not provide enough voting power for
this DAO's quorum.

### Rank 19: Kendama DAO

The test did not reach an assertion. The provider timed out while reading a
storage slot from Base RPC. This is an infrastructure failure, not a DAO
upgrade result.

## Log Interpretation

The test logs implementation addresses, not proxy addresses. For example:

```text
Token: 0xE77e...
Token V3: 0xA97a...
```

This means the DAO currently uses implementation `0xE77e...` and the upgrade
target is `0xA97a...`. The DAO Token proxy address comes from the manifest and is
not printed by that log line.

## Test Correction

The original combined run produced a misleading `TOKEN_NOT_MINTED(491)` result
for a later DAO. The expected implementation helper was aliasing the shared
implementation struct in memory. Applying the MerklePropertyIPFS exception for
one DAO changed the expected metadata implementation for subsequent DAOs.

The helper now copies each implementation field explicitly. Rank 20 was rerun
after this correction and passed with the proper target
`0x63D1...d6CE`.

The earlier Gnars `OutOfGas` result had a separate cause: the scanner called
`tokenURI()` for all 6,006 minted Gnars tokens before selecting its samples.
Gnars has auction token ID `7085`, so the scan exhausted the fork gas limit.
Random sampling reduced the Gnars run from an out-of-gas failure to a passing
run in `7.78s`.
