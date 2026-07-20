// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import { Test } from "forge-std/Test.sol";
import { CREATE3Factory } from "create3-factory/CREATE3Factory.sol";

import { DAOFactory } from "../src/factory/DAOFactory.sol";
import { Manager } from "../src/manager/Manager.sol";
import { DeployConstants } from "../script/DeployConstants.sol";
import { DeployHelpers } from "../script/DeployHelpers.sol";
import { DeployV3New } from "../script/DeployV3New.s.sol";
import { MockProtocolRewards } from "./utils/mocks/MockProtocolRewards.sol";
import { WETH } from "./utils/mocks/WETH.sol";

contract DeployV3NewHarness is DeployV3New {
    function deployAllForTest(bytes32 deploySalt, address deployerAddress, address weth, address protocolRewards, address builderRewardsRecipient)
        external
        returns (DeploymentResult memory deployment)
    {
        return _deployAll(deploySalt, deployerAddress, weth, protocolRewards, builderRewardsRecipient);
    }
}

contract DeployV3NewTest is Test, DeployConstants {
    DeployV3NewHarness internal deployer;
    address internal weth;
    address internal protocolRewards;
    address internal builderRewardsRecipient;

    function setUp() public {
        CREATE3Factory factory = new CREATE3Factory();
        vm.etch(DeployHelpers.CREATE3_FACTORY, address(factory).code);

        deployer = new DeployV3NewHarness();
        weth = address(new WETH());
        protocolRewards = address(new MockProtocolRewards());
        builderRewardsRecipient = address(0xB01D3D);
    }

    function test_DeployV3NewFreshDeploymentBindsDAOFactoryToPredictedManagerProxy() public {
        bytes32 deploySalt = keccak256("DEPLOY_V3_NEW_UNIT_TEST");
        address broadcaster = address(deployer);

        address predictedManager = DeployHelpers.predictCreate3Address(_deriveSalt(deploySalt, MANAGER_PROXY_SALT), broadcaster);
        address predictedDAOFactory = DeployHelpers.predictCreate3Address(_deriveSalt(deploySalt, DAO_FACTORY_SALT), broadcaster);

        vm.prank(broadcaster);
        DeployV3New.DeploymentResult memory deployment =
            deployer.deployAllForTest(deploySalt, broadcaster, weth, protocolRewards, builderRewardsRecipient);

        assertEq(deployment.manager, predictedManager, "Manager proxy prediction mismatch");
        assertEq(deployment.daoFactory, predictedDAOFactory, "DAOFactory prediction mismatch");
        assertEq(DAOFactory(deployment.daoFactory).manager(), deployment.manager, "DAOFactory must bind to Manager proxy");
        assertEq(Manager(deployment.manager).daoFactory(), deployment.daoFactory, "Manager must reference DAOFactory");
        assertEq(Manager(deployment.manager).owner(), broadcaster, "Manager owner must be initialized atomically");

        assertGt(deployment.manager.code.length, 0, "Manager proxy not deployed");
        assertGt(deployment.daoFactory.code.length, 0, "DAOFactory not deployed");
        assertGt(deployment.tokenImpl.code.length, 0, "Token implementation not deployed");
        assertGt(deployment.metadataRendererImpl.code.length, 0, "Metadata implementation not deployed");
        assertGt(deployment.merklePropertyMetadataImpl.code.length, 0, "Merkle metadata implementation not deployed");
        assertGt(deployment.auctionImpl.code.length, 0, "Auction implementation not deployed");
        assertGt(deployment.treasuryImpl.code.length, 0, "Treasury implementation not deployed");
        assertGt(deployment.governorImpl.code.length, 0, "Governor implementation not deployed");
        assertGt(deployment.managerImpl.code.length, 0, "Manager implementation not deployed");
        assertGt(deployment.merkleMinter.code.length, 0, "Merkle minter not deployed");
        assertGt(deployment.redeemMinter.code.length, 0, "Redeem minter not deployed");
    }

    function test_AllContractsDeployedAtPredictedAddresses() public {
        bytes32 deploySalt = keccak256("ALL_CONTRACTS_PREDICTED_TEST");
        address broadcaster = address(deployer);

        // Predict all 11 contract addresses before deployment
        address predictedManagerProxy = DeployHelpers.predictCreate3Address(_deriveSalt(deploySalt, MANAGER_PROXY_SALT), broadcaster);
        address predictedDAOFactory = DeployHelpers.predictCreate3Address(_deriveSalt(deploySalt, DAO_FACTORY_SALT), broadcaster);
        address predictedTokenImpl = DeployHelpers.predictCreate3Address(_deriveSalt(deploySalt, TOKEN_IMPL_SALT), broadcaster);
        address predictedMetadataRendererImpl = DeployHelpers.predictCreate3Address(_deriveSalt(deploySalt, METADATA_RENDERER_IMPL_SALT), broadcaster);
        address predictedMerklePropertyMetadataImpl = DeployHelpers.predictCreate3Address(_deriveSalt(deploySalt, MERKLE_PROPERTY_IPFS_SALT), broadcaster);
        address predictedAuctionImpl = DeployHelpers.predictCreate3Address(_deriveSalt(deploySalt, AUCTION_IMPL_SALT), broadcaster);
        address predictedTreasuryImpl = DeployHelpers.predictCreate3Address(_deriveSalt(deploySalt, TREASURY_IMPL_SALT), broadcaster);
        address predictedGovernorImpl = DeployHelpers.predictCreate3Address(_deriveSalt(deploySalt, GOVERNOR_IMPL_SALT), broadcaster);
        address predictedManagerImpl = DeployHelpers.predictCreate3Address(_deriveSalt(deploySalt, MANAGER_IMPL_SALT), broadcaster);
        address predictedMerkleMinter = DeployHelpers.predictCreate3Address(_deriveSalt(deploySalt, MERKLE_RESERVE_MINTER_SALT), broadcaster);
        address predictedRedeemMinter = DeployHelpers.predictCreate3Address(_deriveSalt(deploySalt, ERC721_REDEEM_MINTER_SALT), broadcaster);

        // Deploy everything
        vm.prank(broadcaster);
        DeployV3New.DeploymentResult memory deployment =
            deployer.deployAllForTest(deploySalt, broadcaster, weth, protocolRewards, builderRewardsRecipient);

        // Verify ALL 11 contracts deployed at their exact predicted addresses
        assertEq(deployment.manager, predictedManagerProxy, "Manager proxy address mismatch");
        assertEq(deployment.daoFactory, predictedDAOFactory, "DAOFactory address mismatch");
        assertEq(deployment.tokenImpl, predictedTokenImpl, "Token implementation address mismatch");
        assertEq(deployment.metadataRendererImpl, predictedMetadataRendererImpl, "MetadataRenderer implementation address mismatch");
        assertEq(deployment.merklePropertyMetadataImpl, predictedMerklePropertyMetadataImpl, "MerklePropertyMetadata implementation address mismatch");
        assertEq(deployment.auctionImpl, predictedAuctionImpl, "Auction implementation address mismatch");
        assertEq(deployment.treasuryImpl, predictedTreasuryImpl, "Treasury implementation address mismatch");
        assertEq(deployment.governorImpl, predictedGovernorImpl, "Governor implementation address mismatch");
        assertEq(deployment.managerImpl, predictedManagerImpl, "Manager implementation address mismatch");
        assertEq(deployment.merkleMinter, predictedMerkleMinter, "Merkle minter address mismatch");
        assertEq(deployment.redeemMinter, predictedRedeemMinter, "Redeem minter address mismatch");
    }

    function test_DAOFactoryBoundToManagerProxy() public {
        bytes32 deploySalt = keccak256("DAO_FACTORY_BINDING_TEST");
        address broadcaster = address(deployer);

        // Predict Manager proxy address
        address predictedManagerProxy = DeployHelpers.predictCreate3Address(_deriveSalt(deploySalt, MANAGER_PROXY_SALT), broadcaster);

        // Deploy everything
        vm.prank(broadcaster);
        DeployV3New.DeploymentResult memory deployment =
            deployer.deployAllForTest(deploySalt, broadcaster, weth, protocolRewards, builderRewardsRecipient);

        // Verify DAOFactory is bound to the Manager proxy (not implementation)
        address boundManager = DAOFactory(deployment.daoFactory).manager();
        assertEq(boundManager, predictedManagerProxy, "DAOFactory should be bound to predicted Manager proxy address");
        assertEq(boundManager, deployment.manager, "DAOFactory should be bound to deployed Manager proxy address");

        // Verify the binding is to the proxy, not the implementation
        assertTrue(boundManager != deployment.managerImpl, "DAOFactory must bind to proxy, not implementation");
    }

    function test_ManagerImplReferencesAllImpls() public {
        bytes32 deploySalt = keccak256("MANAGER_IMPL_REFERENCES_TEST");
        address broadcaster = address(deployer);

        // Deploy everything
        vm.prank(broadcaster);
        DeployV3New.DeploymentResult memory deployment =
            deployer.deployAllForTest(deploySalt, broadcaster, weth, protocolRewards, builderRewardsRecipient);

        // Read Manager implementation's stored implementation addresses
        Manager managerImpl = Manager(deployment.managerImpl);

        // Verify they match the deployed implementation addresses
        assertEq(managerImpl.tokenImpl(), deployment.tokenImpl, "Manager implementation tokenImpl mismatch");
        assertEq(managerImpl.metadataImpl(), deployment.metadataRendererImpl, "Manager implementation metadataImpl mismatch");
        assertEq(managerImpl.auctionImpl(), deployment.auctionImpl, "Manager implementation auctionImpl mismatch");
        assertEq(managerImpl.treasuryImpl(), deployment.treasuryImpl, "Manager implementation treasuryImpl mismatch");
        assertEq(managerImpl.governorImpl(), deployment.governorImpl, "Manager implementation governorImpl mismatch");

        // Verify DAOFactory reference is correct
        assertEq(managerImpl.daoFactory(), deployment.daoFactory, "Manager implementation daoFactory reference mismatch");

        // Verify builderRewardsRecipient is set correctly
        assertEq(managerImpl.builderRewardsRecipient(), builderRewardsRecipient, "Manager implementation builderRewardsRecipient mismatch");
    }

    function test_SaltDerivationDeterministic() public {
        bytes32 deploySalt = keccak256("SALT_DERIVATION_TEST");

        // Call _deriveSalt multiple times with the same input
        bytes32 derivedSalt1 = _deriveSalt(deploySalt, TOKEN_IMPL_SALT);
        bytes32 derivedSalt2 = _deriveSalt(deploySalt, TOKEN_IMPL_SALT);
        bytes32 derivedSalt3 = _deriveSalt(deploySalt, TOKEN_IMPL_SALT);

        // Verify it returns the same salt each time
        assertEq(derivedSalt1, derivedSalt2, "Salt derivation should be deterministic (call 1 vs 2)");
        assertEq(derivedSalt2, derivedSalt3, "Salt derivation should be deterministic (call 2 vs 3)");
        assertEq(derivedSalt1, derivedSalt3, "Salt derivation should be deterministic (call 1 vs 3)");

        // Verify different salts are produced for different inputs
        bytes32 tokenSalt = _deriveSalt(deploySalt, TOKEN_IMPL_SALT);
        bytes32 auctionSalt = _deriveSalt(deploySalt, AUCTION_IMPL_SALT);
        bytes32 governorSalt = _deriveSalt(deploySalt, GOVERNOR_IMPL_SALT);

        // All three should be different from each other
        assertTrue(tokenSalt != auctionSalt, "Different labels should produce different salts (token vs auction)");
        assertTrue(tokenSalt != governorSalt, "Different labels should produce different salts (token vs governor)");
        assertTrue(auctionSalt != governorSalt, "Different labels should produce different salts (auction vs governor)");

        // Verify different deploySalt values produce different results
        bytes32 altDeploySalt = keccak256("DIFFERENT_DEPLOY_SALT");
        bytes32 altTokenSalt = _deriveSalt(altDeploySalt, TOKEN_IMPL_SALT);
        assertTrue(tokenSalt != altTokenSalt, "Different deploySalt values should produce different derived salts");
    }

    function testRevert_CannotReuseDeploySalt() public {
        bytes32 deploySalt = keccak256("SALT_REUSE_TEST");
        address broadcaster = address(deployer);

        // Run deployment with the salt
        vm.prank(broadcaster);
        deployer.deployAllForTest(deploySalt, broadcaster, weth, protocolRewards, builderRewardsRecipient);

        // Try to run deployment again with the SAME salt - should revert
        // CREATE3 prevents salt reuse because the proxy address would be the same
        vm.prank(broadcaster);
        vm.expectRevert();
        deployer.deployAllForTest(deploySalt, broadcaster, weth, protocolRewards, builderRewardsRecipient);
    }
}
