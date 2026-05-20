# Production Readiness Checklist - Safe Treasury V2 & Bridge Infrastructure

**Status**: 🔴 NOT READY FOR MAINNET
**Last Updated**: 2026-05-20
**Target Completion**: TBD (Estimated 8-14 weeks)

---

## 🔴 CRITICAL BLOCKERS (Must Fix Before Production)

### 1. Storage Layout Verification
- **Status**: ❌ NOT STARTED
- **Priority**: CRITICAL
- **Estimated Time**: 1 week
- **Assignee**: TBD
- **Issue**: `.storage-layout` file deleted, no upgrade safety verification
- **Risk**: Storage collision could brick existing DAOs on upgrade

**Tasks**:
- [ ] Re-generate storage layout with `forge inspect --pretty`
- [ ] Add forge script to verify storage layout on upgrades
- [ ] Add CI check to prevent storage breaks
- [ ] Document storage layout in upgrade runbook
- [ ] Test upgrade path from current mainnet Treasury version

**Files**:
- `.storage-layout` (regenerate)
- `script/VerifyStorageLayout.s.sol` (create)
- `.github/workflows/storage-check.yml` (create)

**Acceptance Criteria**:
- [ ] Storage layout file exists and is current
- [ ] CI fails if storage layout changes unexpectedly
- [ ] Upgrade simulation passes on fork

---

### 2. LayerZero Adapter Completion
- **Status**: ❌ NOT STARTED
- **Priority**: CRITICAL
- **Estimated Time**: 2 weeks
- **Assignee**: TBD
- **Issue**: Current implementation is incomplete scaffold, cannot deliver messages

**Tasks**:
- [ ] Implement proper `lzReceive` callback using OApp pattern
- [ ] Add fee estimation and validation
- [ ] Implement native gas forwarding for cross-chain delivery
- [ ] Add refund mechanism for excess fees
- [ ] Remove/document manual `relayMessage` function
- [ ] Add peer configuration for source/destination chains
- [ ] Implement message verification from LayerZero endpoint
- [ ] Add executor config validation
- [ ] Write comprehensive integration tests with LZ endpoint

**Files**:
- `src/bridge/adapters/layerzero/LayerZeroTransportAdapter.sol`
- `src/bridge/adapters/layerzero/ILayerZeroEndpointV2.sol` (expand interface)
- `test/bridge/LayerZeroTransportAdapter.t.sol` (create)

**Acceptance Criteria**:
- [ ] Messages auto-delivered via `lzReceive`, not manual relay
- [ ] Fee calculation works correctly
- [ ] Excess fees refunded to sender
- [ ] Integration tests pass with LZ testnet
- [ ] No manual owner intervention needed for delivery

---

### 3. Security Audit
- **Status**: ❌ NOT STARTED
- **Priority**: CRITICAL
- **Estimated Time**: 4-6 weeks (external dependency)
- **Assignee**: TBD (External firm)
- **Issue**: Complex bridge logic handling significant value requires professional audit

**Tasks**:
- [ ] Select audit firm (Trail of Bits, OpenZeppelin, Spearbit, etc.)
- [ ] Prepare audit scope document
- [ ] Freeze code for audit
- [ ] Conduct audit
- [ ] Remediate findings
- [ ] Publish audit report
- [ ] Community review period

**Audit Scope**:
- All bridge contracts (`src/bridge/**`)
- Treasury V2 additions (`src/governance/treasury/**`)
- Manager V2 additions (`src/manager/**`)
- Upgrade path safety
- Replay protection mechanisms
- Mode switching logic

**Acceptance Criteria**:
- [ ] Professional audit completed
- [ ] All critical/high findings resolved
- [ ] Audit report published
- [ ] No unresolved medium findings

---

### 4. Governance Safety Mechanisms
- **Status**: ❌ NOT STARTED
- **Priority**: CRITICAL
- **Estimated Time**: 1 week
- **Assignee**: TBD
- **Issue**: Expanded attack surface with no circuit breakers

**Tasks**:
- [ ] Implement per-Safe spending limits (daily/per-tx)
- [ ] Add per-Safe pause mechanism
- [ ] Add emergency pause for all Safe execution
- [ ] Implement rate limiting for cross-chain commands
- [ ] Add timelock for high-value Safe operations
- [ ] Document governance risk model changes
- [ ] Add view functions to check limits before proposal

**Files**:
- `src/governance/treasury/Treasury.sol` (add limits)
- `src/governance/treasury/TreasuryStorageV2.sol` (add limit storage)
- `src/bridge/DestinationExecutor.sol` (add rate limiting)
- `test/TreasuryV2Safety.t.sol` (create)

**Acceptance Criteria**:
- [ ] Cannot exceed spending limits
- [ ] Pause works independently per Safe
- [ ] Emergency pause stops all execution
- [ ] Limits configurable via governance
- [ ] Events emitted for limit changes

---

## 🟡 HIGH PRIORITY (Should Fix Before Launch)

### 5. Test Coverage Expansion
- **Status**: ❌ NOT STARTED
- **Priority**: HIGH
- **Estimated Time**: 2 weeks
- **Assignee**: TBD
- **Current Coverage**: ~40% (estimated)
- **Target Coverage**: 90%+

**Missing Tests**:
- [ ] Nonce edge cases (overflow, gaps, reordering)
- [ ] Mode switching attack vectors
- [ ] Multi-adapter attestation scenarios
- [ ] Safe module enablement verification
- [ ] LayerZero delivery failure handling
- [ ] Gas griefing attacks
- [ ] Deadline expiration edge cases
- [ ] Wallet registry manipulation during execution
- [ ] Replay attack scenarios
- [ ] Fuzzing for nonce handling
- [ ] Fuzzing for attestation counts
- [ ] Integration tests with real Safe contracts

**Files to Create/Expand**:
- `test/bridge/DestinationExecutorFuzz.t.sol` (create)
- `test/bridge/DestinationExecutor.t.sol` (expand)
- `test/bridge/SourceBridgeAdapter.t.sol` (expand)
- `test/TreasuryV2.t.sol` (expand)
- `test/bridge/ReplayAttack.t.sol` (create)
- `test/bridge/ModeSwitching.t.sol` (create)

**Acceptance Criteria**:
- [ ] Line coverage ≥90%
- [ ] Branch coverage ≥85%
- [ ] All critical paths tested
- [ ] Fuzzing catches no new issues
- [ ] Integration tests pass

---

### 6. Safe Module Verification
- **Status**: ❌ NOT STARTED
- **Priority**: HIGH
- **Estimated Time**: 1 week
- **Assignee**: TBD
- **Issue**: No on-chain verification that module is enabled

**Tasks**:
- [ ] Add `isModuleEnabled()` check in `registerSafe()`
- [ ] Add view function `isSafeReady(address safe)`
- [ ] Emit warning event if module not enabled
- [ ] Add Safe module enablement helper function
- [ ] Update tests to verify module checks
- [ ] Document module setup requirements

**Files**:
- `src/governance/treasury/Treasury.sol`
- `src/governance/treasury/interfaces/IGnosisSafe.sol` (add `isModuleEnabled`)
- `test/TreasuryV2.t.sol`

**Acceptance Criteria**:
- [ ] Cannot register Safe without enabled module
- [ ] Clear error message on failure
- [ ] Helper function works for verification
- [ ] Tests cover all edge cases

---

### 7. Deterministic Safe Deployment
- **Status**: ❌ NOT STARTED
- **Priority**: HIGH
- **Estimated Time**: 2 weeks
- **Assignee**: TBD
- **Issue**: Spec promises deterministic addresses, no implementation

**Tasks**:
- [ ] Integrate Safe ProxyFactory with CREATE2
- [ ] Implement `deploySafeDeterministic()` in Manager
- [ ] Calculate and return predicted addresses
- [ ] Add validation that addresses match across chains
- [ ] Add tests for address parity
- [ ] Document invariants required for matching addresses
- [ ] Create deployment helper script

**Files**:
- `src/manager/Manager.sol` (add Safe deployment)
- `src/manager/IManager.sol` (add interface)
- `script/DeploySafeDeterministic.s.sol` (create)
- `test/SafeDeterministicDeployment.t.sol` (create)

**Acceptance Criteria**:
- [ ] Same config = same address across chains
- [ ] Predicted address matches deployed address
- [ ] Works with Safe factory on all target chains
- [ ] Tests verify cross-chain parity

---

### 8. Governance Parameter Finalization
- **Status**: ❌ NOT STARTED
- **Priority**: HIGH
- **Estimated Time**: 1 week (discussion) + implementation
- **Assignee**: TBD (Community + core team)
- **Issue**: Critical parameters not finalized

**Open Decisions**:
- [ ] Mode change minimum delay (currently 1 day default)
- [ ] Mode change cooldown (currently 1 day default)
- [ ] Verification threshold defaults
- [ ] Safe module binding model (v1 vs v1.1)
- [ ] Default bridge mode (MANAGED vs SOVEREIGN)
- [ ] Guardian role expectations

**Tasks**:
- [ ] Create governance discussion forum post
- [ ] Compare with existing Treasury delay semantics
- [ ] Analyze attack scenarios for each parameter
- [ ] Community feedback period (1 week)
- [ ] Document final decisions
- [ ] Update defaults in deployment scripts
- [ ] Add parameter validation

**Files**:
- `docs/GOVERNANCE_PARAMETERS.md` (create)
- `script/DeployBridgeInfrastructure.s.sol` (update defaults)

**Acceptance Criteria**:
- [ ] Community consensus on parameters
- [ ] Parameters documented with rationale
- [ ] Defaults updated in code
- [ ] Validation prevents unsafe values

---

## 🟢 MEDIUM PRIORITY (Post-Launch OK, But Important)

### 9. Manager Bridge Registry Improvements
- **Status**: ❌ NOT STARTED
- **Priority**: MEDIUM
- **Estimated Time**: 1 week
- **Assignee**: TBD

**Tasks**:
- [ ] Add max registrations per DAO
- [ ] Add deprecation/archival mechanism
- [ ] Add adapter compatibility validation
- [ ] Add registry view functions
- [ ] Add events for all registry changes

**Files**:
- `src/manager/Manager.sol`
- `src/manager/ManagerStorageV2.sol`

**Acceptance Criteria**:
- [ ] Cannot exceed max registrations
- [ ] Deprecated adapters cannot be used
- [ ] Validation prevents incompatible adapters

---

### 10. Gas Optimization
- **Status**: ❌ NOT STARTED
- **Priority**: MEDIUM
- **Estimated Time**: 1 week
- **Assignee**: TBD

**Tasks**:
- [ ] Profile gas usage for common operations
- [ ] Cache storage reads in hot paths
- [ ] Optimize DestinationExecutor message processing
- [ ] Document gas costs for cross-chain ops
- [ ] Compare costs: local Treasury vs bridged Safe

**Files**:
- `docs/GAS_ANALYSIS.md` (create)
- Various contract optimizations

**Acceptance Criteria**:
- [ ] Gas report generated
- [ ] No low-hanging fruit remaining
- [ ] Costs documented for users

---

### 11. Documentation Completion
- **Status**: ❌ NOT STARTED
- **Priority**: MEDIUM
- **Estimated Time**: 1 week
- **Assignee**: TBD

**Missing Docs**:
- [ ] Migration guide for existing DAOs
- [ ] "When to use Safe vs Treasury" decision tree
- [ ] Gas cost estimates
- [ ] Incident response runbook
- [ ] Mainnet deployment checklist
- [ ] "Why LayerZero" decision doc
- [ ] Security model explanation
- [ ] Testnet deployment guide
- [ ] Bug bounty program details

**Files to Create**:
- `docs/MIGRATION_GUIDE.md`
- `docs/SAFE_VS_TREASURY.md`
- `docs/INCIDENT_RESPONSE.md`
- `docs/DEPLOYMENT_CHECKLIST.md`
- `docs/SECURITY_MODEL.md`
- `docs/TESTNET_GUIDE.md`

**Acceptance Criteria**:
- [ ] All docs exist and are comprehensive
- [ ] Community review completed
- [ ] Integrated into main docs site

---

### 12. Improved Events & Indexing
- **Status**: ❌ NOT STARTED
- **Priority**: MEDIUM
- **Estimated Time**: 3 days
- **Assignee**: TBD

**Tasks**:
- [ ] Add indexed parameters where helpful
- [ ] Ensure all state changes emit events
- [ ] Document event schema for indexers
- [ ] Create subgraph schema

**Files**:
- Various contracts (event improvements)
- `subgraph/schema.graphql` (create)

**Acceptance Criteria**:
- [ ] All critical events indexed properly
- [ ] Subgraph schema complete
- [ ] Frontend can easily query state

---

## 🔵 LOW PRIORITY (Nice to Have)

### 13. Code Quality Improvements
- **Status**: ❌ NOT STARTED
- **Priority**: LOW
- **Estimated Time**: 3 days
- **Assignee**: TBD

**Tasks**:
- [ ] Add missing NatSpec documentation
- [ ] Define all operation constants (DELEGATECALL, CREATE)
- [ ] Improve error messages with context
- [ ] Add code style consistency checks
- [ ] Run slither/mythril static analysis

**Acceptance Criteria**:
- [ ] All public functions have NatSpec
- [ ] No magic numbers
- [ ] Static analysis shows no new issues

---

## 📅 Proposed Timeline

### Phase 1: Critical Blockers (Weeks 1-4)
- **Week 1**: Storage layout verification (#1)
- **Week 2-3**: LayerZero adapter completion (#2)
- **Week 3**: Governance safety mechanisms (#4)
- **Week 4+**: Security audit begins (#3) - parallel track

### Phase 2: High Priority (Weeks 5-8)
- **Week 5-6**: Test coverage expansion (#5)
- **Week 6**: Safe module verification (#6)
- **Week 7-8**: Deterministic Safe deployment (#7)
- **Week 7**: Governance parameter finalization (#8)

### Phase 3: Medium Priority (Weeks 9-11)
- **Week 9**: Manager registry improvements (#9)
- **Week 10**: Documentation completion (#11)
- **Week 10**: Gas optimization (#10)
- **Week 11**: Events & indexing (#12)

### Phase 4: Audit & Testing (Weeks 12-14)
- **Week 12-14**: Audit remediation (#3)
- **Week 13-14**: Testnet deployment
- **Week 14+**: Community testing & feedback

**Total Estimated Time**: 14 weeks to mainnet-ready

---

## 🎯 Definition of Done

The feature is ready for mainnet when:

- [ ] All CRITICAL tasks completed
- [ ] All HIGH tasks completed
- [ ] Security audit passed with no unresolved findings
- [ ] Test coverage ≥90%
- [ ] Storage layout verified safe
- [ ] LayerZero integration fully functional
- [ ] Testnet deployment successful (3+ DAOs, 1+ month)
- [ ] Community testing period completed
- [ ] All documentation complete
- [ ] Bug bounty program live
- [ ] Governance parameters finalized
- [ ] Deployment scripts tested on testnet
- [ ] Rollback plan documented

---

## 📊 Progress Tracking

**Overall Completion**: 0/13 major tasks (0%)

### By Priority:
- 🔴 CRITICAL: 0/4 (0%)
- 🟡 HIGH: 0/4 (0%)
- 🟢 MEDIUM: 0/4 (0%)
- 🔵 LOW: 0/1 (0%)

**Last Status Update**: 2026-05-20
**Next Review Date**: TBD

---

## 🚨 Risk Register

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Storage collision on upgrade | Medium | Critical | Task #1 - storage verification |
| LayerZero delivery failure | Medium | High | Task #2 - proper implementation |
| Cross-chain governance attack | Low | Critical | Task #4 - circuit breakers |
| Audit finds critical issues | Medium | High | Task #3 - professional audit |
| Community rejects parameters | Low | Medium | Task #8 - early discussion |
| Testnet issues found late | Medium | Medium | Early testnet deployment |

---

## Notes

- This document should be updated after each task completion
- Commit messages should reference task numbers
- All PRs should update the relevant checkboxes
- Community should be informed of progress weekly
