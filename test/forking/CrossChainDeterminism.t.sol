// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import { ViaIRTestHelper } from "../utils/ViaIRTestHelper.sol";

import { Manager } from "../../src/manager/Manager.sol";
import { IManager } from "../../src/manager/IManager.sol";
import { DAOFactory } from "../../src/factory/DAOFactory.sol";
import { CREATE3Factory } from "create3-factory/CREATE3Factory.sol";
import { DeployHelpers } from "../../script/DeployHelpers.sol";

import { Token } from "../../src/token/Token.sol";
import { MetadataRenderer } from "../../src/token/metadata/MetadataRenderer.sol";
import { Auction } from "../../src/auction/Auction.sol";
import { Treasury } from "../../src/governance/treasury/Treasury.sol";
import { Governor } from "../../src/governance/governor/Governor.sol";

/// @title CrossChainDeterminism
/// @notice Production-realistic fork test validating cross-chain deterministic DAO deployments
/// @dev This test uses ACTUAL production Manager addresses from mainnet and Optimism to prove
///      that despite different Manager addresses on different chains, DAOFactory enables
///      identical DAO addresses when using the same deployment parameters.
///
///      Test Flow:
///      1. Fork mainnet and Optimism at recent blocks
///      2. Load production Managers at their actual addresses
///      3. Deploy DAOFactory at deterministic address on BOTH chains (using CREATE3)
///      4. Upgrade both Managers to support DAOFactory
///      5. Predict DAO addresses using same parameters on both chains
///      6. Assert predictions are IDENTICAL despite different Manager addresses
///
///      This validates the entire architectural rationale for DAOFactory!
contract CrossChainDeterminism is ViaIRTestHelper {
    ///                                                          ///
    ///                    PRODUCTION ADDRESSES                  ///
    ///                                                          ///
    // Mainnet (Chain ID 1)
    address constant MAINNET_MANAGER_PROXY = 0xd310A3041dFcF14Def5ccBc508668974b5da7174;
    address constant MAINNET_MANAGER_OWNER = 0xDC9b96Ea4966d063Dd5c8dbaf08fe59062091B6D;
    address constant MAINNET_CREATE3_FACTORY = 0xD252d074EEe65b64433a5a6f30Ab67569362E7e0;
    address constant MAINNET_WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    // Optimism (Chain ID 10)
    address constant OPTIMISM_MANAGER_PROXY = 0x3ac0E64Fe2931f8e082C6Bb29283540DE9b5371C;
    address constant OPTIMISM_MANAGER_OWNER = 0x11Fd15eC87391c8d502b889E60f3130C156F93c8;
    address constant OPTIMISM_CREATE3_FACTORY = 0xD252d074EEe65b64433a5a6f30Ab67569362E7e0;
    address constant OPTIMISM_WETH = 0x4200000000000000000000000000000000000006;

    // ERC1967 implementation slot
    bytes32 constant ERC1967_IMPL_SLOT = bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1);

    // Deterministic DAOFactory salt (same on both chains for same address)
    bytes32 constant DAO_FACTORY_SALT = keccak256("DAO_FACTORY");

    // Fork at specific blocks for consistent testing (June 2025)
    uint256 constant MAINNET_FORK_BLOCK = 21200000;
    uint256 constant OPTIMISM_FORK_BLOCK = 125000000;

    ///                                                          ///
    ///                        FORK STATE                        ///
    ///                                                          ///

    uint256 mainnetFork;
    uint256 optimismFork;

    IManager mainnetManager;
    IManager optimismManager;

    address mainnetDaoFactory;
    address optimismDaoFactory;

    Manager mainnetManagerImpl;
    Manager optimismManagerImpl;

    ///                                                          ///
    ///                          SETUP                           ///
    ///                                                          ///

    function setUp() public {
        // Create forks
        mainnetFork = vm.createFork(vm.envString("MAINNET_RPC_URL"));
        optimismFork = vm.createFork(vm.envString("OPTIMISM_RPC_URL"));

        // Setup mainnet
        vm.selectFork(mainnetFork);
        vm.rollFork(MAINNET_FORK_BLOCK);
        initTime();
        address mainnetCreate3Factory = _ensureCreate3FactoryExists();
        _setupMainnet(mainnetCreate3Factory);

        // Setup optimism
        vm.selectFork(optimismFork);
        vm.rollFork(OPTIMISM_FORK_BLOCK);
        initTime();
        address optimismCreate3Factory = _ensureCreate3FactoryExists();
        _setupOptimism(optimismCreate3Factory);
    }

    /// @notice Ensures CREATE3Factory exists, deploying deterministically via CREATE2 if needed
    function _ensureCreate3FactoryExists() internal returns (address) {
        // Use the hardcoded CREATE3_FACTORY address from DeployHelpers
        // The factory is assumed to exist at this address across chains
        address factory = DeployHelpers.CREATE3_FACTORY;

        // If it doesn't exist in the fork, deploy it directly
        if (factory.code.length == 0) {
            CREATE3Factory deployed = new CREATE3Factory();
            vm.etch(factory, address(deployed).code);
        }

        return factory;
    }

    /// @notice Setup mainnet fork: deploy DAOFactory, upgrade Manager
    function _setupMainnet(address create3Factory) internal {
        // Load production Manager
        mainnetManager = IManager(MAINNET_MANAGER_PROXY);

        // Deploy DAOFactory at deterministic address
        mainnetDaoFactory = _deployDAOFactory(create3Factory, MAINNET_MANAGER_PROXY);

        // Deploy new Manager implementation with DAOFactory support
        mainnetManagerImpl = _deployManagerImpl(
            mainnetManager,
            mainnetDaoFactory,
            address(0xaeA77c982515fD4aB72382D9ee1745C874Fa2234), // Builder rewards recipient from addresses/1.json
            MAINNET_WETH
        );

        // Upgrade Manager to new implementation using startPrank to maintain owner context
        vm.startPrank(MAINNET_MANAGER_OWNER);
        mainnetManager.upgradeTo(address(mainnetManagerImpl));
        vm.stopPrank();

        // Verify upgrade succeeded
        address newImpl = address(uint160(uint256(vm.load(MAINNET_MANAGER_PROXY, ERC1967_IMPL_SLOT))));
        require(newImpl == address(mainnetManagerImpl), "Mainnet Manager upgrade failed");
    }

    /// @notice Setup Optimism fork: deploy DAOFactory, upgrade Manager
    function _setupOptimism(address create3Factory) internal {
        // Load production Manager
        optimismManager = IManager(OPTIMISM_MANAGER_PROXY);

        // Deploy DAOFactory at deterministic address (SAME as mainnet)
        optimismDaoFactory = _deployDAOFactory(create3Factory, OPTIMISM_MANAGER_PROXY);

        // Deploy new Manager implementation with DAOFactory support
        optimismManagerImpl = _deployManagerImpl(
            optimismManager,
            optimismDaoFactory,
            address(0xaeA77c982515fD4aB72382D9ee1745C874Fa2234), // Same builder rewards recipient
            OPTIMISM_WETH
        );

        // Upgrade Manager to new implementation using startPrank to maintain owner context
        vm.startPrank(OPTIMISM_MANAGER_OWNER);
        optimismManager.upgradeTo(address(optimismManagerImpl));
        vm.stopPrank();

        // Verify upgrade succeeded
        address newImpl = address(uint160(uint256(vm.load(OPTIMISM_MANAGER_PROXY, ERC1967_IMPL_SLOT))));
        require(newImpl == address(optimismManagerImpl), "Optimism Manager upgrade failed");
    }

    ///                                                          ///
    ///                     DEPLOYMENT HELPERS                   ///
    ///                                                          ///

    /// @notice Deploy DAOFactory at deterministic address using CREATE3
    /// @param create3Factory The CREATE3Factory address (same on both chains)
    /// @param manager The Manager proxy address that will be authorized
    /// @return daoFactory The deployed DAOFactory address
    function _deployDAOFactory(address create3Factory, address manager) internal returns (address daoFactory) {
        bytes memory creationCode = abi.encodePacked(type(DAOFactory).creationCode, abi.encode(manager));

        daoFactory = CREATE3Factory(create3Factory).deploy(DAO_FACTORY_SALT, creationCode);

        // Verify DAOFactory was deployed correctly
        require(daoFactory != address(0), "DAOFactory deployment failed");
        require(DAOFactory(daoFactory).manager() == manager, "DAOFactory manager mismatch");
    }

    /// @notice Deploy new Manager implementation with DAOFactory support and NEW implementations
    /// @param managerProxy The Manager proxy address (used as manager reference for new implementations)
    /// @param daoFactory The DAOFactory address to reference
    /// @param builderRewardsRecipient The builder rewards recipient address
    /// @param weth The WETH address for the chain
    /// @return impl The deployed Manager implementation
    function _deployManagerImpl(IManager managerProxy, address daoFactory, address builderRewardsRecipient, address weth)
        internal
        returns (Manager impl)
    {
        // Deploy NEW implementations with updated initialize() signatures
        address tokenImpl = address(new Token(address(managerProxy)));
        address metadataImpl = address(new MetadataRenderer(address(managerProxy)));
        address auctionImpl = address(new Auction(address(managerProxy), address(0), weth, 0, 0));
        address treasuryImpl = address(new Treasury(address(managerProxy)));
        address governorImpl = address(new Governor(address(managerProxy)));

        // Deploy new Manager implementation with all immutables
        impl = new Manager(tokenImpl, metadataImpl, auctionImpl, treasuryImpl, governorImpl, builderRewardsRecipient, daoFactory);
    }

    ///                                                          ///
    ///                          TESTS                           ///
    ///                                                          ///

    /// @notice Verify DAOFactory addresses match across chains
    function test_DAOFactoryDeterministicAcrossChains() public {
        // DAOFactory should be at the SAME address on both chains
        // This is critical for cross-chain determinism
        assertEq(mainnetDaoFactory, optimismDaoFactory, "DAOFactory addresses must match - this is the foundation of cross-chain determinism");

        // Log the addresses for visibility
        emit log_named_address("DAOFactory address (both chains)", mainnetDaoFactory);
    }

    /// @notice Verify Manager addresses are DIFFERENT across chains (production reality)
    function test_ManagerAddressesDifferAcrossChains() public {
        // Managers are at DIFFERENT addresses in production
        // This is why we need DAOFactory!
        assertTrue(address(mainnetManager) != address(optimismManager), "Manager addresses differ in production");

        emit log_named_address("Mainnet Manager", address(mainnetManager));
        emit log_named_address("Optimism Manager", address(optimismManager));
    }

    /// @notice Core test: DAO predictions match across chains despite different Manager addresses
    function test_CrossChainPredictionDeterminism() public {
        // Setup test parameters (same on both chains)
        address deployer = address(0x1234567890123456789012345678901234567890);
        bytes32 salt = keccak256("CROSS_CHAIN_DAO_V1");

        // Predict addresses on MAINNET
        vm.selectFork(mainnetFork);
        (address mainnetToken, address mainnetMetadata, address mainnetAuction, address mainnetTreasury, address mainnetGovernor) =
            mainnetManager.predictDeterministicAddresses(deployer, salt);

        // Predict addresses on OPTIMISM
        vm.selectFork(optimismFork);
        (address optimismToken, address optimismMetadata, address optimismAuction, address optimismTreasury, address optimismGovernor) =
            optimismManager.predictDeterministicAddresses(deployer, salt);

        // ========== CRITICAL ASSERTIONS: Predictions MUST match ==========
        // Despite:
        // - Different Manager addresses
        // - Different implementation addresses
        // - Different chains
        // The predicted DAO addresses MUST be IDENTICAL because DAOFactory is at the same address!

        assertEq(mainnetToken, optimismToken, "Token addresses must match across chains");
        assertEq(mainnetMetadata, optimismMetadata, "Metadata addresses must match across chains");
        assertEq(mainnetAuction, optimismAuction, "Auction addresses must match across chains");
        assertEq(mainnetTreasury, optimismTreasury, "Treasury addresses must match across chains");
        assertEq(mainnetGovernor, optimismGovernor, "Governor addresses must match across chains");

        // Log predicted addresses for visibility
        emit log_named_address("Predicted Token (both chains)", mainnetToken);
        emit log_named_address("Predicted Metadata (both chains)", mainnetMetadata);
        emit log_named_address("Predicted Auction (both chains)", mainnetAuction);
        emit log_named_address("Predicted Treasury (both chains)", mainnetTreasury);
        emit log_named_address("Predicted Governor (both chains)", mainnetGovernor);
    }

    /// @notice Integration test: Actually deploy a DAO and verify addresses match predictions
    function test_ActualDeploymentMatchesPrediction() public {
        // Use mainnet fork for actual deployment
        vm.selectFork(mainnetFork);

        address deployer = address(this);
        bytes32 salt = keccak256("ACTUAL_DEPLOYMENT_TEST");

        // Predict addresses BEFORE deployment (uses Manager's immutable implementations)
        (address predictedToken, address predictedMetadata, address predictedAuction, address predictedTreasury, address predictedGovernor) =
            mainnetManager.predictDeterministicAddresses(deployer, salt);

        // Setup minimal DAO params with one founder
        IManager.FounderParams[] memory founders = new IManager.FounderParams[](1);
        founders[0] = IManager.FounderParams({ wallet: address(this), ownershipPct: 10, vestExpiry: 4 weeks });

        IManager.TokenParams memory tokenParams = IManager.TokenParams({
            initStrings: abi.encode("Test DAO", "TEST", "Test Description", "ipfs://test", "https://test.com", "https://renderer.test"),
            metadataRenderer: address(0),
            reservedUntilTokenId: 0
        });

        IManager.AuctionParams memory auctionParams =
            IManager.AuctionParams({ reservePrice: 0.01 ether, duration: 1 days, founderRewardRecipent: address(0), founderRewardBps: 0 });

        IManager.GovParams memory govParams = IManager.GovParams({
            timelockDelay: 2 days,
            votingDelay: 1 seconds,
            votingPeriod: 1 weeks,
            proposalThresholdBps: 50,
            quorumThresholdBps: 1000,
            vetoer: address(0),
            proposalUpdatablePeriod: 1 days
        });

        // Actually deploy the DAO deterministically
        (address deployedToken, address deployedMetadata, address deployedAuction, address deployedTreasury, address deployedGovernor) =
            mainnetManager.deployDeterministic(founders, tokenParams, auctionParams, govParams, salt);

        // Verify deployed addresses MATCH predictions EXACTLY
        assertEq(deployedToken, predictedToken, "Deployed Token must match prediction");
        assertEq(deployedMetadata, predictedMetadata, "Deployed Metadata must match prediction");
        assertEq(deployedAuction, predictedAuction, "Deployed Auction must match prediction");
        assertEq(deployedTreasury, predictedTreasury, "Deployed Treasury must match prediction");
        assertEq(deployedGovernor, predictedGovernor, "Deployed Governor must match prediction");
    }
}
