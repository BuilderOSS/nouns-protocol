# DAO Upgrade Final Multichain Report

## Scope and Method

The fork suite was run against the 20 configured DAOs on Base Mainnet,
Ethereum Mainnet, and Optimism Mainnet. Fork blocks:

| Network | Fork block |
| --- | ---: |
| Base Mainnet | `51766395` |
| Ethereum Mainnet | `26053043` |
| Optimism Mainnet | `157361680` |

All runs used `REGISTER_MISSING=true`. Manager registrations were made only on
the local fork.

The test checks implementation slots, ownership, metadata state, auction state,
sampled token owners and URIs, and the Governor proposal lifecycle. Token
checks use 10 deterministic random token IDs. The test does not enumerate every
token or call `tokenURI()` for every supply item.

`REGISTER_MISSING=true` registers missing Manager upgrade pairs only on the local
fork. No live chain state is changed. Already-upgraded DAOs are included in the
results when their implementation and state checks pass.

## Sources of Truth

- DAO addresses and ranks: `test/forking/top-daos.json`
- Upgrade and exception behavior: `test/forking/TestDAOsSystemUpgrade.t.sol`
- V3 implementation addresses: `addresses/1.json`, `addresses/10.json`, and
  `addresses/8453.json`

## Common V3 Targets

| Component | V3 implementation |
| --- | --- |
| Token | `0xA97ab235Bc6234B871ffBE688cd478B743F6ac07` |
| MetadataRenderer | `0x63D1f81efb4c47eBFA77Dc9841932C360C39d6CE` |
| Auction | `0xe0f2982e725f90fA0394eEB8BEcC3C1aaa0CD6a1` |
| Treasury | `0x5eF26412F6b3EA35099F53BA9a032Ec15a4B77A4` |
| Governor | `0x04515024ad1F9bD097Db4983914A23A6dcB65751` |

## Base Mainnet

### Missing Registrations

The Base scan found 10 missing pairs across 6 DAOs:

| Current implementation | Target | DAOs |
| --- | --- | --- |
| Metadata `0x83A9B0aaC8d38A7C8cCbbE8Ee8B103610BD8A790` | Metadata V3 | Purple, Builder, the park dao, Lil Toadz DAO |
| Token `0x127F22a79D123780F7E9FF38578d16a78799C131` | Token V3 | Based Management One, Based Reaper |
| Auction `0x639dC4bDcAA16dd626Eaa6A1480a852D5427252C` | Auction V3 | Based Management One, Based Reaper |
| Governor `0x46E4eaE74254346867bBF53E7D30BAa6F6C8cD5a` | Governor V3 | Based Management One, Based Reaper |

The common Base pairs were also locally registered where needed:

- Token `0xE77e4FA003b2cC07ad10a9D1dB216Cae5Ed14d3f` -> Token V3.
- Metadata `0xB4Ca85D61f7fcCe0d176Fdb743860daBF3FC03f9` -> Metadata V3.
- Auction `0xf958872ceb73bA7d0acA0c7a9905119BCb371dEC` -> Auction V3.
- Treasury `0xaf75199b91AEDBe2B99476899782C5Bb507393E0` -> Treasury V3.
- Governor `0x9Af9f31BAE469c13528B458E007A7EA965BD14bB` -> Governor V3.

### Exceptions

- DAOs currently using `0x83A9...a790` keep that Base Mainnet
  `MerklePropertyIPFS` implementation instead of upgrading MetadataRenderer.
- Based DAO's synthetic proposal is allowed to end `Defeated` when 10 sampled
  holders do not meet quorum. Upgrade and state checks still run.
- City Nouns can mint founder-vesting tokens and skip token IDs when starting
  an auction. The test checks that supply increases, the auction token ID
  advances, and the new token belongs to the auction.

### Result

All 20 Base Mainnet DAOs pass isolated upgrade and state checks.

## Ethereum Mainnet

### Missing Registrations

The scan found 66 missing pairs:

- Token `0xAeD75D1e5c1821E2EC29D5d24b794b13C34c5d63`, Auction
  `0x785708d09b89C470aD7B5b3f8ac804cE72B6b282`, and Governor
  `0x46eA3fd17DEb7B291AeA60E67E5cB3a104FEa11D` -> their V3 targets for
  Builder, Purple, REXER, Paladins Dao, Entropy, the park dao, PoohCrew,
  Public Assembly, mferbuilderDAO, BLVKHVND, Art Haus, AW3 DAO, Lil Toadz
  DAO, Portion Club, Spores, The Panama DAO, and CHECKED DAO.
- Token `0xe6322201ceD0a4D6595968411285A39ccf9d5989`, Metadata
  `0x26f494Af990123154E7Cc067da7A311B07D54Ae1`, Auction
  `0x2661fe1a882AbFD28AE0c2769a90F327850397c6`, Treasury
  `0x0B6D2473f54de3f1d80b27c92B22D13050Da289a`, and Governor
  `0x9eefEF0891b1895af967fe48C5D7D96E984B96a3` -> their V3 targets for
  XNouns, Santa Fe DAO, and FamilyDAO.

These pairs were registered only on the local forks.

### Results for Previously Unconfirmed DAOs

- Ranks 12, 14, 15, 16, 17, 18, and 20 pass.
- Art Haus, rank 13, passes. Its synthetic proposal cannot be created by the
  sampled proposer because of `BELOW_PROPOSAL_THRESHOLD`; the test treats that
  as an expected governance limitation after upgrade validation succeeds.
- The Panama DAO, rank 19, has the same expected proposal-threshold limitation
  and passes upgrade validation.
- mferbuilderDAO, rank 11, remains an ownership exception and is not silently
  bypassed.

mferbuilderDAO ownership at the pinned block:

- Token, MetadataRenderer, and Auction owner: `0x6D538...9CA8D714`.
- Treasury owner: the Governor proxy.
- Governor owner: `0x08BA2093CB72cAdbDA756E9b0eC93099E31B1855`.

The Governor is not owned by the Treasury proxy, so the required Treasury-only
upgrade call cannot be performed safely. This DAO needs an owner-authorized
upgrade path or an ownership migration before it can be marked passing.

## Optimism Mainnet

### Missing Registrations

The scan found 25 missing pairs:

- Token `0x127F22a79D123780F7E9FF38578d16a78799C131`, Auction
  `0x639dC4bDcAA16dd626Eaa6A1480a852D5427252C`, and Governor
  `0x46E4eaE74254346867bBF53E7D30BAa6F6C8cD5a` -> their V3 targets for
  Builder HAUS, testdao, `#00FF00`, `$0.236978`, Fourth, Commitments2, and
  CommitmentDAO.
- Metadata `0xdEe7aa9B8d084541Fe2c71c52217Fbc2b14d922D` -> Metadata V3 for
  SHOAL, Shoal, SHOAL rank 14, and SHOAL rank 17.

These pairs were registered only on the local forks.

### Results for Previously Unconfirmed DAOs

Ranks 7, 8, 10, 11, 12, 13, 14, and 17 are unlaunched zero-sale DAOs. Their
Token, MetadataRenderer, and Auction proxies are owned by deployment owners,
not the Treasury proxy:

- Razzy DM ranks 7, 8, 10, and 12: common deployment owner
  `0x116B52E794e1FC1DbceBBb2bc2C2ACffF6529b99`.
- SHOAL-family ranks 11, 13, 14, and 17: common deployment owner
  `0xEDc1a397589A0236C4810883b7d559288a5Fe7e1`.

The ownership assertion correctly stops these upgrades. They should not be
forced through with `vm.prank(dao.treasury)`: the deployed owner is the actual
upgrade authority for the unlaunched proxies. SHOAL ranks also require the
missing MetadataRenderer registration listed above.

Previously confirmed Optimism ranks 1–6, 9, 15, 16, and 18–20 continue to
pass.

## Final Status

- Base Mainnet: 20/20 pass.
- Ethereum Mainnet: 19 pass; mferbuilderDAO remains blocked by Governor
  ownership.
- Optimism Mainnet: 12 pass; 8 unlaunched DAOs remain blocked by deployment
  ownership rather than Treasury ownership.
