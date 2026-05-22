# Appendix: Security and Authorization Details

This appendix expands the security posture and authorization expectations for the Soroban module system.

## Security Philosophy

The protocol minimizes trust and blast radius by:

- explicit authorization checks at every privileged boundary
- constrained module responsibilities
- reduced MVP action surface in Treasury
- governance-mediated upgrades instead of implicit admin mutation

## Authorization Boundaries

Authority design follows clear one-way boundaries:

- Manager authority publishes implementation updates under hardened controls
- Factory authority exists only during DAO initialization
- Governor validates proposals and controls execution intent
- Treasury is the privileged execution boundary for approved asset movement
- Token, Auction, and Metadata enforce owner/authorized-caller checks

Boundary safety requirements:

- no residual factory authority post-initialization
- no hidden admin bypass for treasury movement
- no circular authorization dependencies between Governor and Treasury

## Manager Security Controls

Manager is the highest-impact trust point and requires:

- multisig-controlled authority at account level
- timelock between publication and active use
- approved upgrade path validation and downgrade resistance
- emergency pause on deployment path

Operational expectations:

- signer diversity across independent organizations
- documented signer rotation process
- clear incident ownership for emergency pause and recovery

## Upgrade Safety Controls

Upgrade safety requires:

- explicit DAO opt-in through governance proposal
- validation that target implementation is Manager-approved
- staged testnet rehearsal for high-impact changes
- documented rollback or recovery process

Migration safety expectations:

- breaking storage changes use versioned migration policy
- migration paths are idempotent and replay-safe
- migration outcomes validated on production-like test data

## Authorization Verification Requirements

Test coverage must include:

- unauthorized access negative tests for all privileged methods
- handoff verification that factory loses authority after initialization
- validation of governor-to-treasury execution chain
- minter authorization enforcement checks
- manager control path checks for multisig and timelock behavior

Audit-oriented evidence should include:

- authorization matrix by contract/function
- expected caller and execution path per privileged operation
- failure mode inventory for incorrect or missing authorization
