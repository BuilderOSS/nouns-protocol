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
}

// Simple mock contract for testing actual deployments
contract MockContract {
    uint256 public value = 42;

    function getValue() external view returns (uint256) {
        return value;
    }
}
