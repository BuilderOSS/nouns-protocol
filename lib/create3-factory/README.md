# CREATE3 Factory

Factory contract for easily deploying contracts to the same address on multiple chains, using CREATE3.

## Why?

Deploying a contract to multiple chains with the same address is annoying. One usually would create a new Ethereum account, seed it with enough tokens to pay for gas on every chain, and then deploy the contract naively. This relies on the fact that the new account's nonce is synced on all the chains, therefore resulting in the same contract address.
However, deployment is often a complex process that involves several transactions (e.g. for initialization), which means it's easy for nonces to fall out of sync and make it forever impossible to deploy the contract at the desired address.

One could use a `CREATE2` factory that deterministically deploys contracts to an address that's unrelated to the deployer's nonce, but the address is still related to the hash of the contract's creation code. This means if you wanted to use different constructor parameters on different chains, the deployed contracts will have different addresses.

A `CREATE3` factory offers the best solution: the address of the deployed contract is determined by only the deployer address and the salt. This makes it far easier to deploy contracts to multiple chains at the same addresses.

## Deployments

`CREATE3Factory` has been deployed to `0xD252d074EEe65b64433a5a6f30Ab67569362E7e0` on the following networks (see [`deployments/`](./deployments) for full deployment details):

- Ethereum Mainnet
- Ethereum Sepolia Testnet
- Base Mainnet
- Base Sepolia Testnet
- Optimism Mainnet
- Optimism Sepolia Testnet

Every network has the factory at the exact same address, because the address is a
deterministic function of the salt (`buildeross.create3factory.v1`) and the factory's bytecode,
not of who deploys it — see [Deploying to a new chain](#deploying-to-a-new-chain) below.

This is a fork of [zeframlou/create3-factory](https://github.com/zeframlou/create3-factory),
which deploys its own independent factory at `0x9fBB3DF7C40Da2e5A0dE984fFE2CCB7C47cd0ABf` on a
separate set of chains. The factories use different salts and have unrelated addresses.

## Usage

Call `CREATE3Factory::deploy()` to deploy a contract and `CREATE3Factory::getDeployed()` to predict the deployment address, it's as simple as it gets.

A few notes:

- The salt provided is hashed together with the deployer address (i.e. msg.sender) to form the final salt, such that each deployer has its own namespace of deployed addresses.
- The deployed contract should be aware that `msg.sender` in the constructor will be the temporary proxy contract used by `CREATE3` rather than the deployer, so common patterns like `Ownable` should be modified to accomodate for this.

## Installation

To install with [Foundry](https://github.com/foundry-rs/foundry):

```
forge install zeframlou/create3-factory
```

## Local development

This project uses [Foundry](https://github.com/foundry-rs/foundry) as the development framework.

### Dependencies

```bash
forge install
```

### Compilation

```bash
forge build
```

### Deploying to a new chain

Anyone can deploy `CREATE3Factory` to one of the supported chains and have it land at the same
canonical address on every chain — no shared or published private key is required, and you don't
need permission from the maintainers.

This works because the factory is deployed with a fixed salt (`buildeross.create3factory.v1`)
via Solidity's salted `new` (CREATE2), which Foundry routes through the
[canonical deterministic deployment proxy](https://github.com/Arachnid/deterministic-deployment-proxy)
(`0x4e59b44847b379578588920cA78FbF26c0B4956C`) — already live on most EVM chains. The
resulting address depends only on `(proxy address, salt, factory bytecode)`, **not** on who
sends the deployment transaction, so anyone deploying with their own wallet gets the exact
same address. `CREATE3Factory` itself has no owner or privileged functions (see
[`src/CREATE3Factory.sol`](./src/CREATE3Factory.sol)), so deploying it doesn't grant the
deployer any special control over it afterwards.

To deploy to one of the supported networks:

1. Ensure the network's RPC URL is configured in `foundry.toml` under `[rpc_endpoints]` and
   set the corresponding environment variable in `.env` (e.g., `MAINNET_RPC_URL`,
   `BASE_SEPOLIA_RPC_URL`, etc.).
2. Set `PRIVATE_KEY` in `.env` to your own wallet's key, funded with a small amount of the
   chain's native gas token. This key is only used to pay for your own deployment transaction
   — it is never shared or published.
3. Preview the address for free, with no gas spent and no key required:
   ```bash
   make predict network=<name>
   ```
   Verify the predicted address matches across all networks. If it doesn't, stop — see the
   caveat below before spending any gas.
4. Deploy for real:
   ```bash
   make deploy-with-key network=<name>
   ```
   Where `<name>` is one of: `mainnet`, `sepolia`, `base`, `base_sepolia`, `optimism`, or
   `optimism_sepolia`.

   This writes `deployments/<name>-<chainid>.json` with the deployment details. Re-running
   the same command on a chain that's already deployed is a no-op — it detects the existing
   contract and skips deployment instead of erroring. This target passes `--verify`, which
   submits source verification to the chain's block explorer using the matching key in `.env`;
   if you don't have one, drop `--verify` from the `deploy-with-key` recipe in the `Makefile`
   and verify later.

If the deterministic deployment proxy itself isn't yet live on your target chain (rare, only
on very new/obscure chains), `forge script --broadcast` deploys it automatically as part of
the same transaction sequence, at a small one-time extra cost (~0.007 ETH at the proxy's
fixed price of 100 gwei / 68,131 gas) — no extra steps needed on your part.

**Caveat:** the resulting address is only identical across chains if the contract is compiled
with the exact `solc` version, `evm_version`, and optimizer settings pinned in
`foundry.toml`. Building with different settings silently produces a different address.
Don't override the profile in `foundry.toml` when deploying.
