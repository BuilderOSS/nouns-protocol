# Protocol Documentation

## Deployment & Operations

- [`deployment-workflows`](./deployment-workflows.md): Main deployment command reference from `package.json`, supported networks, env requirements, and manager owner sync usage.
- [`upgrade-runbook`](./upgrade-runbook.md): Chain-agnostic rollout guide for implementation deployment, manager update/registration pipeline, and DAO upgrade execution.
- [`manager-ownership-runbook`](./manager-ownership-runbook.md): Manager ownership transfer guide (governance or multisig), verification steps, and JSON manifest tracking fields.

## Governor & Proposals

- [`governor-architecture`](./governor-architecture.md): Governor feature design for signed proposals, updatable lifecycle, storage model, and EAS hybrid boundary.
- [`governor-proposal-lifecycle`](./governor-proposal-lifecycle.md): End-to-end proposal state machine and timing reference with query map, defaults, and update permissions.
- [`eas-proposal-candidates-schema`](./eas-proposal-candidates-schema.md): EAS attestation schemas for proposal candidates, comments, and sponsor signatures. Includes schema definitions, versioning system, and integration examples.

## Audit & Security

- [`v3-audit-readiness`](./v3-audit-readiness.md): Comprehensive V3 audit checklist covering Governor enhancements, CREATE2/CREATE3 deterministic deployments, security invariants, test coverage, breaking changes, and operational rollout procedures.
