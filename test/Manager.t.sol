// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { NounsBuilderTest } from "./utils/NounsBuilderTest.sol";

import { IManager, Manager } from "../src/manager/Manager.sol";

import { MockImpl } from "./utils/mocks/MockImpl.sol";
import { MetadataRenderer } from "../src/token/metadata/MetadataRenderer.sol";
import { BridgeTypes } from "../src/bridge/types/BridgeTypes.sol";
import { IOwnable } from "../src/lib/interfaces/IOwnable.sol";

contract ManagerTest is NounsBuilderTest {
    MockImpl internal mockImpl;
    address internal altMetadataImpl;

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

    function test_DeployBridgeInfrastructure() public {
        deployMock();

        IManager.BridgeDeployParams memory params = IManager.BridgeDeployParams({
            daoId: keccak256(abi.encode(address(token))),
            sourceTreasury: address(treasury),
            sourceChainId: block.chainid,
            destinationChainId: 8453,
            destinationEid: 30184,
            transportAdapterId: 1,
            layerZeroEndpoint: makeAddr("lzEndpoint"),
            bridgeOwner: manager.owner(),
            destinationManagedAdmin: makeAddr("managedAdmin"),
            destinationGuardian: makeAddr("guardian"),
            mode: BridgeTypes.BridgeMode.MANAGED,
            verificationThreshold: 1,
            modeChangeMinDelay: 1 days,
            modeChangeCooldown: 1 days
        });

        vm.prank(manager.owner());
        IManager.BridgeAddresses memory addresses = manager.deployBridgeInfrastructure(params);

        assertTrue(addresses.sourceBridgeAdapter != address(0));
        assertTrue(addresses.destinationExecutor != address(0));
        assertTrue(addresses.transportAdapter != address(0));
        assertTrue(addresses.safeWalletAdapter != address(0));
        assertTrue(addresses.verificationPolicy != address(0));

        assertEq(IOwnable(addresses.sourceBridgeAdapter).owner(), address(manager));
        assertEq(IOwnable(addresses.destinationExecutor).owner(), manager.owner());

        IManager.BridgeAddresses memory stored = manager.getBridgeAddresses(params.daoId, params.destinationChainId);
        assertEq(stored.sourceBridgeAdapter, addresses.sourceBridgeAdapter);
        assertEq(stored.destinationExecutor, addresses.destinationExecutor);
        assertEq(stored.transportAdapter, addresses.transportAdapter);
        assertEq(stored.safeWalletAdapter, addresses.safeWalletAdapter);
        assertEq(stored.verificationPolicy, addresses.verificationPolicy);

        assertEq(manager.getSourceBridgeAdapter(params.daoId), addresses.sourceBridgeAdapter);
    }

    function testRevert_OnlyOwnerCanDeployBridgeInfrastructure() public {
        deployMock();

        IManager.BridgeDeployParams memory params = IManager.BridgeDeployParams({
            daoId: keccak256("dao"),
            sourceTreasury: address(treasury),
            sourceChainId: block.chainid,
            destinationChainId: 10,
            destinationEid: 11111,
            transportAdapterId: 1,
            layerZeroEndpoint: makeAddr("lzEndpoint"),
            bridgeOwner: manager.owner(),
            destinationManagedAdmin: makeAddr("managedAdmin"),
            destinationGuardian: makeAddr("guardian"),
            mode: BridgeTypes.BridgeMode.MANAGED,
            verificationThreshold: 1,
            modeChangeMinDelay: 1 days,
            modeChangeCooldown: 1 days
        });

        vm.expectRevert(abi.encodeWithSignature("ONLY_OWNER()"));
        manager.deployBridgeInfrastructure(params);
    }

    function test_DeployBridgeInfrastructure_MultipleChainsReuseSourceAdapter() public {
        deployMock();

        bytes32 daoId = keccak256(abi.encode(address(token)));

        IManager.BridgeDeployParams memory params = IManager.BridgeDeployParams({
            daoId: daoId,
            sourceTreasury: address(treasury),
            sourceChainId: block.chainid,
            destinationChainId: 8453,
            destinationEid: 30184,
            transportAdapterId: 1,
            layerZeroEndpoint: makeAddr("lzEndpoint1"),
            bridgeOwner: manager.owner(),
            destinationManagedAdmin: makeAddr("managedAdmin1"),
            destinationGuardian: makeAddr("guardian1"),
            mode: BridgeTypes.BridgeMode.MANAGED,
            verificationThreshold: 1,
            modeChangeMinDelay: 1 days,
            modeChangeCooldown: 1 days
        });

        vm.prank(manager.owner());
        IManager.BridgeAddresses memory first = manager.deployBridgeInfrastructure(params);

        params.destinationChainId = 10;
        params.destinationEid = 30111;
        params.layerZeroEndpoint = makeAddr("lzEndpoint2");
        params.destinationManagedAdmin = makeAddr("managedAdmin2");
        params.destinationGuardian = makeAddr("guardian2");

        vm.prank(manager.owner());
        IManager.BridgeAddresses memory second = manager.deployBridgeInfrastructure(params);

        assertEq(first.sourceBridgeAdapter, second.sourceBridgeAdapter);
        assertTrue(first.destinationExecutor != second.destinationExecutor);
        assertTrue(first.transportAdapter != second.transportAdapter);
    }
}
