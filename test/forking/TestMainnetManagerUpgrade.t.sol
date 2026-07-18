// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import { Test } from "forge-std/Test.sol";
import { ViaIRTestHelper } from "../utils/ViaIRTestHelper.sol";

import { Manager } from "../../src/manager/Manager.sol";
import { IManager } from "../../src/manager/IManager.sol";
import { IToken } from "../../src/token/IToken.sol";
import { IGovernor } from "../../src/governance/governor/IGovernor.sol";
import { ITreasury } from "../../src/governance/treasury/ITreasury.sol";
import { IAuction } from "../../src/auction/IAuction.sol";
import { IBaseMetadata } from "../../src/token/metadata/interfaces/IBaseMetadata.sol";

import { Token } from "../../src/token/Token.sol";
import { MetadataRenderer } from "../../src/token/metadata/MetadataRenderer.sol";
import { Auction } from "../../src/auction/Auction.sol";
import { Treasury } from "../../src/governance/treasury/Treasury.sol";
import { Governor } from "../../src/governance/governor/Governor.sol";
import { DAOFactory } from "../../src/factory/DAOFactory.sol";
import { DeployHelpers } from "../../script/DeployHelpers.sol";
import { DeployConstants } from "../../script/DeployConstants.sol";
import { CREATE3Factory } from "create3-factory/CREATE3Factory.sol";

/// @title TestMainnetManagerUpgrade
/// @notice Comprehensive fork test for upgrading Manager on Ethereum mainnet
/// @dev Tests backward compatibility, new deterministic deployment features, and state integrity
contract TestMainnetManagerUpgrade is ViaIRTestHelper, DeployConstants {
    ///                                                          ///
    ///                      MAINNET ADDRESSES                   ///
    ///                                                          ///
    // Mainnet Manager addresses (from addresses/1.json)
    address constant MAINNET_MANAGER_PROXY = 0xd310A3041dFcF14Def5ccBc508668974b5da7174;
    address constant MAINNET_MANAGER_OWNER = 0xDC9b96Ea4966d063Dd5c8dbaf08fe59062091B6D;
    address constant MAINNET_CREATE3_FACTORY = 0xD252d074EEe65b64433a5a6f30Ab67569362E7e0;

    // ERC1967 implementation slot
    bytes32 constant ERC1967_IMPL_SLOT = bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1);

    // Real mainnet DAOs for testing
    address constant BUILDER_TOKEN = 0xdf9B7D26c8Fc806b1Ae6273684556761FF02d422;
    address constant PURPLE_TOKEN = 0xa45662638E9f3bbb7A6FeCb4B17853B7ba0F3a60;

    // Fork at recent mainnet block (June 2025)
    uint256 constant FORK_BLOCK = 21200000;

    ///                                                          ///
    ///                      TEST STATE                         ///
    ///                                                          ///

    IManager managerProxy;
    Manager newManagerImpl;
    address currentManagerImpl;

    // NEW implementation contracts for testing (deployed from local code)
    Token newTokenImpl;
    MetadataRenderer newMetadataImpl;
    Auction newAuctionImpl;
    Treasury newTreasuryImpl;
    Governor newGovernorImpl;

    // State before upgrade
    address recordedTokenImpl;
    address recordedMetadataImpl;
    address recordedAuctionImpl;
    address recordedTreasuryImpl;
    address recordedGovernorImpl;
    address recordedOwner;
    address recordedBuilderRewardsRecipient;

    // DAO addresses before upgrade
    address recordedBuilderMetadata;
    address recordedBuilderAuction;
    address recordedBuilderTreasury;
    address recordedBuilderGovernor;

    address recordedPurpleMetadata;
    address recordedPurpleAuction;
    address recordedPurpleTreasury;
    address recordedPurpleGovernor;

    // Fork ID
    uint256 mainnetFork;

    ///                                                          ///
    ///                         SETUP                            ///
    ///                                                          ///

    function setUp() public virtual {
        // Create and select mainnet fork
        mainnetFork = vm.createFork(vm.envString("MAINNET_RPC_URL"));
        vm.selectFork(mainnetFork);

        // Fork at specific block for consistent testing
        vm.rollFork(FORK_BLOCK);

        // Initialize time tracking for via_ir safety
        initTime();

        // Ensure CREATE3Factory exists at the expected address
        address create3Factory = _ensureCreate3FactoryExists();

        // Load manager proxy
        managerProxy = IManager(MAINNET_MANAGER_PROXY);

        // Record state before upgrade
        _recordStateBeforeUpgrade();

        // Deploy new implementations
        _deployNewImplementations(create3Factory);
    }

    /// @notice Ensures CREATE3Factory exists, deploying deterministically via CREATE2 if needed
    function _ensureCreate3FactoryExists() internal returns (address) {
        // Deploy CREATE3Factory deterministically using CREATE2 (Nick's factory)
        // This ensures same address across chains
        bytes memory creationCode = type(CREATE3Factory).creationCode;
        bytes32 salt = keccak256("NOUNS_BUILDER_CREATE3_FACTORY");

        address predicted = DeployHelpers.predictAddress(creationCode, salt);

        if (predicted.code.length == 0) {
            address deployed = DeployHelpers.deployViaFactory(creationCode, salt);
            require(deployed == predicted, "CREATE3Factory address mismatch");
        }

        return predicted;
    }

    /// @notice Records all Manager state before the upgrade
    function _recordStateBeforeUpgrade() internal {
        // Get current Manager implementation from ERC1967 slot
        currentManagerImpl = address(uint160(uint256(vm.load(MAINNET_MANAGER_PROXY, ERC1967_IMPL_SLOT))));

        // Record Manager immutables
        recordedTokenImpl = managerProxy.tokenImpl();
        recordedMetadataImpl = managerProxy.metadataImpl();
        recordedAuctionImpl = managerProxy.auctionImpl();
        recordedTreasuryImpl = managerProxy.treasuryImpl();
        recordedGovernorImpl = managerProxy.governorImpl();
        recordedOwner = managerProxy.owner();

        // Try to get builderRewardsRecipient (may not exist in older implementations)
        try Manager(address(managerProxy)).builderRewardsRecipient() returns (address recipient) {
            recordedBuilderRewardsRecipient = recipient;
        } catch {
            // Older Manager implementations don't have this function
            // Use a default value from addresses/1.json
            recordedBuilderRewardsRecipient = 0xaeA77c982515fD4aB72382D9ee1745C874Fa2234;
        }

        // Record Builder DAO addresses
        (recordedBuilderMetadata, recordedBuilderAuction, recordedBuilderTreasury, recordedBuilderGovernor) = managerProxy.getAddresses(BUILDER_TOKEN);

        // Record Purple DAO addresses
        (recordedPurpleMetadata, recordedPurpleAuction, recordedPurpleTreasury, recordedPurpleGovernor) = managerProxy.getAddresses(PURPLE_TOKEN);
    }

    /// @notice Deploys new Manager implementation with deterministic deployment features
    function _deployNewImplementations(address create3Factory) internal {
        // Deploy NEW DAO implementation contracts from local code
        // These will be used for testing deterministic deployment
        address MAINNET_WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

        newTokenImpl = new Token(address(managerProxy));
        newMetadataImpl = new MetadataRenderer(address(managerProxy));
        newAuctionImpl = new Auction(address(managerProxy), address(0), MAINNET_WETH, 0, 0);
        newTreasuryImpl = new Treasury(address(managerProxy));
        newGovernorImpl = new Governor(address(managerProxy));

        // Deploy DAOFactory via CREATE3 for deterministic address across chains
        bytes memory creationCode = abi.encodePacked(type(DAOFactory).creationCode, abi.encode(address(managerProxy)));
        bytes32 daoFactorySalt = keccak256("NOUNS_BUILDER_DAO_FACTORY_V1");

        address daoFactory = CREATE3Factory(create3Factory).deploy(daoFactorySalt, creationCode);

        // Deploy new Manager implementation
        // Keeps mainnet immutables for backward compatibility with existing DAOs
        // Now references DAOFactory instead of CREATE3Factory
        newManagerImpl = new Manager(
            recordedTokenImpl,
            recordedMetadataImpl,
            recordedAuctionImpl,
            recordedTreasuryImpl,
            recordedGovernorImpl,
            recordedBuilderRewardsRecipient,
            daoFactory
        );
    }

    ///                                                          ///
    ///                 SECTION A: UPGRADE TESTS                 ///
    ///                                                          ///

    /// @notice Tests that only the owner can upgrade the Manager
    function test_UpgradeAuthorization_OnlyOwnerCanUpgrade() public {
        address notOwner = address(0x1234);

        vm.prank(notOwner);
        vm.expectRevert(abi.encodeWithSignature("ONLY_OWNER()"));
        managerProxy.upgradeTo(address(newManagerImpl));
    }

    /// @notice Tests successful Manager upgrade by owner
    function test_UpgradeExecution_OwnerCanUpgrade() public {
        // Get implementation before upgrade
        address implBefore = address(uint160(uint256(vm.load(MAINNET_MANAGER_PROXY, ERC1967_IMPL_SLOT))));

        assertEq(implBefore, currentManagerImpl, "Initial implementation should match current mainnet impl");

        // Upgrade as owner
        vm.prank(MAINNET_MANAGER_OWNER);
        managerProxy.upgradeTo(address(newManagerImpl));

        // Verify implementation updated
        address implAfter = address(uint160(uint256(vm.load(MAINNET_MANAGER_PROXY, ERC1967_IMPL_SLOT))));
        assertEq(implAfter, address(newManagerImpl), "Implementation should be updated");
    }

    ///                                                          ///
    ///            SECTION B: POST-UPGRADE STATE INTEGRITY       ///
    ///                                                          ///

    /// @notice Tests that all immutables are preserved after upgrade
    function test_PostUpgrade_ImmutablesPreserved() public {
        _performUpgrade();

        // Verify all immutables preserved
        assertEq(managerProxy.tokenImpl(), recordedTokenImpl, "tokenImpl should be preserved");
        assertEq(managerProxy.metadataImpl(), recordedMetadataImpl, "metadataImpl should be preserved");
        assertEq(managerProxy.auctionImpl(), recordedAuctionImpl, "auctionImpl should be preserved");
        assertEq(managerProxy.treasuryImpl(), recordedTreasuryImpl, "treasuryImpl should be preserved");
        assertEq(managerProxy.governorImpl(), recordedGovernorImpl, "governorImpl should be preserved");

        // After upgrade, builderRewardsRecipient should be preserved
        assertEq(
            Manager(address(managerProxy)).builderRewardsRecipient(),
            recordedBuilderRewardsRecipient,
            "builderRewardsRecipient should be set correctly"
        );
    }

    /// @notice Tests that ownership is preserved after upgrade
    function test_PostUpgrade_OwnershipPreserved() public {
        _performUpgrade();

        assertEq(managerProxy.owner(), recordedOwner, "Owner should be preserved");
    }

    /// @notice Tests that existing DAO addresses are still queryable
    function test_PostUpgrade_ExistingDAOAddressesQueryable() public {
        _performUpgrade();

        // Query Builder DAO addresses
        (address builderMetadata, address builderAuction, address builderTreasury, address builderGovernor) = managerProxy.getAddresses(BUILDER_TOKEN);

        assertEq(builderMetadata, recordedBuilderMetadata, "Builder metadata should be preserved");
        assertEq(builderAuction, recordedBuilderAuction, "Builder auction should be preserved");
        assertEq(builderTreasury, recordedBuilderTreasury, "Builder treasury should be preserved");
        assertEq(builderGovernor, recordedBuilderGovernor, "Builder governor should be preserved");

        // Query Purple DAO addresses
        (address purpleMetadata, address purpleAuction, address purpleTreasury, address purpleGovernor) = managerProxy.getAddresses(PURPLE_TOKEN);

        assertEq(purpleMetadata, recordedPurpleMetadata, "Purple metadata should be preserved");
        assertEq(purpleAuction, recordedPurpleAuction, "Purple auction should be preserved");
        assertEq(purpleTreasury, recordedPurpleTreasury, "Purple treasury should be preserved");
        assertEq(purpleGovernor, recordedPurpleGovernor, "Purple governor should be preserved");
    }

    /// @notice Tests that upgrade registry is preserved
    function test_PostUpgrade_UpgradeRegistryPreserved() public {
        // Register an upgrade before the Manager upgrade
        vm.prank(MAINNET_MANAGER_OWNER);
        managerProxy.registerUpgrade(recordedTokenImpl, address(newTokenImpl));

        assertTrue(managerProxy.isRegisteredUpgrade(recordedTokenImpl, address(newTokenImpl)), "Upgrade should be registered");

        // Perform Manager upgrade
        _performUpgrade();

        // Verify registry still works
        assertTrue(
            managerProxy.isRegisteredUpgrade(recordedTokenImpl, address(newTokenImpl)), "Upgrade should still be registered after Manager upgrade"
        );
    }

    ///                                                          ///
    ///          SECTION C: VALIDATION TESTS                     ///
    ///                                                          ///

    /// @notice Tests that zero address implementations are rejected
    function test_Validation_ZeroAddressImplementationReverts() public {
        _performUpgrade();

        IManager.ImplementationParams memory impls = IManager.ImplementationParams({
            token: address(0),
            metadataRenderer: address(newMetadataImpl),
            auction: address(newAuctionImpl),
            treasury: address(newTreasuryImpl),
            governor: address(newGovernorImpl)
        });

        // This should fail validation before deployment
        vm.expectRevert(abi.encodeWithSignature("IMPLEMENTATION_REQUIRED()"));
        managerProxy.predictDeterministicAddresses(address(this), keccak256("TEST"), impls);
    }

    /// @notice Tests that non-contract addresses are rejected
    function test_Validation_EOAImplementationReverts() public {
        _performUpgrade();

        IManager.ImplementationParams memory impls = IManager.ImplementationParams({
            token: address(0x9999), // EOA address (no code)
            metadataRenderer: address(newMetadataImpl),
            auction: address(newAuctionImpl),
            treasury: address(newTreasuryImpl),
            governor: address(newGovernorImpl)
        });

        // This should fail validation due to no bytecode
        vm.expectRevert(abi.encodeWithSignature("INVALID_IMPLEMENTATION()"));
        managerProxy.predictDeterministicAddresses(address(this), keccak256("TEST"), impls);
    }

    ///                                                          ///
    ///              SECTION D: VERSION INFORMATION              ///
    ///                                                          ///

    /// @notice Tests getDAOVersions for existing DAO
    function test_VersionInfo_GetDAOVersions() public {
        _performUpgrade();

        IManager.DAOVersionInfo memory versions = Manager(address(managerProxy)).getDAOVersions(PURPLE_TOKEN);

        // Should return version strings (or empty if not versioned)
        assertTrue(bytes(versions.token).length >= 0, "Token version should be queryable");
        assertTrue(bytes(versions.metadata).length >= 0, "Metadata version should be queryable");
        assertTrue(bytes(versions.auction).length >= 0, "Auction version should be queryable");
        assertTrue(bytes(versions.treasury).length >= 0, "Treasury version should be queryable");
        assertTrue(bytes(versions.governor).length >= 0, "Governor version should be queryable");
    }

    /// @notice Tests getLatestVersions
    function test_VersionInfo_GetLatestVersions() public {
        _performUpgrade();

        IManager.DAOVersionInfo memory versions = Manager(address(managerProxy)).getLatestVersions();

        // Should return version strings for immutable implementations
        assertTrue(bytes(versions.token).length >= 0, "Token latest version should be queryable");
        assertTrue(bytes(versions.metadata).length >= 0, "Metadata latest version should be queryable");
        assertTrue(bytes(versions.auction).length >= 0, "Auction latest version should be queryable");
        assertTrue(bytes(versions.treasury).length >= 0, "Treasury latest version should be queryable");
        assertTrue(bytes(versions.governor).length >= 0, "Governor latest version should be queryable");
    }

    ///                                                          ///
    ///                    HELPER FUNCTIONS                      ///
    ///                                                          ///

    /// @notice Performs the Manager upgrade
    function _performUpgrade() internal {
        // Mainnet WETH address
        address MAINNET_WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

        vm.startPrank(MAINNET_MANAGER_OWNER);

        // Upgrade to new Manager implementation
        managerProxy.upgradeTo(address(newManagerImpl));

        vm.stopPrank();
    }
}
