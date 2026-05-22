# Appendix: Storage and TTL Operations

This appendix captures deeper storage and operations guidance supporting the Stellar technical plan.

## Storage Model

Soroban storage classes are used with explicit intent:

- persistent storage for long-lived protocol state
- instance storage for compact contract configuration
- temporary storage for short-lived process and anti-abuse records

Target persistent records include:

- DAO registry mappings
- token ownership and balances
- governance proposals and vote records
- auction state and settlement history
- treasury transfer records
- voting checkpoints
- metadata seeds

Target instance records include:

- module authority configuration
- core runtime settings
- active implementation/version pointers where local to module

Temporary records are limited to:

- short-duration lock keys
- ephemeral anti-abuse markers

## TTL Maintenance Policy

Operational liveness depends on recurring TTL maintenance.

Primary strategy:

- auto-bump storage in normal write/read paths for active DAOs
- prefer low-friction maintenance in user-triggered contract flows

Secondary strategy:

- permissionless maintenance entry points for dormant DAOs
- batch refresh patterns for address/key groups

Fallback strategy:

- operator runbook for restore and maintenance recovery
- incident steps for archived state detection and response

## Checkpoint Growth Controls

Voting checkpoint growth is bounded by policy:

- checkpoint on governance-relevant balance changes
- apply age-based pruning
- apply per-address checkpoint caps
- provide permissionless prune maintenance function

Expected outcomes:

- predictable long-term storage growth
- stable historical voting functionality for governance windows
- manageable annual storage maintenance costs for active DAOs

## Operational Ownership

Before mainnet launch, define:

- who monitors TTL and storage health
- who funds maintenance operations
- alert thresholds for stale or near-expiry records
- incident response path for archive restore

Minimum operations checklist:

- storage health dashboard in place
- periodic maintenance cadence defined
- emergency restore drill completed on testnet
- treasury budget allocated for annual maintenance
