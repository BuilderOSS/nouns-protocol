# DAO Upgrade Registration Report

## Scope

The configurable fork suite was run against all 20 DAOs on each supported network:

```bash
DAO_CHAINS=all DAO_COUNT=20 forge test \
  --match-path test/forking/TestDAOsSystemUpgrade.t.sol -vv
```

The scan reads each proxy's current ERC1967 implementation and checks the corresponding pair in that network's Manager:

```solidity
manager.isRegisteredUpgrade(currentImplementation, v3Implementation)
```

No upgrade transactions were executed because preflight found missing registrations.

## Summary

| Network | DAOs scanned | DAOs with missing registrations | Missing pairs |
| --- | ---: | ---: | ---: |
| Base | 20 | 6 | 10 |
| Ethereum | 20 | 20 | 64 |
| Optimism | 20 | 11 | 25 |
| **Total** | **60** | **37** | **99** |

Already-upgraded DAOs are treated as successful. The scan did not find any fully upgraded DAO among this selection.

## Base Mainnet

V3 targets from `addresses/8453.json`:

- Token: `0xA97ab235Bc6234B871ffBE688cd478B743F6ac07`
- MetadataRenderer: `0x63D1f81efb4c47eBFA77Dc9841932C360C39d6CE`
- Auction: `0xe0f2982e725f90fA0394eEB8BEcC3C1aaa0CD6a1`
- Treasury: `0x5eF26412F6b3EA35099F53BA9a032Ec15a4B77A4`
- Governor: `0x04515024ad1F9bD097Db4983914A23A6dcB65751`

Missing registrations:

- Metadata `0x83A9B0aaC8d38A7C8cCbbE8Ee8B103610BD8A790` -> `0x63D1f81efb4c47eBFA77Dc9841932C360C39d6CE`: Purple, Builder, the park dao, Lil Toadz DAO.
- Token `0x127F22a79D123780F7E9FF38578d16a78799C131` -> `0xA97ab235Bc6234B871ffBE688cd478B743F6ac07`: Based Management One, Based Reaper.
- Auction `0x639dC4bDcAA16dd626Eaa6A1480a852D5427252C` -> `0xe0f2982e725f90fA0394eEB8BEcC3C1aaa0CD6a1`: Based Management One, Based Reaper.
- Governor `0x46E4eaE74254346867bBF53E7D30BAa6F6C8cD5a` -> `0x04515024ad1F9bD097Db4983914A23A6dcB65751`: Based Management One, Based Reaper.

The following common Base pairs were registered during the scan:

- Token `0xE77e4FA003b2cC07ad10a9D1dB216Cae5Ed14d3f` -> V3 Token.
- Metadata `0xB4Ca85D61f7fcCe0d176Fdb743860daBF3FC03f9` -> V3 MetadataRenderer.
- Auction `0xf958872ceb73bA7d0acA0c7a9905119BCb371dEC` -> V3 Auction.
- Treasury `0xaf75199b91AEDBe2B99476899782C5Bb507393E0` -> V3 Treasury.
- Governor `0x9Af9f31BAE469c13528B458E007A7EA965BD14bB` -> V3 Governor.

## Ethereum Mainnet

Missing registrations:

- Token `0xAeD75D1e5c1821E2EC29D5d24b794b13C34c5d63` -> V3 Token, and Auction `0x785708d09b89C470aD7B5b3f8ac804cE72B6b282` -> V3 Auction, and Governor `0x46eA3fd17DEb7B291AeA60E67E5cB3a104FEa11D` -> V3 Governor: Builder, Purple, REXER, Paladins Dao, Entropy, the park dao, PoohCrew, Public Assembly, mferbuilderDAO, BLVKHVND, Art Haus, AW3 DAO, Lil Toadz DAO, Portion Club, Spores, The Panama DAO, CHECKED DAO.
- Token `0xe6322201ceD0a4D6595968411285A39ccf9d5989` -> V3 Token, Metadata `0x26f494Af990123154E7Cc067da7A311B07D54Ae1` -> V3 MetadataRenderer, Auction `0x2661fe1a882AbFD28AE0c2769a90F327850397c6` -> V3 Auction, Treasury `0x0B6D2473f54de3f1d80b27c92B22D13050Da289a` -> V3 Treasury, and Governor `0x9eefEF0891b1895af967fe48C5D7D96E984B96a3` -> V3 Governor: XNouns, Santa Fe DAO, FamilyDAO.

The common registered Ethereum pairs observed were the V3 MetadataRenderer pair from `0x5a28EEF0eD8cCe44CDa9d7097ecCE041bb51B9D4` and the V3 Treasury pair from `0x3bdAFE0D299168F6ebB6e1B4E1e9702A30F6364D`.

## Optimism Mainnet

Missing registrations:

- Token `0x127F22a79D123780F7E9FF38578d16a78799C131` -> V3 Token, Auction `0x639dC4bDcAA16dd626Eaa6A1480a852D5427252C` -> V3 Auction, and Governor `0x46E4eaE74254346867bBF53E7D30BAa6F6C8cD5a` -> V3 Governor: Builder HAUS, testdao, `#00FF00`, `$0.236978`, Fourth, Commitments2, CommitmentDAO.
- Metadata `0xdEe7aa9B8d084541Fe2c71c52217Fbc2b14d922D` -> V3 MetadataRenderer: SHOAL, Shoal, SHOAL rank 14, SHOAL rank 17.

All required pairs were registered for Creative Kidz, HOPON Club, Razzy DM ranks 7, 8, 10, and 12, Crecis, Contr, and We Them Media.

## Successful Base Upgrade Reference

Transaction:

`0x42a344946065b7665e260f396cddf745b3cc5508bcbe4e4f60de4117bd85e4e2`

The transaction upgraded a DAO using the common registered Base pairs:

- Governor `0x9Af9f31BAE469c13528B458E007A7EA965BD14bB` -> `0x04515024ad1F9bD097Db4983914A23A6dcB65751`
- Token `0xE77e4FA003b2cC07ad10a9D1dB216Cae5Ed14d3f` -> `0xA97ab235Bc6234B871ffBE688cd478B743F6ac07`
- Treasury `0xaf75199b91AEDBe2B99476899782C5Bb507393E0` -> `0x5eF26412F6b3EA35099F53BA9a032Ec15a4B77A4`
- Auction `0xf958872ceb73bA7d0acA0c7a9905119BCb371dEC` -> `0xe0f2982e725f90fA0394eEB8BEcC3C1aaa0CD6a1`
- Metadata `0xB4Ca85D61f7fcCe0d176Fdb743860daBF3FC03f9` -> `0x63D1f81efb4c47eBFA77Dc9841932C360C39d6CE`

The receipt and execution trace show all five Manager registration checks returning `true`, followed by pause, upgrades, unpause, and `updateProposalUpdatablePeriod(0)`.
