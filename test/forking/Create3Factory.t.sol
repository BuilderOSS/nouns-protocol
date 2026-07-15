// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import "forge-std/Test.sol";
import { ICREATE3Factory } from "create3-factory/ICREATE3Factory.sol";
import { DeployHelpers } from "../../script/DeployHelpers.sol";

/// @title Create3FactoryTest
/// @notice Tests to verify CREATE3 factory deployment and prediction logic
contract Create3FactoryTest is Test {
    address internal constant CREATE3_FACTORY = DeployHelpers.CREATE3_FACTORY;

    /// @notice Test that CREATE3 factory exists on mainnet
    function test_Create3FactoryExistsMainnet() public {
        vm.createSelectFork(vm.rpcUrl("mainnet"));
        _assertFactoryExists();
    }

    /// @notice Test that CREATE3 factory exists on Optimism
    function test_Create3FactoryExistsOptimism() public {
        vm.createSelectFork(vm.rpcUrl("optimism"));
        _assertFactoryExists();
    }

    /// @notice Test that CREATE3 factory exists on Base
    function test_Create3FactoryExistsBase() public {
        vm.createSelectFork(vm.rpcUrl("base"));
        _assertFactoryExists();
    }

    /// @notice Test that CREATE3 factory exists on Sepolia
    function test_Create3FactoryExistsSepolia() public {
        vm.createSelectFork(vm.rpcUrl("sepolia"));
        _assertFactoryExists();
    }

    /// @notice Test that CREATE3 factory exists on Optimism Sepolia
    function test_Create3FactoryExistsOptimismSepolia() public {
        vm.createSelectFork(vm.rpcUrl("optimism_sepolia"));
        _assertFactoryExists();
    }

    /// @notice Test that CREATE3 factory exists on Base Sepolia
    function test_Create3FactoryExistsBaseSepolia() public {
        vm.createSelectFork(vm.rpcUrl("base_sepolia"));
        _assertFactoryExists();
    }

    /// @notice Test that our prediction logic matches the factory's getDeployed function
    function test_Create3PredictionMatchesFactory() public {
        vm.createSelectFork(vm.rpcUrl("mainnet"));

        address deployer = address(0x1234567890123456789012345678901234567890);
        bytes32 salt = keccak256("test_salt");

        // Get prediction from factory
        address factoryPrediction = ICREATE3Factory(CREATE3_FACTORY).getDeployed(deployer, salt);

        // Get prediction from our helper
        address ourPrediction = DeployHelpers.predictCreate3Address(salt, deployer);

        // They should match
        assertEq(ourPrediction, factoryPrediction, "Prediction mismatch");
    }

    /// @notice Test multiple salts to ensure prediction is consistent
    function testFuzz_Create3PredictionMatchesFactory(bytes32 salt, address deployer) public {
        vm.createSelectFork(vm.rpcUrl("mainnet"));

        // Get prediction from factory
        address factoryPrediction = ICREATE3Factory(CREATE3_FACTORY).getDeployed(deployer, salt);

        // Get prediction from our helper
        address ourPrediction = DeployHelpers.predictCreate3Address(salt, deployer);

        // They should match
        assertEq(ourPrediction, factoryPrediction, "Prediction mismatch");
    }

    /// @notice Helper to assert factory exists with code
    function _assertFactoryExists() internal {
        address factory = CREATE3_FACTORY;
        uint256 codeSize;
        assembly {
            codeSize := extcodesize(factory)
        }
        assertGt(codeSize, 0, "CREATE3 factory does not exist");
    }
}
