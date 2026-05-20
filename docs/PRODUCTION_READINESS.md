# Production Readiness Tracking

**Feature:** Governor Updatable Proposals + Signed Proposals
**Branch:** `feat/updatable-proposals`
**Target Version:** `2.1.0`
**Last Updated:** 2026-05-20

---

## Status Overview

**Overall Readiness:** 75% → Target: 95%+

- ✅ **Code Quality:** 8/10 (solid foundation)
- ⚠️ **Production Readiness:** 6/10 (needs work)
- ⚠️ **Community Readiness:** 5/10 (education needed)

---

## Critical Path Items (Blocking)

### 🔴 P0: Must Fix Before Audit

- [ ] **Double-voting scenario test** - Verify hasVoted mapping behavior across proposal updates
- [ ] **Gas benchmarks** - Profile proposeBySigs with 1, 16, 32 signers + update flows
- [ ] **Fuzz tests** - Add signer ordering, update flows, state transitions
- [ ] **Invariant tests** - Votes never exceed supply, proposal state consistency
- [ ] **Code quality fixes** - Gas optimizations, event consistency, magic numbers
- [ ] **ProposalState.Replaced enum** - Distinguish updated proposals from canceled

### 🟡 P1: Must Fix Before Mainnet

- [ ] **Breaking change migration guide** - Frontend code examples for castVoteBySig migration
- [ ] **Subgraph schema updates** - Schema + example queries for revision tracking
- [ ] **ERC-1271 integration tests** - Test smart contract wallet signers
- [ ] **Emergency pause mechanism** - Circuit breaker for critical bugs
- [ ] **Rollback plan documentation** - Emergency DAO downgrade process
- [ ] **Community RFC** - Default updatable period justification + feedback

### 🟢 P2: Should Have Before Mainnet

- [ ] **DAO operator best practices** - When to use propose vs proposeBySigs
- [ ] **Proposal update rate limiting** - Prevent spam updates
- [ ] **Coverage reporting** - CI integration + coverage % target
- [ ] **Audit completion** - Security audit report + findings addressed
- [ ] **Bug bounty launch** - Immunefi program setup

---

## Detailed Issue Tracking

### 1. Design Concerns

#### 1.1 Vote Preservation Across Updates ⚠️ CRITICAL
**Status:** 🔴 Not Started
**Priority:** P0
**Assignee:** TBD

**Issue:**
```solidity
// Current behavior unclear:
// 1. User votes on proposal 0xABC during Updatable period
// 2. Proposer updates -> new ID 0xDEF
// 3. hasVoted[0xABC][user] = true
// 4. hasVoted[0xDEF][user] = ??? (likely false)
// 5. Can user vote again on 0xDEF?
```

**Tasks:**
- [ ] Write test: `testRevert_CannotVoteTwiceAcrossUpdate`
- [ ] Write test: `test_VotesPreservedAcrossUpdate`
- [ ] Document intended behavior in architecture doc
- [ ] Consider: Should hasVoted mapping be copied?
- [ ] Consider: Should votes reset on major updates?

**Notes:**
- If double-voting is possible, this is a CRITICAL vulnerability
- If intended, needs clear documentation and justification

---

#### 1.2 Proposal ID Mutability UX Confusion
**Status:** 🔴 Not Started
**Priority:** P0
**Assignee:** TBD

**Issue:**
- Updated proposals marked as `canceled = true`
- Appears in "canceled proposals" list (confusing)
- Block explorers show misleading state

**Tasks:**
- [ ] Add `ProposalState.Replaced` enum value
- [ ] Update `state()` function to check `proposalIdReplacedBy[id] != 0`
- [ ] Add `isReplaced(proposalId)` view function
- [ ] Update events to distinguish replacement from cancellation
- [ ] Document UX implications in lifecycle doc

**Code Change:**
```solidity
enum ProposalState {
    Pending, Active, Canceled, Defeated, Succeeded,
    Queued, Expired, Executed, Vetoed, Updatable, Replaced
}
```

---

#### 1.3 MAX_PROPOSAL_SIGNERS Gas Analysis
**Status:** 🔴 Not Started
**Priority:** P0
**Assignee:** TBD

**Issue:**
- No gas benchmarks for 32 signers
- `getVotes()` called in loop (external call)
- Risk of block gas limit DoS

**Tasks:**
- [ ] Add `test_GasProposeBySigs_1Signer`
- [ ] Add `test_GasProposeBySigs_16Signers`
- [ ] Add `test_GasProposeBySigs_32Signers`
- [ ] Add `test_GasCancelSignedProposal_32Signers`
- [ ] Document gas costs in architecture doc
- [ ] Consider: Should max be reduced to 16?

**Acceptance Criteria:**
- Gas cost with 32 signers < 10M gas
- Document worst-case scenario

---

### 2. Code Quality Issues

#### 2.1 Gas Optimization - Signer Array Copy
**Status:** 🔴 Not Started
**Priority:** P0
**Assignee:** TBD

**File:** `src/governance/governor/Governor.sol:895`

**Current:**
```solidity
for (uint256 i = 0; i < _oldSigners.length; ++i) {
    proposalSigners[newProposalId].push(_oldSigners[i]);
}
```

**Optimized:**
```solidity
address[] storage newSigners = proposalSigners[newProposalId];
uint256 len = _oldSigners.length;
for (uint256 i; i < len; ++i) {
    newSigners.push(_oldSigners[i]);
}
```

**Tasks:**
- [ ] Apply optimization
- [ ] Add gas comparison test

---

#### 2.2 Gas Optimization - Cache signers.length
**Status:** 🔴 Not Started
**Priority:** P0
**Assignee:** TBD

**File:** `src/governance/governor/Governor.sol:469`

**Current:**
```solidity
for (uint256 i = 0; i < signers.length; ++i) {
```

**Optimized:**
```solidity
uint256 signersLen = signers.length;
for (uint256 i; i < signersLen; ++i) {
```

**Tasks:**
- [ ] Apply optimization in all signer loops
- [ ] Add gas comparison test

---

#### 2.3 Event Consistency - ProposalUpdated
**Status:** 🔴 Not Started
**Priority:** P1
**Assignee:** TBD

**Issue:**
- `ProposalCreated` includes full `Proposal` struct
- `ProposalUpdated` does NOT include struct
- Indexers need extra RPC call

**Tasks:**
- [ ] Add proposal struct to `ProposalUpdated` event
- [ ] Update event documentation
- [ ] Consider: Breaking change for event schema?

---

#### 2.4 Magic Number - DEFAULT_PROPOSAL_UPDATABLE_PERIOD
**Status:** 🔴 Not Started
**Priority:** P1
**Assignee:** TBD

**Issue:**
- Hardcoded `1 days` with no justification
- Should be community decision

**Tasks:**
- [ ] Create community RFC
- [ ] Document rationale in architecture doc
- [ ] Survey other DAOs (Compound: 2 days, Uniswap: 3 days)
- [ ] Consider: Make it 2 days to match votingDelay norms?

---

### 3. Test Coverage Gaps

#### 3.1 Fuzz Testing
**Status:** 🔴 Not Started
**Priority:** P0
**Assignee:** TBD

**Tasks:**
- [ ] `testFuzz_SignerOrderingEnforcement(address[] memory signers)`
- [ ] `testFuzz_ProposalUpdateGasLimits(uint8 numSigners)`
- [ ] `testFuzz_UpdateWithDifferentArrayLengths(uint256 numTargets)`
- [ ] `testFuzz_SignatureDeadlineEdgeCases(uint256 deadline)`

---

#### 3.2 Invariant Testing
**Status:** 🔴 Not Started
**Priority:** P0
**Assignee:** TBD

**Tasks:**
- [ ] `testInvariant_VotesNeverExceedSupply()`
- [ ] `testInvariant_OnlyOneActiveProposalPerID()`
- [ ] `testInvariant_ReplacedProposalsAlwaysCanceled()`
- [ ] `testInvariant_ProposerAlwaysHasThresholdAtCreation()`

---

#### 3.3 ERC-1271 Smart Wallet Tests
**Status:** 🔴 Not Started
**Priority:** P1
**Assignee:** TBD

**Tasks:**
- [ ] Deploy mock ERC-1271 wallet contract
- [ ] Test `proposeBySigs` with smart wallet signer
- [ ] Test `castVoteBySig` with smart wallet
- [ ] Test `updateProposalBySigs` with smart wallet
- [ ] Document ERC-1271 compatibility in docs

---

#### 3.4 Edge Case Tests
**Status:** 🔴 Not Started
**Priority:** P1
**Assignee:** TBD

**Tasks:**
- [ ] `test_UpdateAtExactUpdatePeriodEnd()` - Timestamp boundary
- [ ] `test_ProposalIDCollision()` - Theoretical but should revert
- [ ] `testRevert_ReentrancyDuringPropose()` - Safety check
- [ ] `test_MultipleUpdatesInSequence()` - Update 5 times
- [ ] `testRevert_UpdateAfterVotingStarted()` - State machine edge

---

### 4. Breaking Change Management

#### 4.1 Migration Guide for castVoteBySig
**Status:** 🔴 Not Started
**Priority:** P0 (BLOCKING)
**Assignee:** TBD

**Required Content:**
- [ ] Side-by-side API comparison (old vs new)
- [ ] Code example: Generate new signature format
- [ ] Code example: ethers.js migration
- [ ] Code example: viem migration
- [ ] Code example: wagmi hooks migration
- [ ] Nonce handling explanation
- [ ] Common errors + troubleshooting
- [ ] Timeline for deprecation (testnet → mainnet)

**Deliverable:** `docs/MIGRATION_GUIDE_VOTE_BY_SIG.md`

---

#### 4.2 Ecosystem Partner Coordination
**Status:** 🔴 Not Started
**Priority:** P0 (BLOCKING)
**Assignee:** TBD

**Partners to Contact:**
- [ ] Nouns.wtf frontend team
- [ ] Agora governance platform
- [ ] Tally governance platform
- [ ] Snapshot (if applicable)
- [ ] Block explorer teams (Etherscan, Basescan)

**Process:**
1. Share migration guide draft
2. Schedule coordination calls
3. Provide testnet endpoints
4. Gather feedback + adjust timeline
5. Staged rollout agreement

---

#### 4.3 Subgraph Schema Updates
**Status:** 🔴 Not Started
**Priority:** P1
**Assignee:** TBD

**Tasks:**
- [ ] Schema: Add `proposalSigners` relationship
- [ ] Schema: Add `proposalReplacements` relationship
- [ ] Schema: Add `ProposalRevision` entity
- [ ] Handler: `ProposalUpdated` event
- [ ] Handler: `ProposalSignersSet` event
- [ ] Example query: Get current proposal version
- [ ] Example query: Get proposal revision history
- [ ] Example query: Get all proposals by signer

**Deliverable:** `docs/SUBGRAPH_MIGRATION.md`

---

### 5. Operational Safety

#### 5.1 Emergency Pause Mechanism
**Status:** 🔴 Not Started
**Priority:** P1
**Assignee:** TBD

**Issue:**
- No circuit breaker for critical bugs
- Cannot disable proposal updates without full upgrade

**Tasks:**
- [ ] Add `_proposalUpdatesEnabled` boolean flag
- [ ] Add `pauseProposalUpdates()` owner function
- [ ] Add `unpauseProposalUpdates()` owner function
- [ ] Guard `updateProposal` and `updateProposalBySigs`
- [ ] Add tests for paused state
- [ ] Document emergency procedures

**Code Sketch:**
```solidity
bool private _proposalUpdatesEnabled = true;

function pauseProposalUpdates() external onlyOwner {
    _proposalUpdatesEnabled = false;
    emit ProposalUpdatesPaused();
}
```

---

#### 5.2 Rollback Plan Documentation
**Status:** 🔴 Not Started
**Priority:** P1
**Assignee:** TBD

**Required Content:**
- [ ] Identify rollback triggers (critical bug criteria)
- [ ] Emergency governance proposal template
- [ ] Downgrade procedure (revert to v2.0.0)
- [ ] Communication plan (discord, twitter, email)
- [ ] Data preservation strategy (proposal history)
- [ ] Timeline estimates for emergency response

**Deliverable:** `docs/EMERGENCY_ROLLBACK_PLAN.md`

---

#### 5.3 Staged Rollout Plan
**Status:** 🔴 Not Started
**Priority:** P1
**Assignee:** TBD

**Timeline:**
- [ ] Week 1-2: Testnet deployment (Sepolia, Base Sepolia)
- [ ] Week 3: Canary DAO selection (criteria: low TVL, active governance)
- [ ] Week 4: Canary DAO upgrade + monitoring
- [ ] Week 5: Feedback review + fixes
- [ ] Week 6+: Batch upgrade (10 DAOs/week)

**Canary DAO Criteria:**
- Treasury < $100k
- Active governance (>5 proposals/month)
- Engaged community
- Willing to test new features

**Deliverable:** `docs/ROLLOUT_PLAN.md`

---

### 6. Community Education

#### 6.1 DAO Operator Best Practices
**Status:** 🔴 Not Started
**Priority:** P2
**Assignee:** TBD

**Content Needed:**
- [ ] When to use `propose` vs `proposeBySigs`
- [ ] How to coordinate with signers
- [ ] Best practices for proposal updates
- [ ] How to handle signer disagreements
- [ ] Social norms for update frequency
- [ ] Example workflows with screenshots

**Deliverable:** `docs/DAO_OPERATOR_GUIDE.md`

---

#### 6.2 Community RFC - Default Updatable Period
**Status:** 🔴 Not Started
**Priority:** P1
**Assignee:** TBD

**Questions for Community:**
- Is 1 day enough time to review proposals before voting?
- Should it match votingDelay (typically 2 days)?
- Should different DAO sizes have different defaults?

**Process:**
1. Post RFC to governance forum
2. 1-week discussion period
3. Temperature check poll
4. Update constant based on consensus

---

#### 6.3 Video Tutorials
**Status:** 🟡 Post-Launch
**Priority:** P3
**Assignee:** TBD

**Topics:**
- Creating a signed proposal
- Updating a proposal
- Tracking proposal revisions
- Understanding proposal states

---

### 7. Audit Preparation

#### 7.1 Audit Firm Engagement
**Status:** 🔴 Not Started
**Priority:** P1
**Assignee:** TBD

**Recommended Firms:**
- Trail of Bits (governance specialty)
- OpenZeppelin
- Spearbit

**Timeline:** 4-6 weeks engagement

**Tasks:**
- [ ] Get quotes from 3 firms
- [ ] Select auditor
- [ ] Prepare scope document
- [ ] Schedule kickoff call

---

#### 7.2 Audit Scope Document
**Status:** 🔴 Not Started
**Priority:** P1
**Assignee:** TBD

**Content:**
- [ ] Contract list + LOC count
- [ ] Known issues / design decisions
- [ ] Attack vectors to focus on
- [ ] Upgrade safety requirements
- [ ] Test coverage report

**Deliverable:** `docs/AUDIT_SCOPE.md`

---

#### 7.3 Bug Bounty Program
**Status:** 🔴 Not Started
**Priority:** P2
**Assignee:** TBD

**Platform:** Immunefi

**Reward Structure:**
- Critical: $100k+
- High: $50k
- Medium: $10k
- Low: $1k

**Tasks:**
- [ ] Create Immunefi profile
- [ ] Define severity criteria
- [ ] Fund bounty pool
- [ ] Announce launch

---

## Timeline Estimate

### Phase 1: Pre-Audit (3-4 weeks)
**Target:** Address all P0 items

- Week 1: Code quality fixes + gas optimizations
- Week 2: Fuzz tests + invariant tests
- Week 3: Migration guide + community RFC
- Week 4: ERC-1271 tests + emergency mechanisms

### Phase 2: Audit (4-6 weeks)
- Week 1: Audit kickoff
- Week 2-5: Audit in progress
- Week 6: Findings review + fixes

### Phase 3: Pre-Launch (2-3 weeks)
- Week 1: Testnet deployment + subgraph
- Week 2: Ecosystem partner testing
- Week 3: Bug bounty launch + docs finalization

### Phase 4: Mainnet Rollout (4-6 weeks)
- Week 1: Manager upgrade + registration
- Week 2: Canary DAO upgrade
- Week 3: Monitor + gather feedback
- Week 4-6: Batch upgrade remaining DAOs

**Total: 13-19 weeks (3-4.5 months)**

---

## Success Metrics

**Code Quality:**
- [ ] 90%+ test coverage
- [ ] Zero high/critical audit findings
- [ ] Gas costs documented + acceptable

**Community Readiness:**
- [ ] 3+ major frontends migrated
- [ ] Subgraph deployed + tested
- [ ] 100+ community members trained

**Production Safety:**
- [ ] 30+ days canary deployment without issues
- [ ] Emergency procedures tested
- [ ] Rollback plan validated

---

## Progress Tracking

**Last Updated:** 2026-05-20
**Items Completed:** 0 / 50+
**Estimated Completion:** 2026-09-15

### Weekly Progress Log

#### 2026-05-20
- ✅ Created production readiness tracking document
- 🔄 Starting Phase 1: Pre-Audit fixes

---

## Notes

- This document should be updated as each task is completed
- Commit messages should reference task numbers
- All P0 items must be complete before audit
- All P1 items must be complete before mainnet
- P2 items can be addressed post-launch with careful monitoring
