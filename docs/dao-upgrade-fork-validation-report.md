# DAO Upgrade Fork Validation Report

## Test Configuration

The tests ran with fork-only registration enabled. Missing Manager pairs were registered inside the local fork and were not written to any live chain.

The state checks covered:

- All five proxy implementation slots.
- Token supply, allowing one expected mint when unpausing a settled auction.
- Existing token owners.
- Existing token URI hashes.
- Auction settings and expected next-auction behavior.
- Governor settings and `proposalUpdatablePeriod == 0`.
- Treasury settings.
- Metadata renderer settings.

Pinned fork blocks:

- Base: `51766395`
- Ethereum: `26053043`
- Optimism: `157361680`

## Missing Registrations

The original all-DAO preflight found 99 missing pairs:

- Base: 10 pairs.
- Ethereum: 64 pairs.
- Optimism: 25 pairs.

The missing pair list is documented in `docs/dao-upgrade-registration-report.md`. Fork tests register these pairs locally before attempting upgrades.

## Verified Smooth Upgrades

### Base Mainnet

- Rank 4: `member`
- Rank 7: `Based Management One`

### Ethereum Mainnet

- Rank 1: `Builder`
- Rank 2: `Purple`
- Rank 3: `REXER`
- Rank 4: `Paladins Dao`
- Rank 5: `Entropy`
- Rank 6: `the park dao`
- Rank 7: `XNouns`
- Rank 8: `PoohCrew`
- Rank 9: `Santa Fe DAO`
- Rank 10: `Public Assembly`

### Optimism Mainnet

- Rank 1: `Builder HAUS`
- Rank 2: `Creative Kidz`
- Rank 3: `testdao`
- Rank 4: `HOPON Club`
- Rank 5: `#00FF00`
- Rank 6: `$0.236978`
- Rank 9: `Crecis`
- Rank 15: `Fourth`
- Rank 16: `Contr`
- Rank 18: `Commitments2`
- Rank 19: `CommitmentDAO`
- Rank 20: `We Them Media`

## Upgrade Failures

- Base rank 1, `Collective Nouns`: fork execution reverted after registration and upgrade attempts. Needs an isolated verbose rerun after RPC throttling clears.
- Base rank 2, `Gnars`: fork execution reverted after registration and upgrade attempts. Needs an isolated verbose rerun after RPC throttling clears.
- Base rank 3, `Purple`: custom metadata state was empty after the MetadataRenderer upgrade. The checks observed project URI, description, contract image, renderer base, and property count changing to empty/zero. The token owner/URI path also encountered `TOKEN_NOT_MINTED(0)` while scanning IDs.
- Optimism rank 7, `Razzy DM`: `AUCTION_CREATE_FAILED_TO_LAUNCH()` during the required unpause transition.
- Optimism ranks 8, 10, 11, 12, 13, 14, and 17: failed in the parallel matrix run and need isolated reruns for exact failure classification.

## Unverified

The following selections were not completed because parallel RPC traffic hit provider storage throttling (`HTTP 429`):

- Base ranks 5, 6, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, and 20.
- Ethereum ranks 11 through 20.

These are not classified as passes or failures yet.

## Interpretation

Registration is sufficient for most DAOs, but not sufficient for every DAO. The first confirmed incompatibilities are DAO-specific state/launch behavior:

- Purple has a custom MetadataRenderer state shape that is not preserved by the current V3 upgrade path.
- Some DAOs cannot create the next auction when the test unpauses a settled or unlaunched auction.
- Existing token URI and ownership checks pass for the smooth cases listed above.
