# Appendix: Resource Budget and Capacity Guidance

This appendix captures resource budgeting guidance for Soroban-constrained protocol operations.

## Capacity Principles

Design for predictable execution by:

- keeping MVP action surfaces narrow
- avoiding unbounded loops in governance-critical paths
- preferring paginated processing where batch growth is possible
- validating expensive flows under stress scenarios before mainnet

## High-Impact Execution Paths

Priority paths for load testing:

- auction settlement with reward splits and founder mint side effects
- governance proposal execution with multi-action batches
- frequent token transfer periods affecting checkpoint writes
- maintenance operations for checkpoint pruning and TTL refresh

## Budgeting Guardrails

Define and enforce guardrails such as:

- proposal complexity warning thresholds in UI
- maximum recommended action count per proposal batch
- checkpoint retention caps and prune cadence
- founder allocation bounds aligned with settlement headroom

## Failure Avoidance Strategies

To reduce runtime failure risk:

- reject or warn on oversized proposal payloads
- break large execution sets into sequential proposals
- schedule maintenance batches with conservative key counts
- monitor resource usage trends after each release

## Verification Plan

Before mainnet:

- run stress tests for worst-case expected settlement and governance paths
- confirm operation success within target instruction and I/O safety margins
- measure contract sizes and ensure expansion headroom remains
- capture reproducible benchmark reports for engineering and security review

## Operational Ownership

Define who is responsible for:

- updating budget assumptions as usage changes
- tuning app-side limits and warnings
- maintaining performance regression tests
- publishing periodic capacity status for protocol operators
