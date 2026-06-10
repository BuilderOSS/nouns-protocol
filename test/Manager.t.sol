// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import { NounsBuilderTest } from "./utils/NounsBuilderTest.sol";

import { IManager, Manager } from "../src/manager/Manager.sol";

import { MockImpl } from "./utils/mocks/MockImpl.sol";
import { Token } from "../src/token/Token.sol";
import { Auction } from "../src/auction/Auction.sol";
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

    function test_DeployDeterministicMatchesPrediction() public {
        setMockFounderParams();
        setMockTokenParams();
        setMockAuctionParams();
        setMockGovParams();

        address deployer = address(this);
        IManager.ImplementationParams memory implementationParams = getImplementationParams();
        (address predictedToken, address predictedMetadata, address predictedAuction, address predictedTreasury, address predictedGovernor) =
            manager.predictDeterministicAddresses(deployer, DEFAULT_DEPLOY_SALT, implementationParams);

        deployDeterministic(foundersArr, tokenParams, auctionParams, govParams, DEFAULT_DEPLOY_SALT, implementationParams);

        assertEq(address(token), predictedToken);
        assertEq(address(metadataRenderer), predictedMetadata);
        assertEq(address(auction), predictedAuction);
        assertEq(address(treasury), predictedTreasury);
        assertEq(address(governor), predictedGovernor);
    }

    function test_PredictDeterministicAddressesChangesWithSalt() public {
        address deployer = address(this);
        IManager.ImplementationParams memory implementationParams = getImplementationParams();
        (address tokenA, address metadataA, address auctionA, address treasuryA, address governorA) =
            manager.predictDeterministicAddresses(deployer, DEFAULT_DEPLOY_SALT, implementationParams);
        (address tokenB, address metadataB, address auctionB, address treasuryB, address governorB) =
            manager.predictDeterministicAddresses(deployer, ALT_DEPLOY_SALT, implementationParams);

        assertTrue(tokenA != tokenB);
        assertTrue(metadataA != metadataB);
        assertTrue(auctionA != auctionB);
        assertTrue(treasuryA != treasuryB);
        assertTrue(governorA != governorB);
    }

    function test_PredictDeterministicAddressesChangesWithImplementationBundle() public {
        IManager.ImplementationParams memory defaultImplementationParams = getImplementationParams();
        IManager.ImplementationParams memory altImplementationParams = getImplementationParams();
        altImplementationParams.metadataRenderer = altMetadataImpl;

        (, address defaultMetadata,,,) = manager.predictDeterministicAddresses(address(this), DEFAULT_DEPLOY_SALT, defaultImplementationParams);
        (, address overrideMetadata,,,) = manager.predictDeterministicAddresses(address(this), DEFAULT_DEPLOY_SALT, altImplementationParams);

        assertTrue(defaultMetadata != overrideMetadata);
    }

    function test_PredictDeterministicAddressesChangesWithDeployer() public {
        address attacker = vm.addr(ATTACKER_PK);
        address victim = vm.addr(VICTIM_PK);
        IManager.ImplementationParams memory implementationParams = getImplementationParams();

        (address attackerToken, address attackerMetadata, address attackerAuction, address attackerTreasury, address attackerGovernor) =
            manager.predictDeterministicAddresses(attacker, DEFAULT_DEPLOY_SALT, implementationParams);
        (address victimToken, address victimMetadata, address victimAuction, address victimTreasury, address victimGovernor) =
            manager.predictDeterministicAddresses(victim, DEFAULT_DEPLOY_SALT, implementationParams);

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
        IManager.ImplementationParams memory implementationParams = getImplementationParams();

        (address attackerPredictedToken,,,,) = manager.predictDeterministicAddresses(attacker, DEFAULT_DEPLOY_SALT, implementationParams);
        (address victimPredictedToken, address victimPredictedMetadata, address victimPredictedAuction, address victimPredictedTreasury, address victimPredictedGovernor) =
            manager.predictDeterministicAddresses(victim, DEFAULT_DEPLOY_SALT, implementationParams);

        vm.prank(attacker);
        manager.deployDeterministic(foundersArr, tokenParams, auctionParams, govParams, DEFAULT_DEPLOY_SALT, implementationParams);

        (address attackerMetadata,,,) = manager.getAddresses(attackerPredictedToken);
        assertTrue(attackerMetadata != address(0));

        vm.prank(victim);
        (address victimToken, address victimMetadata, address victimAuction, address victimTreasury, address victimGovernor) =
            manager.deployDeterministic(foundersArr, tokenParams, auctionParams, govParams, DEFAULT_DEPLOY_SALT, implementationParams);

        assertEq(victimToken, victimPredictedToken);
        assertEq(victimMetadata, victimPredictedMetadata);
        assertEq(victimAuction, victimPredictedAuction);
        assertEq(victimTreasury, victimPredictedTreasury);
        assertEq(victimGovernor, victimPredictedGovernor);
        assertTrue(attackerPredictedToken != victimToken);
    }

    function test_PredictDeterministicAddressesChangesAcrossManagerUpgrade() public {
        address deployer = address(this);
        IManager.ImplementationParams memory implementationParams = getImplementationParams();
        (address tokenBefore, address metadataBefore, address auctionBefore, address treasuryBefore, address governorBefore) =
            manager.predictDeterministicAddresses(deployer, DEFAULT_DEPLOY_SALT, implementationParams);

        address newTokenImpl = address(new Token(address(manager)));
        address newMetadataImpl = address(new MetadataRenderer(address(manager)));
        address newAuctionImpl = address(new Auction(address(manager), address(rewards), weth, 1, 2));
        address newTreasuryImpl = address(new Treasury(address(manager)));
        address newGovernorImpl = address(new Governor(address(manager)));
        address newManagerImpl = address(new Manager(newTokenImpl, newMetadataImpl, newAuctionImpl, newTreasuryImpl, newGovernorImpl, zoraDAO));

        vm.prank(zoraDAO);
        manager.upgradeTo(newManagerImpl);

        IManager.ImplementationParams memory newImplementationParams = IManager.ImplementationParams({
            token: newTokenImpl,
            metadataRenderer: newMetadataImpl,
            auction: newAuctionImpl,
            treasury: newTreasuryImpl,
            governor: newGovernorImpl
        });

        (address tokenAfter, address metadataAfter, address auctionAfter, address treasuryAfter, address governorAfter) =
            manager.predictDeterministicAddresses(deployer, DEFAULT_DEPLOY_SALT, newImplementationParams);

        assertTrue(tokenBefore != tokenAfter);
        assertTrue(metadataBefore != metadataAfter);
        assertTrue(auctionBefore != auctionAfter);
        assertTrue(treasuryBefore != treasuryAfter);
        assertTrue(governorBefore != governorAfter);
    }

    function testRevert_DeployDeterministicWithUsedSalt() public {
        setMockFounderParams();
        setMockTokenParams();
        setMockAuctionParams();
        setMockGovParams();
        IManager.ImplementationParams memory implementationParams = getImplementationParams();

        deployDeterministic(foundersArr, tokenParams, auctionParams, govParams, DEFAULT_DEPLOY_SALT, implementationParams);

        vm.expectRevert();
        manager.deployDeterministic(foundersArr, tokenParams, auctionParams, govParams, DEFAULT_DEPLOY_SALT, implementationParams);
    }

    function testRevert_DeployDeterministicWithZeroImplementation() public {
        setMockFounderParams();
        setMockTokenParams();
        setMockAuctionParams();
        setMockGovParams();

        IManager.ImplementationParams memory implementationParams = getImplementationParams();
        implementationParams.metadataRenderer = address(0);

        vm.expectRevert(Manager.IMPLEMENTATION_REQUIRED.selector);
        manager.deployDeterministic(foundersArr, tokenParams, auctionParams, govParams, DEFAULT_DEPLOY_SALT, implementationParams);
    }

    function testRevert_PredictDeterministicAddressesWithZeroImplementation() public {
        IManager.ImplementationParams memory implementationParams = getImplementationParams();
        implementationParams.governor = address(0);

        vm.expectRevert(Manager.IMPLEMENTATION_REQUIRED.selector);
        manager.predictDeterministicAddresses(address(this), DEFAULT_DEPLOY_SALT, implementationParams);
    }
}
