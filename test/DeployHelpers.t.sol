// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import { Test } from "forge-std/Test.sol";
import { CREATE3Factory } from "create3-factory/CREATE3Factory.sol";

import { DeployHelpers } from "../script/DeployHelpers.sol";

contract DeployHelpersTest is Test {
    function setUp() public {
        CREATE3Factory factory = new CREATE3Factory();
        vm.etch(DeployHelpers.CREATE3_FACTORY, address(factory).code);
    }

    function test_PredictCreate3AddressMatchesFactory() public {
        address deployer = address(0x1234);
        bytes32 salt = keccak256("CREATE3_PREDICTION_TEST");

        address factoryPrediction = CREATE3Factory(DeployHelpers.CREATE3_FACTORY).getDeployed(deployer, salt);
        address helperPrediction = DeployHelpers.predictCreate3Address(salt, deployer);

        assertEq(helperPrediction, factoryPrediction, "helper prediction must match factory");
    }

    function test_PredictCreate3AddressChangesWithDeployer() public {
        bytes32 salt = keccak256("CREATE3_DEPLOYER_NAMESPACE_TEST");

        address deployerA = address(0xA11CE);
        address deployerB = address(0xB0B);

        assertTrue(
            DeployHelpers.predictCreate3Address(salt, deployerA) != DeployHelpers.predictCreate3Address(salt, deployerB),
            "different deployers must have different CREATE3 namespaces"
        );
    }

    function test_PredictCreate3AddressChangesWithSalt() public {
        address deployer = address(0xA11CE);

        assertTrue(
            DeployHelpers.predictCreate3Address(keccak256("SALT_A"), deployer) != DeployHelpers.predictCreate3Address(keccak256("SALT_B"), deployer),
            "different salts must produce different addresses"
        );
    }

    function test_Create3DeploymentMatchesPrediction() public {
        address deployer = address(this);
        bytes32 salt = keccak256("ACTUAL_DEPLOYMENT_TEST");

        // Predict the address
        address predicted = DeployHelpers.predictCreate3Address(salt, deployer);

        // Deploy a simple contract using CREATE3
        bytes memory creationCode = type(MockContract).creationCode;
        address deployed = CREATE3Factory(DeployHelpers.CREATE3_FACTORY).deploy(salt, creationCode);

        assertEq(deployed, predicted, "actual deployment must match prediction");

        // Verify contract was actually deployed
        assertTrue(deployed.code.length > 0, "contract must have bytecode");
    }

    function test_Create3RevertOnSaltReuse() public {
        bytes32 salt = keccak256("SALT_REUSE_TEST");

        // First deployment should succeed
        bytes memory creationCode = type(MockContract).creationCode;
        CREATE3Factory(DeployHelpers.CREATE3_FACTORY).deploy(salt, creationCode);

        // Second deployment with same salt should revert
        vm.expectRevert();
        CREATE3Factory(DeployHelpers.CREATE3_FACTORY).deploy(salt, creationCode);
    }

    function test_Create3PredictionStableBeforeDeployment() public {
        address deployer = address(0xABCD);
        bytes32 salt = keccak256("STABILITY_TEST");

        // Call prediction multiple times
        address prediction1 = DeployHelpers.predictCreate3Address(salt, deployer);
        address prediction2 = DeployHelpers.predictCreate3Address(salt, deployer);
        address prediction3 = DeployHelpers.predictCreate3Address(salt, deployer);

        assertEq(prediction1, prediction2, "predictions must be stable");
        assertEq(prediction2, prediction3, "predictions must be stable");
    }

    /// @notice Regression test for broadcast context behavior with CREATE3
    /// @dev This test validates that CREATE3 deployments correctly use msg.sender
    ///      (the broadcaster) rather than address(this) (the harness contract)
    ///      when called within vm.startBroadcast() context.
    ///
    /// Security Context:
    /// - During Foundry broadcast, msg.sender is set to the broadcaster address
    /// - The deploying contract (harness) has a different address
    /// - CREATE3 addresses depend on the deployer address via msg.sender
    /// - Using address(this) instead of msg.sender would predict the wrong address
    ///
    /// This test proves:
    /// 1. Deployment address equals predictCreate3Address(salt, realDeployer)
    /// 2. Deployment address does NOT equal predictCreate3Address(salt, address(harness))
    /// 3. msg.sender during broadcast is realDeployer, not the harness contract
    function test_Create3BroadcastUsesCorrectDeployer() public {
        // Setup: Create a real deployer address different from test contract
        address realDeployer = address(0xD3D10);
        bytes32 salt = keccak256("BROADCAST_CONTEXT_TEST");

        // Predict addresses for BOTH scenarios
        address predictedFromRealDeployer = DeployHelpers.predictCreate3Address(salt, realDeployer);
        address predictedFromHarness = DeployHelpers.predictCreate3Address(salt, address(this));

        // CRITICAL: These predictions MUST be different
        assertTrue(predictedFromRealDeployer != predictedFromHarness, "Sanity check: deployer and harness must have different CREATE3 namespaces");

        // Fund the real deployer for gas
        vm.deal(realDeployer, 1 ether);

        // Simulate broadcast context: msg.sender becomes realDeployer
        vm.startBroadcast(realDeployer);

        // Deploy from within this test contract (harness)
        // address(this) != realDeployer, but msg.sender == realDeployer
        bytes memory creationCode = type(MockContract).creationCode;
        address deployed = CREATE3Factory(DeployHelpers.CREATE3_FACTORY).deploy(salt, creationCode);

        vm.stopBroadcast();

        // PROOF: Deployed address matches realDeployer prediction
        assertEq(deployed, predictedFromRealDeployer, "Deployed address must match prediction using realDeployer (msg.sender)");

        // PROOF: Deployed address does NOT match harness prediction
        assertTrue(deployed != predictedFromHarness, "Deployed address must NOT match prediction using address(harness)");

        // Verify contract was actually deployed
        assertTrue(deployed.code.length > 0, "Contract must have bytecode");
    }

    /// @notice Test deployViaCreate3 wrapper with explicit deployer parameter
    /// @dev This tests that deployViaCreate3 correctly accepts and uses the deployerAddress parameter.
    ///      In production, vm.startBroadcast() makes the broadcaster the actual caller.
    ///      In tests without broadcast, the test contract is the actual caller.
    function test_DeployViaCreate3WithExplicitDeployer() public {
        address deployer = address(this);
        bytes32 salt = keccak256("DEPLOY_HELPER_EXPLICIT_TEST");

        // Predict address using the deployer
        address predicted = DeployHelpers.predictCreate3Address(salt, deployer);

        // Deploy using explicit deployer parameter
        bytes memory creationCode = type(MockContract).creationCode;
        address deployed = DeployHelpers.deployViaCreate3(creationCode, salt, deployer);

        // Verify deployment matches prediction
        assertEq(deployed, predicted, "deployViaCreate3 must match prediction with explicit deployer");

        // Verify contract was actually deployed
        assertTrue(deployed.code.length > 0, "Contract must have bytecode");
    }

    /// @notice External helper to test deployViaCreate3 from external call context
    /// @dev In test context, the actual caller is always the test contract (address(this)),
    ///      so we pass address(this) as the deployerAddress parameter.
    function externalDeployHelper(bytes memory creationCode, bytes32 salt) external returns (address) {
        // Note: We pass address(this) because that's the actual caller in test context.
        // In production with vm.startBroadcast(), the actual caller would be the broadcaster.
        return DeployHelpers.deployViaCreate3(creationCode, salt, address(this));
    }

    /// @notice Test that verifies multiple deployments work correctly
    /// @dev This test proves the internal validation works correctly across multiple deployments
    function test_DeployViaCreate3MultipleDeploymentsWithCorrectDeployer() public {
        address deployer = address(this);
        bytes32 salt1 = keccak256("MULTIPLE_DEPLOYMENT_TEST_1");
        bytes32 salt2 = keccak256("MULTIPLE_DEPLOYMENT_TEST_2");

        // Deploy first contract
        address deployed1 = DeployHelpers.deployViaCreate3(type(MockContract).creationCode, salt1, deployer);

        // Deploy second contract with different salt
        address deployed2 = DeployHelpers.deployViaCreate3(type(MockContract).creationCode, salt2, deployer);

        // Verify both deployments use correct deployer
        assertEq(deployed1, DeployHelpers.predictCreate3Address(salt1, deployer), "First deployment must use correct deployer");

        assertEq(deployed2, DeployHelpers.predictCreate3Address(salt2, deployer), "Second deployment must use correct deployer");

        // Verify they're different addresses
        assertTrue(deployed1 != deployed2, "Different salts must produce different addresses");

        // Verify both have bytecode
        assertTrue(deployed1.code.length > 0, "First contract must have bytecode");
        assertTrue(deployed2.code.length > 0, "Second contract must have bytecode");
    }
}

// Simple mock contract for testing actual deployments
contract MockContract {
    uint256 public value = 42;

    function getValue() external view returns (uint256) {
        return value;
    }
}
