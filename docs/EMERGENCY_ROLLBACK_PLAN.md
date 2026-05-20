# Emergency Rollback Plan: Governor v2.1.0

**Purpose:** Procedures for emergency response if critical issues discovered post-upgrade
**Priority:** P1 - Must exist before mainnet deployment
**Status:** Production-Ready Template

---

## When to Activate This Plan

### Critical Issues (Immediate Rollback)
- **Security vulnerability** actively being exploited
- **Funds at risk** - treasury execution compromise
- **Governance deadlock** - unable to create/vote on proposals
- **State corruption** - proposal data inconsistent

### Major Issues (Urgent Rollback)
- **Vote counting errors** discovered
- **Signature verification bypass**
- **Proposal update exploit** causing harm

### Do NOT Rollback For:
- Minor UX issues
- Documentation errors
- Non-critical gas inefficiencies
- Individual DAO preference changes

---

## Emergency Response Team

### Roles & Responsibilities

**Incident Commander:** Builder DAO multisig holder
- Declares emergency state
- Approves rollback decision
- Communicates with community

**Technical Lead:** Protocol developer
- Assesses technical impact
- Prepares rollback proposal
- Executes technical steps

**Community Manager:** DAO communications
- Announces emergency
- Updates community channels
- Manages external communications

**Security Lead:** Audit firm contact
- Validates vulnerability
- Assesses exploit scope
- Provides security guidance

---

## Rollback Decision Tree

```
Critical Issue Detected
    ↓
Is exploit active? ───YES──→ IMMEDIATE ROLLBACK (Section A)
    ↓ NO
    ↓
Are funds at risk? ───YES──→ URGENT ROLLBACK (Section B)
    ↓ NO
    ↓
Can issue be patched? ───YES──→ HOT FIX (Section C)
    ↓ NO
    ↓
Schedule PLANNED DOWNGRADE (Section D)
```

---

## Section A: Immediate Rollback (< 2 hours)

**Trigger:** Active exploit, funds at risk
**Timeline:** Execute within 2 hours of detection

### Step 1: Emergency Pause (If Vetoer Exists)
```
Time: 0-5 minutes
Actor: Vetoer (if configured)
```

**Actions:**
1. Vetoer calls `veto(proposalId)` on any malicious proposals
2. Prevents execution while rollback prepared
3. **Note:** This only stops specific proposals, not the feature

**Limitations:**
- Only works if DAO has vetoer configured
- Only stops individual proposals, not systemic issues
- Buys time but doesn't fix underlying problem

### Step 2: Coordinate Multi-Sig (For Manager Upgrade Authority)
```
Time: 5-30 minutes
Actor: Manager owner (typically multi-sig)
```

**If Manager owner is EOA:**
- Single signer can immediately register downgrade
- Proceed to Step 3

**If Manager owner is multi-sig (e.g., Gnosis Safe):**
1. Alert all signers via emergency channel
2. Create downgrade transaction in multi-sig UI
3. Collect required signatures (typically 3-5)
4. Execute when threshold met

**Multi-sig Emergency Protocol:**
- Keep 24/7 contact list for signers
- Use secure group chat for coordination
- Pre-approve rollback templates if possible
- Document who's on call each week

### Step 3: Register Downgrade Implementation
```
Time: 30-60 minutes
Actor: Manager owner
```

**Prepare downgrade implementation:**
```solidity
// Get current (v2.1.0) and previous (v2.0.0) implementation addresses
address currentImpl = manager.governorImpl();
address previousImpl = 0x...; // v2.0.0 address (document this!)

// Register downgrade path in Manager
manager.registerUpgrade(
    currentImpl,
    previousImpl
);
```

**Critical:** Previous implementation address must be documented in advance!

**Document here:**
- **v2.0.0 Governor Implementation:** `[TO BE FILLED AT DEPLOYMENT]`
- **v2.1.0 Governor Implementation:** `[TO BE FILLED AT DEPLOYMENT]`
- **Manager Contract:** `[TO BE FILLED AT DEPLOYMENT]`

### Step 4: Execute Emergency DAO Proposal
```
Time: 60-120 minutes
Actor: DAO with emergency powers (if exists)
```

**Option A: Emergency DAO with fast-track:**
Some DAOs have emergency procedures (e.g., 1-hour voting):

```solidity
// Emergency proposal with expedited timeline
bytes memory upgradeCalldata = abi.encodeWithSignature(
    "_authorizeUpgrade(address)",
    previousImpl
);

address[] memory targets = new address[](1);
targets[0] = address(governor);

uint256[] memory values = new uint256[](1);
values[0] = 0;

bytes[] memory calldatas = new bytes[](1);
calldatas[0] = upgradeCalldata;

// Create emergency proposal
governor.propose(
    targets,
    values,
    calldatas,
    "EMERGENCY ROLLBACK TO v2.0.0: [Brief reason]"
);
```

**Option B: No emergency DAO:**
- Must wait for normal governance timeline
- Rely on vetoer + community coordination in the meantime
- Consider: Should DAOs implement emergency procedures?

### Step 5: Community Communication
```
Time: Immediate (parallel with technical steps)
Actor: Community Manager
```

**Communication Template:**

**🚨 EMERGENCY: Governor Rollback In Progress**

**Status:** Critical issue detected in Governor v2.1.0
**Action:** Rolling back to v2.0.0
**ETA:** [X] hours
**Impact:** [Describe user impact]

**What happened:**
- [Brief technical description]
- [Link to post-mortem when available]

**What we're doing:**
- Emergency rollback to previous version
- Investigating root cause
- Will share full post-mortem

**What you should do:**
- **DO NOT** create new proposals until rollback complete
- **DO NOT** vote on proposals created after [timestamp]
- Monitor [Discord/Forum] for updates

**Next update:** [Time]

---

## Section B: Urgent Rollback (< 24 hours)

**Trigger:** Major issue, no active exploit but risk present
**Timeline:** Execute within 24 hours

### Follow Standard Governance Process

1. **Assess Impact** (0-2 hours)
   - Document the issue thoroughly
   - Determine affected DAOs
   - Estimate risk level

2. **Prepare Rollback Proposal** (2-4 hours)
   - Write detailed proposal description
   - Include technical justification
   - Link to issue documentation

3. **Emergency Proposal Vote** (4-24 hours)
   - Submit rollback proposal
   - Rally community for fast approval
   - If DAO has updatable period, propose immediately to skip it
   - If DAO has short voting period, can complete in 24hrs

4. **Execute Downgrade** (Immediate after approval)
   - Queue in treasury
   - Wait for timelock (if configured)
   - Execute upgrade transaction

---

## Section C: Hot Fix (Patch Forward)

**Trigger:** Issue can be fixed without rollback
**Timeline:** 1-7 days

### When to Use Hot Fix Instead of Rollback

- Bug is minor and non-critical
- Fix is simple and low-risk
- Rollback would cause more disruption than fix
- Issue affects limited functionality

### Hot Fix Process

1. **Develop Fix** (1-3 days)
   - Create patch branch
   - Write tests for bug
   - Implement minimal fix
   - Run full test suite

2. **Emergency Audit** (1-2 days)
   - Get rapid review from auditor
   - Focus on changed code only
   - Get sign-off on fix

3. **Deploy v2.1.1** (1 day)
   - Deploy patched implementation
   - Register upgrade in Manager
   - Test on testnet first

4. **Governance Vote** (2-7 days)
   - Submit upgrade proposal
   - Explain fix in detail
   - Vote and execute

---

## Section D: Planned Downgrade (Voluntary)

**Trigger:** DAO chooses to revert for non-emergency reasons
**Timeline:** Standard governance process

### Use Cases
- Feature not meeting community needs
- Prefer previous UX
- Want to wait for v3.0.0

### Process
Same as any governance proposal:
1. Community discussion (1-2 weeks)
2. Formal proposal (1 day)
3. Voting period (typically 7-14 days)
4. Execution (1-2 days)

---

## Technical Rollback Procedures

### For Individual DAOs

**Downgrade Single DAO Governor:**

```solidity
// In governance proposal:
function downgradeGovernor(address previousImpl) external {
    // This must be called by governor's own proposal
    require(msg.sender == address(this), "Only via proposal");

    // Authorize upgrade (downgrade) to previous version
    _authorizeUpgrade(previousImpl);
}
```

**Proposal Parameters:**
```javascript
const targets = [governorProxy];
const values = [0];
const calldatas = [
  governorInterface.encodeFunctionData("_authorizeUpgrade", [
    previousImplementation
  ])
];
const description = "Emergency rollback to Governor v2.0.0";
```

### For Multiple DAOs (Batch Rollback)

**If many DAOs affected:**

1. **Coordinate timing**
   - Stagger proposals to avoid network congestion
   - Target 10-20 DAOs per day

2. **Prepare scripts**
   ```javascript
   // Automated proposal creation
   for (const dao of affectedDAOs) {
     await createRollbackProposal(dao.governor, previousImpl);
   }
   ```

3. **Monitor execution**
   - Track proposal status
   - Verify successful downgrades
   - Document any failures

---

## Data Preservation

### Before Rollback: Capture State

**Critical data to preserve:**

1. **Proposal snapshots**
   ```
   For each proposal created with v2.1.0:
   - Proposal ID
   - Signer list (if signed)
   - Update history (if updated)
   - Current votes
   - State
   ```

2. **Replacement mappings**
   ```javascript
   // Query all replaced proposals
   const replacedProposals = await subgraph.query(`{
     proposals(where: { state: "REPLACED" }) {
       id
       replacedBy { id }
     }
   }`);
   ```

3. **User signatures**
   ```
   - Nonce values per user
   - Signed but not executed proposals
   ```

**Storage location:**
- Export to IPFS
- Store in DAO-controlled address
- Include in rollback proposal description

### After Rollback: State Migration

**What happens to v2.1.0 data:**

- **Proposals in Updatable state:** Become Pending immediately
- **Signed proposals:** Lose signer information (but remain valid)
- **Replaced proposals:** Show as Canceled in v2.0.0
- **Proposal nonces:** No longer tracked (not breaking)

**User impact:**
- Can no longer update existing proposals
- Cannot create new signed proposals
- Can still vote/execute existing proposals
- Historical data preserved in events

---

## Post-Rollback Actions

### Immediate (Day 1)

1. **Verify rollback successful**
   - Check all DAOs downgraded correctly
   - Test basic governance functions
   - Verify no data corruption

2. **Announce completion**
   - Update community channels
   - Confirm service restored
   - Set expectations for next steps

3. **Begin root cause analysis**
   - Assemble technical team
   - Review exploit details
   - Document timeline

### Short-term (Week 1)

4. **Publish post-mortem**
   - What happened
   - Why it happened
   - What we're doing to prevent recurrence

5. **Compensate affected users** (if applicable)
   - Identify losses
   - Propose compensation plan
   - Execute via governance

6. **Update documentation**
   - Mark v2.1.0 as deprecated
   - Update integration guides
   - Add warnings to old docs

### Long-term (Month 1)

7. **Fix the issue**
   - Develop proper fix
   - Get re-audited
   - Test extensively

8. **Prepare v2.1.1 or v2.2.0**
   - Incorporate lessons learned
   - Enhanced testing
   - Better safeguards

9. **Rebuild confidence**
   - Transparent communication
   - Testnet validation
   - Gradual re-rollout

---

## Communication Templates

### Emergency Announcement

**Subject:** 🚨 URGENT: Governor Rollback Required

**Body:**
```
EMERGENCY SITUATION

We have identified a [critical/major] issue in Governor v2.1.0 that requires
immediate action.

ISSUE: [Brief description]

IMPACT: [What's affected]

ACTION REQUIRED: We are rolling back all DAOs to Governor v2.0.0

TIMELINE:
- Now: Rollback proposals being submitted
- [X] hours: Voting completes
- [X] hours: Rollback executed

WHAT YOU SHOULD DO:
- [Specific user actions]

We will provide updates every [X] hours until resolved.

Next update: [Time]
```

### Status Update Template

**Subject:** Rollback Status Update #[N]

**Body:**
```
ROLLBACK UPDATE #[N]

Status: [In Progress / Complete / Blocked]

Progress:
- [X] of [Y] DAOs rolled back
- [X] of [Y] proposals migrated
- [X] of [Y] users affected

Issues encountered:
- [List any problems]

Next steps:
- [What's happening next]

ETA for completion: [Time]

Next update: [Time]
```

### Post-Mortem Template

**Subject:** Post-Mortem: Governor v2.1.0 Rollback

**Sections:**
1. Executive Summary
2. Timeline of Events
3. Root Cause Analysis
4. Impact Assessment
5. Remediation Steps
6. Lessons Learned
7. Action Items
8. Conclusion

---

## Rollback Checklist

### Pre-Deployment (Do This Now!)
- [ ] Document v2.0.0 implementation address
- [ ] Document v2.1.0 implementation address
- [ ] Document Manager contract address
- [ ] Establish 24/7 emergency contact list
- [ ] Set up emergency communication channels
- [ ] Brief all multi-sig signers on process
- [ ] Identify emergency powers (vetoer, fast-track)
- [ ] Test rollback on testnet

### During Emergency
- [ ] Declare emergency state
- [ ] Assess issue severity
- [ ] Choose rollback path (A/B/C/D)
- [ ] Alert emergency response team
- [ ] Communicate with community
- [ ] Preserve critical data
- [ ] Execute technical rollback
- [ ] Verify rollback successful
- [ ] Announce completion

### Post-Rollback
- [ ] Publish post-mortem
- [ ] Compensate affected users
- [ ] Update documentation
- [ ] Fix underlying issue
- [ ] Re-audit fix
- [ ] Test on testnet
- [ ] Prepare re-deployment
- [ ] Rebuild community confidence

---

## Contact Information

### Emergency Response Team

**Incident Commander:** [TO BE FILLED]
- Discord: @username
- Telegram: @username
- Email: email@domain.com
- Phone: [For critical emergencies]

**Technical Lead:** [TO BE FILLED]
- GitHub: @username
- Discord: @username

**Community Manager:** [TO BE FILLED]
- Discord: @username
- Twitter: @handle

**Security Lead / Audit Firm:** [TO BE FILLED]
- Email: security@auditfirm.com
- Emergency hotline: [Phone]

### Communication Channels

**Primary:** [Discord server link]
**Backup:** [Telegram group link]
**Public:** [Twitter account]
**Status Page:** [URL if exists]

---

## Lessons from Past Incidents

### Case Study: [Example Protocol] Governance Bug (Hypothetical)

**What happened:** Signature validation bypass
**Response time:** 4 hours from detection to rollback
**What worked:** Pre-established emergency procedures, fast multi-sig coordination
**What didn't:** Communication delays, unclear documentation
**Lessons:** Have templates ready, test procedures regularly

---

## Testing This Plan

### Testnet Drills (Quarterly)

1. **Simulate emergency**
   - Deploy v2.1.0 to testnet
   - Identify "critical issue"
   - Execute full rollback

2. **Measure performance**
   - Time each step
   - Identify bottlenecks
   - Update procedures

3. **Rotate roles**
   - Different people each drill
   - Ensure redundancy
   - Train new team members

---

**Last Updated:** 2026-05-20
**Next Review:** Before mainnet deployment
**Status:** Production-Ready Template

**Remember:** The best emergency plan is one you never have to use. Thorough testing and auditing are the primary defense.
