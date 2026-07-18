// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import { Test } from "forge-std/Test.sol";
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
    bytes32 constant DAO_FACTORY_SALT = keccak256("NOUNS_BUILDER_DAO_FACTORY_V1");

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
        initTime();
        address mainnetCreate3Factory = _ensureCreate3FactoryExists();
        _setupMainnet(mainnetCreate3Factory);

        // Setup optimism
        vm.selectFork(optimismFork);
        initTime();
        address optimismCreate3Factory = _ensureCreate3FactoryExists();
        _setupOptimism(optimismCreate3Factory);
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
            address(0xaeA77c982515fD4aB72382D9ee1745C874Fa2234) // Builder rewards recipient from addresses/1.json
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
            address(0xaeA77c982515fD4aB72382D9ee1745C874Fa2234) // Same builder rewards recipient
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

    /// @notice Deploy new Manager implementation with DAOFactory support
    /// @param currentManager The current Manager proxy (to read existing immutables)
    /// @param daoFactory The DAOFactory address to reference
    /// @param builderRewardsRecipient The builder rewards recipient address
    /// @return impl The deployed Manager implementation
    function _deployManagerImpl(IManager currentManager, address daoFactory, address builderRewardsRecipient)
        internal
        returns (Manager impl)
    {
        // Get current implementation addresses (for backward compatibility)
        address tokenImpl = currentManager.tokenImpl();
        address metadataImpl = currentManager.metadataImpl();
        address auctionImpl = currentManager.auctionImpl();
        address treasuryImpl = currentManager.treasuryImpl();
        address governorImpl = currentManager.governorImpl();

        // Deploy new Manager implementation with all immutables
        impl = new Manager(
            tokenImpl, metadataImpl, auctionImpl, treasuryImpl, governorImpl, builderRewardsRecipient, daoFactory
        );
    }

    ///                                                          ///
    ///                          TESTS                           ///
    ///                                                          ///

    /// @notice Verify DAOFactory addresses match across chains
    function test_DAOFactoryDeterministicAcrossChains() public {
        // DAOFactory should be at the SAME address on both chains
        // This is critical for cross-chain determinism
        assertEq(
            mainnetDaoFactory, optimismDaoFactory, "DAOFactory addresses must match - this is the foundation of cross-chain determinism"
        );

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

        // Deploy NEW implementations for testing (can be different on each chain - doesn't matter!)
        vm.selectFork(mainnetFork);
        address mainnetTokenImpl = address(new Token(address(mainnetManager)));
        address mainnetMetadataImpl = address(new MetadataRenderer(address(mainnetManager)));
        address mainnetAuctionImpl = address(new Auction(address(mainnetManager), address(0), MAINNET_WETH, 0, 0));
        address mainnetTreasuryImpl = address(new Treasury(address(mainnetManager)));
        address mainnetGovernorImpl = address(new Governor(address(mainnetManager)));

        vm.selectFork(optimismFork);
        address optimismTokenImpl = address(new Token(address(optimismManager)));
        address optimismMetadataImpl = address(new MetadataRenderer(address(optimismManager)));
        address optimismAuctionImpl = address(new Auction(address(optimismManager), address(0), OPTIMISM_WETH, 0, 0));
        address optimismTreasuryImpl = address(new Treasury(address(optimismManager)));
        address optimismGovernorImpl = address(new Governor(address(optimismManager)));

        // Implementation addresses are DIFFERENT (as expected)
        assertTrue(mainnetTokenImpl != optimismTokenImpl, "Implementation addresses differ between chains");

        // Create implementation params for mainnet
        IManager.ImplementationParams memory mainnetParams = IManager.ImplementationParams({
            token: mainnetTokenImpl,
            metadataRenderer: mainnetMetadataImpl,
            auction: mainnetAuctionImpl,
            treasury: mainnetTreasuryImpl,
            governor: mainnetGovernorImpl
        });

        // Create implementation params for optimism
        IManager.ImplementationParams memory optimismParams = IManager.ImplementationParams({
            token: optimismTokenImpl,
            metadataRenderer: optimismMetadataImpl,
            auction: optimismAuctionImpl,
            treasury: optimismTreasuryImpl,
            governor: optimismGovernorImpl
        });

        // Predict addresses on MAINNET
        vm.selectFork(mainnetFork);
        (address mainnetToken, address mainnetMetadata, address mainnetAuction, address mainnetTreasury, address mainnetGovernor) =
            mainnetManager.predictDeterministicAddresses(deployer, salt, mainnetParams);

        // Predict addresses on OPTIMISM
        vm.selectFork(optimismFork);
        (address optimismToken, address optimismMetadata, address optimismAuction, address optimismTreasury, address optimismGovernor) =
            optimismManager.predictDeterministicAddresses(deployer, salt, optimismParams);

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

    /// @notice Verify predictions are bytecode-independent (CREATE3 property)
    function test_PredictionsBytecodeIndependent() public {
        address deployer = address(0xABCDEF);
        bytes32 salt = keccak256("BYTECODE_INDEPENDENCE_TEST");

        // Select mainnet fork
        vm.selectFork(mainnetFork);

        // Deploy two DIFFERENT sets of implementations
        address tokenImpl1 = address(new Token(address(mainnetManager)));
        address metadataImpl1 = address(new MetadataRenderer(address(mainnetManager)));
        address auctionImpl1 = address(new Auction(address(mainnetManager), address(0), MAINNET_WETH, 0, 0));
        address treasuryImpl1 = address(new Treasury(address(mainnetManager)));
        address governorImpl1 = address(new Governor(address(mainnetManager)));

        address tokenImpl2 = address(new Token(address(mainnetManager)));
        address metadataImpl2 = address(new MetadataRenderer(address(mainnetManager)));
        address auctionImpl2 = address(new Auction(address(mainnetManager), address(0), MAINNET_WETH, 1, 2)); // Different constructor params!
        address treasuryImpl2 = address(new Treasury(address(mainnetManager)));
        address governorImpl2 = address(new Governor(address(mainnetManager)));

        // Implementations are DIFFERENT
        assertTrue(auctionImpl1 != auctionImpl2, "Auction implementations should differ");

        // Create params with different implementations
        IManager.ImplementationParams memory params1 =
            IManager.ImplementationParams({ token: tokenImpl1, metadataRenderer: metadataImpl1, auction: auctionImpl1, treasury: treasuryImpl1, governor: governorImpl1 });

        IManager.ImplementationParams memory params2 =
            IManager.ImplementationParams({ token: tokenImpl2, metadataRenderer: metadataImpl2, auction: auctionImpl2, treasury: treasuryImpl2, governor: governorImpl2 });

        // Predict with BOTH sets of implementations
        (address token1, address metadata1, address auction1, address treasury1, address governor1) =
            mainnetManager.predictDeterministicAddresses(deployer, salt, params1);

        (address token2, address metadata2, address auction2, address treasury2, address governor2) =
            mainnetManager.predictDeterministicAddresses(deployer, salt, params2);

        // Predictions MUST be IDENTICAL (CREATE3 is bytecode-independent)
        assertEq(token1, token2, "Predictions must be bytecode-independent");
        assertEq(metadata1, metadata2, "Predictions must be bytecode-independent");
        assertEq(auction1, auction2, "Predictions must be bytecode-independent");
        assertEq(treasury1, treasury2, "Predictions must be bytecode-independent");
        assertEq(governor1, governor2, "Predictions must be bytecode-independent");
    }

    /// @notice Integration test: Actually deploy a DAO and verify addresses match predictions
    function test_ActualDeploymentMatchesPrediction() public {
        // Use mainnet fork for actual deployment
        vm.selectFork(mainnetFork);

        address deployer = address(this);
        bytes32 salt = keccak256("ACTUAL_DEPLOYMENT_TEST");

        // Deploy implementations
        address tokenImpl = address(new Token(address(mainnetManager)));
        address metadataImpl = address(new MetadataRenderer(address(mainnetManager)));
        address auctionImpl = address(new Auction(address(mainnetManager), address(0), MAINNET_WETH, 0, 0));
        address treasuryImpl = address(new Treasury(address(mainnetManager)));
        address governorImpl = address(new Governor(address(mainnetManager)));

        IManager.ImplementationParams memory params =
            IManager.ImplementationParams({ token: tokenImpl, metadataRenderer: metadataImpl, auction: auctionImpl, treasury: treasuryImpl, governor: governorImpl });

        // Predict addresses BEFORE deployment
        (address predictedToken, address predictedMetadata, address predictedAuction, address predictedTreasury, address predictedGovernor) =
            mainnetManager.predictDeterministicAddresses(deployer, salt, params);

        // Setup minimal DAO params
        IManager.FounderParams[] memory founders = new IManager.FounderParams[](0);

        IManager.TokenParams memory tokenParams = IManager.TokenParams({
            initStrings: abi.encode("Test DAO", "TEST", "Test Description", "ipfs://test", "https://test.com", "https://renderer.test"),
            metadataRenderer: address(0),
            reservedUntilTokenId: 0
        });

        IManager.AuctionParams memory auctionParams = IManager.AuctionParams({ reservePrice: 0.01 ether, duration: 1 days, founderRewardRecipent: address(0), founderRewardBps: 0 });

        IManager.GovParams memory govParams = IManager.GovParams({ timelockDelay: 2 days, votingDelay: 1 seconds, votingPeriod: 1 weeks, proposalThresholdBps: 50, quorumThresholdBps: 1000, vetoer: address(0) });

        // Actually deploy the DAO deterministically
        (address deployedToken, address deployedMetadata, address deployedAuction, address deployedTreasury, address deployedGovernor) =
            mainnetManager.deployDeterministic(founders, tokenParams, auctionParams, govParams, salt, params);

        // Verify deployed addresses MATCH predictions EXACTLY
        assertEq(deployedToken, predictedToken, "Deployed Token must match prediction");
        assertEq(deployedMetadata, predictedMetadata, "Deployed Metadata must match prediction");
        assertEq(deployedAuction, predictedAuction, "Deployed Auction must match prediction");
        assertEq(deployedTreasury, predictedTreasury, "Deployed Treasury must match prediction");
        assertEq(deployedGovernor, predictedGovernor, "Deployed Governor must match prediction");
    }
}
