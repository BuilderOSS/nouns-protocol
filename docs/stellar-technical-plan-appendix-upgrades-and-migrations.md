# Appendix: Upgrades and Storage Migration Policy

This appendix documents upgrade and migration policy for Soroban module evolution.

## Upgrade Governance Policy

Module upgrades follow a dual-control model:

- Manager publishes approved implementations and upgrade paths
- each DAO independently adopts upgrades through its own governance process

Policy outcomes:

- no forced upgrades across all DAOs
- communities retain local upgrade choice
- centralized publication with decentralized adoption

## Upgrade Lifecycle

Recommended lifecycle:

1. publish candidate implementation metadata and risk notes
2. enforce publication timelock before activation
3. DAO proposes local module upgrade
4. DAO votes and, if passed, executes upgrade path
5. verify post-upgrade state and operational health

## Migration Classification

Classify changes before release:

- non-breaking: additive or backward-compatible storage evolution
- breaking: structural storage changes requiring migration handling

Governance and release notes must state migration class clearly.

## Migration Safety Requirements

For breaking changes:

- define explicit migration strategy before publication
- ensure migration process is idempotent
- validate on production-like testnet data volume
- document expected runtime cost and execution constraints

If full migration in one pass is risky:

- use staged or lazy migration policy with bounded per-call work
- maintain correctness guarantees during mixed-state transition window

## Rollback and Recovery

Each high-impact release must include:

- rollback eligibility assessment
- recovery procedure if backward compatibility is limited
- operator checklist for detection, pause, and controlled recovery

Rollback is governance-mediated and never treated as automatic.

## Release Readiness Checklist

Before publishing upgrades:

- risk classification complete
- migration strategy reviewed
- testnet rehearsal complete
- operations team briefed on recovery steps
- community-facing upgrade notes published
