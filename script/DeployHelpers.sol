// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import { ICREATE3Factory } from "create3-factory/ICREATE3Factory.sol";

/// @title DeployHelpers
/// @notice Helper functions for deterministic cross-chain deployments using CREATE2 and CREATE3 factories
library DeployHelpers {
    /// @notice The CREATE3 factory address
    /// @dev Deployed at the same address on mainnet, optimism, base, and testnets
    /// @dev CREATE3 enables bytecode-independent deterministic deployments
    address public constant CREATE3_FACTORY = 0xD252d074EEe65b64433a5a6f30Ab67569362E7e0;

    /// @notice Deploys a contract via the CREATE3 factory for bytecode-independent determinism
    /// @dev CREATE3 address depends only on salt and deployer, NOT on bytecode
    /// @dev This enables same addresses across chains even when constructor args differ
    /// @param creationCode The complete creation bytecode (including constructor args)
    /// @param salt The CREATE3 salt (will be hashed with deployer by factory)
    /// @param deployerAddress The address that will call CREATE3Factory (usually from vm.addr(privateKey))
    /// @return deployed The deployed contract address
    function deployViaCreate3(bytes memory creationCode, bytes32 salt, address deployerAddress) internal returns (address deployed) {
        // Call CREATE3Factory.deploy(salt, creationCode)
        // The external call will be made with msg.sender = deployerAddress when called during vm.startBroadcast()
        deployed = ICREATE3Factory(CREATE3_FACTORY).deploy(salt, creationCode);

        // Verify deployed address matches prediction using the expected deployer
        // CRITICAL: Use deployerAddress (not msg.sender or address(this)) to verify against the actual
        // deployer that will be used by the CREATE3 factory during broadcast
        address predicted = predictCreate3Address(salt, deployerAddress);
        require(deployed == predicted, "CREATE3 deployed address mismatch");

        // Verify contract was actually deployed
        require(deployed.code.length > 0, "CREATE3 deployment produced no code");
    }

    /// @notice Predicts the address for a CREATE3 deployment
    /// @dev Delegates to the CREATE3 factory's getDeployed function
    /// @param salt The CREATE3 salt
    /// @param deployer The address calling the CREATE3 factory
    /// @return The predicted deployment address
    function predictCreate3Address(bytes32 salt, address deployer) internal view returns (address) {
        return ICREATE3Factory(CREATE3_FACTORY).getDeployed(deployer, salt);
    }

    /// @notice Converts an address to a hex string (lowercase, without checksum)
    /// @param _addr The address to convert
    /// @return The hex string representation with 0x prefix
    function addressToString(address _addr) internal pure returns (string memory) {
        bytes memory s = new bytes(40);
        for (uint256 i = 0; i < 20; i++) {
            bytes1 b = bytes1(uint8(uint256(uint160(_addr)) / (2 ** (8 * (19 - i)))));
            bytes1 hi = bytes1(uint8(b) / 16);
            bytes1 lo = bytes1(uint8(b) - 16 * uint8(hi));
            s[2 * i] = char(hi);
            s[2 * i + 1] = char(lo);
        }
        return string(abi.encodePacked("0x", string(s)));
    }

    /// @notice Converts a bytes32 value to a hex string
    /// @param _bytes The bytes32 value to convert
    /// @return The hex string representation with 0x prefix
    function bytes32ToString(bytes32 _bytes) internal pure returns (string memory) {
        bytes memory s = new bytes(64);
        for (uint256 i = 0; i < 32; i++) {
            bytes1 b = _bytes[i];
            bytes1 hi = bytes1(uint8(b) / 16);
            bytes1 lo = bytes1(uint8(b) - 16 * uint8(hi));
            s[2 * i] = char(hi);
            s[2 * i + 1] = char(lo);
        }
        return string(abi.encodePacked("0x", string(s)));
    }

    /// @notice Converts a hex nibble (0-15) to its ASCII character representation
    /// @param b The nibble to convert (must be 0-15)
    /// @return c The ASCII character ('0'-'9' or 'a'-'f')
    function char(bytes1 b) internal pure returns (bytes1 c) {
        if (uint8(b) < 10) return bytes1(uint8(b) + 0x30);
        else return bytes1(uint8(b) + 0x57);
    }
}
