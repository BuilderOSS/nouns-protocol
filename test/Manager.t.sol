// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import { NounsBuilderTest } from "./utils/NounsBuilderTest.sol";

import { IManager, Manager } from "../src/manager/Manager.sol";

import { MockImpl } from "./utils/mocks/MockImpl.sol";
import { Token } from "../src/token/Token.sol";
import { Auction } from "../src/auction/Auction.sol";
import { DAOFactory } from "../src/factory/DAOFactory.sol";
import { Governor } from "../src/governance/governor/Governor.sol";
import { Treasury } from "../src/governance/treasury/Treasury.sol";
import { MetadataRenderer } from "../src/token/metadata/MetadataRenderer.sol";

contract ManagerTest is NounsBuilderTest {
    MockImpl internal mockImpl;
    address internal altMetadataImpl;
    bytes32 internal constant ALT_DEPLOY_SALT = keccak256("ALT_DEPLOY_SALT");
    uint256 internal constant ATTACKER_PK = 0xBADC0DE;
    uint256 internal constant VICTIM_PK = 0xA11CE;

    function setUp() public virtual override {
        super.setUp();

        mockImpl = new MockImpl();
        altMetadataImpl = address(new MetadataRenderer(address(manager)));
    }

    function setupAltMock() internal virtual {
        setMockFounderParams();

        setMockTokenParamsWithRenderer(altMetadataImpl);

        setMockAuctionParams();

        setMockGovParams();
    }

    function test_GetAddresses() public {
        deployMock();

        (address _metadata, address _auction, address _treasury, address _governor) = manager.getAddresses(address(token));

        assertEq(address(metadataRenderer), _metadata);
        assertEq(address(auction), _auction);
        assertEq(address(treasury), _treasury);
        assertEq(address(governor), _governor);
    }

    function test_TokenInitialized() public {
        deployMock();

        assertEq(token.owner(), address(founder));
        assertEq(token.auction(), address(auction));
        assertEq(token.totalSupply(), 0);
        vm.prank(founder);
        auction.unpause();
        assertEq(token.owner(), address(treasury));
        assertEq(token.totalSupply(), 3);
    }

    function test_MetadataRendererInitialized() public {
        deployMock();

        assertEq(metadataRenderer.owner(), address(founder));
    }

    function test_GetDAOVersions() public {
        deployMock();

        string memory version = manager.contractVersion();
        IManager.DAOVersionInfo memory versionInfo = manager.getDAOVersions(address(token));
        assertEq(versionInfo.token, version);
        assertEq(versionInfo.metadata, version);
        assertEq(versionInfo.governor, version);
        assertEq(versionInfo.auction, version);
        assertEq(versionInfo.treasury, version);
    }

    function test_AuctionInitialized() public {
        deployMock();

        assertEq(auction.owner(), founder);
        assertTrue(auction.paused());

        assertEq(auction.treasury(), address(treasury));
        assertEq(auction.duration(), auctionParams.duration);
        assertEq(auction.reservePrice(), auctionParams.reservePrice);
        assertEq(auction.timeBuffer(), 5 minutes);
        assertEq(auction.minBidIncrement(), 10);
    }

    function test_TreasuryInitialized() public {
        deployMock();

        assertEq(treasury.owner(), address(governor));
        assertEq(treasury.delay(), govParams.timelockDelay);
    }

    function test_GovernorInitialized() public {
        deployMock();

        assertEq(governor.owner(), address(treasury));
        assertEq(governor.votingDelay(), govParams.votingDelay);
        assertEq(governor.votingPeriod(), govParams.votingPeriod);
    }

    function testRevert_DeployWithoutFounder() public {
        setMockTokenParams();

        setMockAuctionParams();

        setMockGovParams();

        foundersArr.push();

        vm.expectRevert(abi.encodeWithSignature("FOUNDER_REQUIRED()"));
        deploy(foundersArr, tokenParams, auctionParams, govParams);
    }

    function test_RegisterUpgrade() public {
        address owner = manager.owner();

        vm.prank(owner);
        manager.registerUpgrade(tokenImpl, address(mockImpl));

        assertTrue(manager.isRegisteredUpgrade(tokenImpl, address(mockImpl)));
    }

    function test_RemoveUpgrade() public {
        address owner = manager.owner();

        vm.prank(owner);
        manager.registerUpgrade(tokenImpl, address(mockImpl));

        vm.prank(owner);
        manager.removeUpgrade(tokenImpl, address(mockImpl));

        assertFalse(manager.isRegisteredUpgrade(tokenImpl, address(mockImpl)));
    }

    function testRevert_OnlyOwnerCanRegisterUpgrade() public {
        vm.expectRevert(abi.encodeWithSignature("ONLY_OWNER()"));
        manager.registerUpgrade(address(token), address(mockImpl));
    }

    function testRevert_OnlyOwnerCanRemoveUpgrade() public {
        vm.expectRevert(abi.encodeWithSignature("ONLY_OWNER()"));
        manager.removeUpgrade(address(token), address(mockImpl));
    }

    function test_DeployWithAltRenderer() public {
        setupAltMock();
        deploy(foundersArr, tokenParams, auctionParams, govParams);

        assertEq(metadataRenderer.owner(), address(founder));
    }

    function test_SetNewRenderer() public {
        deployMock();

        vm.startPrank(founder);
        manager.setMetadataRenderer(address(token), metadataRendererImpl, tokenParams.initStrings);
        vm.stopPrank();
    }

    function testRevert_DeployWithEmptyFounderArray() public {
        IManager.FounderParams[] memory emptyFounders = new IManager.FounderParams[](0);
        setMockTokenParams();
        setMockAuctionParams();
        setMockGovParams();

        vm.expectRevert(IManager.FOUNDER_REQUIRED.selector);
        manager.deploy(emptyFounders, tokenParams, auctionParams, govParams);
    }

    function test_DeployDeterministicMatchesPrediction() public {
        setMockFounderParams();
        setMockTokenParams();
        setMockAuctionParams();
        setMockGovParams();

        address deployer = address(this);
        (address predictedToken, address predictedMetadata, address predictedAuction, address predictedTreasury, address predictedGovernor) =
            manager.predictDeterministicAddresses(deployer, DEFAULT_DEPLOY_SALT);

        deployDeterministic(foundersArr, tokenParams, auctionParams, govParams, DEFAULT_DEPLOY_SALT);

        assertEq(address(token), predictedToken);
        assertEq(address(metadataRenderer), predictedMetadata);
        assertEq(address(auction), predictedAuction);
        assertEq(address(treasury), predictedTreasury);
        assertEq(address(governor), predictedGovernor);
    }

    function testRevert_ManagerConstructorWithNonFactoryContract() public {
        vm.expectRevert(abi.encodeWithSelector(Manager.INVALID_FACTORY_CONTRACT.selector, address(mockImpl)));
        new Manager(tokenImpl, metadataRendererImpl, auctionImpl, treasuryImpl, governorImpl, zoraDAO, address(mockImpl));
    }

    function testRevert_DeployDeterministicWithWrongFactoryBinding() public {
        address wrongBoundManager = address(0xBEEF);
        address wrongFactory = address(new DAOFactory(wrongBoundManager));
        address newManagerImpl = address(new Manager(tokenImpl, metadataRendererImpl, auctionImpl, treasuryImpl, governorImpl, zoraDAO, wrongFactory));

        vm.prank(zoraDAO);
        manager.upgradeTo(newManagerImpl);

        setMockFounderParams();
        setMockTokenParams();
        setMockAuctionParams();
        setMockGovParams();

        vm.expectRevert(abi.encodeWithSelector(Manager.INVALID_FACTORY_BINDING.selector, wrongFactory, address(manager), wrongBoundManager));
        manager.deployDeterministic(foundersArr, tokenParams, auctionParams, govParams, DEFAULT_DEPLOY_SALT);
    }

    function test_PredictDeterministicAddressesChangesWithSalt() public {
        address deployer = address(this);
        (address tokenA, address metadataA, address auctionA, address treasuryA, address governorA) =
            manager.predictDeterministicAddresses(deployer, DEFAULT_DEPLOY_SALT);
        (address tokenB, address metadataB, address auctionB, address treasuryB, address governorB) =
            manager.predictDeterministicAddresses(deployer, ALT_DEPLOY_SALT);

        assertTrue(tokenA != tokenB);
        assertTrue(metadataA != metadataB);
        assertTrue(auctionA != auctionB);
        assertTrue(treasuryA != treasuryB);
        assertTrue(governorA != governorB);
    }

    function test_PredictDeterministicAddressesChangesWithDeployer() public {
        address attacker = vm.addr(ATTACKER_PK);
        address victim = vm.addr(VICTIM_PK);

        (address attackerToken, address attackerMetadata, address attackerAuction, address attackerTreasury, address attackerGovernor) =
            manager.predictDeterministicAddresses(attacker, DEFAULT_DEPLOY_SALT);
        (address victimToken, address victimMetadata, address victimAuction, address victimTreasury, address victimGovernor) =
            manager.predictDeterministicAddresses(victim, DEFAULT_DEPLOY_SALT);

        assertTrue(attackerToken != victimToken);
        assertTrue(attackerMetadata != victimMetadata);
        assertTrue(attackerAuction != victimAuction);
        assertTrue(attackerTreasury != victimTreasury);
        assertTrue(attackerGovernor != victimGovernor);
    }

    function test_DeployDeterministicSameSaltDifferentDeployersDoNotConflict() public {
        address attacker = vm.addr(ATTACKER_PK);
        address victim = vm.addr(VICTIM_PK);

        setMockFounderParams();
        setMockTokenParams();
        setMockAuctionParams();
        setMockGovParams();

        (address attackerPredictedToken,,,,) = manager.predictDeterministicAddresses(attacker, DEFAULT_DEPLOY_SALT);
        (
            address victimPredictedToken,
            address victimPredictedMetadata,
            address victimPredictedAuction,
            address victimPredictedTreasury,
            address victimPredictedGovernor
        ) = manager.predictDeterministicAddresses(victim, DEFAULT_DEPLOY_SALT);

        vm.prank(attacker);
        manager.deployDeterministic(foundersArr, tokenParams, auctionParams, govParams, DEFAULT_DEPLOY_SALT);

        (address attackerMetadata,,,) = manager.getAddresses(attackerPredictedToken);
        assertTrue(attackerMetadata != address(0));

        vm.prank(victim);
        (address victimToken, address victimMetadata, address victimAuction, address victimTreasury, address victimGovernor) =
            manager.deployDeterministic(foundersArr, tokenParams, auctionParams, govParams, DEFAULT_DEPLOY_SALT);

        assertEq(victimToken, victimPredictedToken);
        assertEq(victimMetadata, victimPredictedMetadata);
        assertEq(victimAuction, victimPredictedAuction);
        assertEq(victimTreasury, victimPredictedTreasury);
        assertEq(victimGovernor, victimPredictedGovernor);
        assertTrue(attackerPredictedToken != victimToken);
    }

    function test_PredictDeterministicAddressesStableAcrossManagerUpgrade() public {
        // NOTE: With the new CREATE3 factory approach, addresses are stable across Manager upgrades
        // because they depend on the factory address and deployer, not Manager address or implementation addresses
        address deployer = address(this);
        (address tokenBefore, address metadataBefore, address auctionBefore, address treasuryBefore, address governorBefore) =
            manager.predictDeterministicAddresses(deployer, DEFAULT_DEPLOY_SALT);

        address newTokenImpl = address(new Token(address(manager)));
        address newMetadataImpl = address(new MetadataRenderer(address(manager)));
        address newAuctionImpl = address(new Auction(address(manager), address(rewards), weth, 1, 2));
        address newTreasuryImpl = address(new Treasury(address(manager)));
        address newGovernorImpl = address(new Governor(address(manager)));
        address newManagerImpl =
            address(new Manager(newTokenImpl, newMetadataImpl, newAuctionImpl, newTreasuryImpl, newGovernorImpl, zoraDAO, daoFactory));

        vm.prank(zoraDAO);
        manager.upgradeTo(newManagerImpl);

        // Same implementation params mean same addresses (since CREATE3 factory and deployer are constant)
        (address tokenAfter, address metadataAfter, address auctionAfter, address treasuryAfter, address governorAfter) =
            manager.predictDeterministicAddresses(deployer, DEFAULT_DEPLOY_SALT);

        // Addresses remain the same because CREATE3 factory address and deployer are constant
        assertEq(tokenBefore, tokenAfter);
        assertEq(metadataBefore, metadataAfter);
        assertEq(auctionBefore, auctionAfter);
        assertEq(treasuryBefore, treasuryAfter);
        assertEq(governorBefore, governorAfter);
    }

    function testRevert_DeployDeterministicWithUsedSalt() public {
        setMockFounderParams();
        setMockTokenParams();
        setMockAuctionParams();
        setMockGovParams();

        deployDeterministic(foundersArr, tokenParams, auctionParams, govParams, DEFAULT_DEPLOY_SALT);

        vm.expectRevert();
        manager.deployDeterministic(foundersArr, tokenParams, auctionParams, govParams, DEFAULT_DEPLOY_SALT);
    }

    function test_PredictionConsistentBeforeAndAfterDeploy() public {
        setMockFounderParams();
        setMockTokenParams();
        setMockAuctionParams();
        setMockGovParams();

        address deployer = address(this);
        bytes32 salt = keccak256("PREDICTION_STABILITY_TEST");

        // Predict addresses BEFORE deployment
        (address predictedToken, address predictedMetadata, address predictedAuction, address predictedTreasury, address predictedGovernor) =
            manager.predictDeterministicAddresses(deployer, salt);

        // Deploy the DAO
        (address token, address metadata, address auction, address treasury, address governor) =
            manager.deployDeterministic(foundersArr, tokenParams, auctionParams, govParams, salt);

        // Predict addresses AFTER deployment (should be the same)
        (
            address predictedTokenAfter,
            address predictedMetadataAfter,
            address predictedAuctionAfter,
            address predictedTreasuryAfter,
            address predictedGovernorAfter
        ) = manager.predictDeterministicAddresses(deployer, salt);

        // Verify predictions didn't change
        assertEq(predictedToken, predictedTokenAfter, "Token prediction should not change after deployment");
        assertEq(predictedMetadata, predictedMetadataAfter, "Metadata prediction should not change after deployment");
        assertEq(predictedAuction, predictedAuctionAfter, "Auction prediction should not change after deployment");
        assertEq(predictedTreasury, predictedTreasuryAfter, "Treasury prediction should not change after deployment");
        assertEq(predictedGovernor, predictedGovernorAfter, "Governor prediction should not change after deployment");

        // Verify deployed addresses match predictions
        assertEq(token, predictedToken, "Deployed token should match prediction");
        assertEq(metadata, predictedMetadata, "Deployed metadata should match prediction");
        assertEq(auction, predictedAuction, "Deployed auction should match prediction");
        assertEq(treasury, predictedTreasury, "Deployed treasury should match prediction");
        assertEq(governor, predictedGovernor, "Deployed governor should match prediction");
    }

    function test_FundRecoveryScenario() public {
        // Simulates the fund recovery use case:
        // 1. Deploy DAO on Chain A
        // 2. Funds accidentally sent to predicted treasury on Chain B
        // 3. Deploy DAO on Chain B to recover funds

        setMockFounderParams();
        setMockTokenParams();
        setMockAuctionParams();
        setMockGovParams();

        address deployer = address(this);

        // Predict treasury address (same on both chains)
        (,,, address predictedTreasury,) = manager.predictDeterministicAddresses(deployer, DEFAULT_DEPLOY_SALT);

        // Simulate funds sent to predicted address "on Chain B" (before deployment)
        vm.deal(predictedTreasury, 10 ether);
        assertEq(predictedTreasury.balance, 10 ether);
        assertEq(predictedTreasury.code.length, 0, "Treasury not yet deployed");

        // Deploy DAO on "Chain B" using same parameters
        deployDeterministic(foundersArr, tokenParams, auctionParams, govParams, DEFAULT_DEPLOY_SALT);

        // Verify treasury deployed to predicted address
        assertEq(address(treasury), predictedTreasury, "Treasury deployed to predicted address");
        assertEq(predictedTreasury.code.length > 0, true, "Treasury now has code");
        assertEq(address(treasury).balance, 10 ether, "Treasury controls the funds");

        // DAO can now recover the funds through governance
        assertEq(treasury.owner(), address(governor), "Governor controls treasury");
    }
}
