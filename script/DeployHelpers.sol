// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

/// @title DeployHelpers
/// @notice Helper functions for deterministic cross-chain deployments using CREATE2 and CREATE3 factories
library DeployHelpers {
    /// @notice The canonical CREATE2 factory address (Nick's factory)
    /// @dev Deployed at the same address on all EVM chains
    address internal constant CREATE2_FACTORY = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

    /// @notice The CREATE3 factory address
    /// @dev Deployed at the same address on mainnet, optimism, base, and testnets
    /// @dev CREATE3 enables bytecode-independent deterministic deployments
    address public constant CREATE3_FACTORY = 0xD252d074EEe65b64433a5a6f30Ab67569362E7e0;

    /// @notice Deploys a contract via the CREATE2 factory
    /// @param creationCode The complete creation bytecode (including constructor args)
    /// @param salt The CREATE2 salt
    /// @return deployed The deployed contract address
    function deployViaFactory(bytes memory creationCode, bytes32 salt) internal returns (address deployed) {
        // Prepare factory payload: salt || initCode
        bytes memory payload = abi.encodePacked(salt, creationCode);

        // Deploy via CREATE2 factory
        (bool success, bytes memory result) = CREATE2_FACTORY.call(payload);

        // Ensure deployment succeeded
        require(success, "Factory deployment failed");

        // Validate return value is exactly 20 bytes (address)
        require(result.length == 20, "Invalid factory return");

        // Extract deployed address
        deployed = address(uint160(bytes20(result)));

        // Verify deployed address matches prediction to ensure canonical factory behavior
        address predicted = predictAddress(creationCode, salt);
        require(deployed == predicted, "Deployed address mismatch");

        // Verify contract was actually deployed
        require(deployed.code.length > 0, "Deployment produced no code");
    }

    /// @notice Predicts the address for a CREATE2 deployment via factory
    /// @param creationCode The complete creation bytecode (including constructor args)
    /// @param salt The CREATE2 salt
    /// @return The predicted deployment address
    function predictAddress(bytes memory creationCode, bytes32 salt) internal pure returns (address) {
        bytes32 hash = keccak256(abi.encodePacked(bytes1(0xff), CREATE2_FACTORY, salt, keccak256(creationCode)));
        return address(uint160(uint256(hash)));
    }

    /// @notice Deploys a contract via the CREATE3 factory for bytecode-independent determinism
    /// @dev CREATE3 address depends only on salt and deployer, NOT on bytecode
    /// @dev This enables same addresses across chains even when constructor args differ
    /// @param creationCode The complete creation bytecode (including constructor args)
    /// @param salt The CREATE3 salt (will be hashed with msg.sender by factory)
    /// @return deployed The deployed contract address
    function deployViaCreate3(bytes memory creationCode, bytes32 salt) internal returns (address deployed) {
        // Call CREATE3Factory.deploy(salt, creationCode)
        bytes memory callData = abi.encodeWithSignature("deploy(bytes32,bytes)", salt, creationCode);

        (bool success, bytes memory result) = CREATE3_FACTORY.call(callData);
        require(success, "CREATE3 deployment failed");

        // Decode deployed address from result
        deployed = abi.decode(result, (address));

        // Verify deployed address matches prediction
        // CRITICAL: Use msg.sender (not address(this)) because in Foundry broadcast,
        // msg.sender is the broadcaster address, not the script contract
        address predicted = predictCreate3Address(salt, msg.sender);
        require(deployed == predicted, "CREATE3 deployed address mismatch");

        // Verify contract was actually deployed
        require(deployed.code.length > 0, "CREATE3 deployment produced no code");
    }

    /// @notice Predicts the address for a CREATE3 deployment
    /// @dev CREATE3 uses a two-step process: CREATE2 proxy + CREATE from proxy
    /// @param salt The CREATE3 salt
    /// @param deployer The address calling the CREATE3 factory
    /// @return The predicted deployment address
    function predictCreate3Address(bytes32 salt, address deployer) internal pure returns (address) {
        // Step 1: CREATE3 factory hashes deployer into the salt
        bytes32 finalSalt = keccak256(abi.encodePacked(deployer, salt));

        // Step 2: Calculate proxy address via CREATE2 with fixed proxy bytecode
        // Proxy bytecode hash is constant: keccak256(hex"67_36_3d_3d_37_36_3d_34_f0_3d_52_60_08_60_18_f3")
        bytes32 proxyBytecodeHash = 0x21c35dbe1b344a2488cf3321d6ce542f8e9f305544ff09e4993a62319a497c1f;

        bytes32 proxyHash = keccak256(abi.encodePacked(bytes1(0xff), CREATE3_FACTORY, finalSalt, proxyBytecodeHash));

        address proxy = address(uint160(uint256(proxyHash)));

        // Step 3: Calculate final address via CREATE from proxy (nonce = 1)
        // Address formula: keccak256(rlp([proxy, 1]))
        // RLP encoding of [proxy, 1]: 0xd6_94 ++ proxy ++ 0x01
        bytes32 finalHash = keccak256(abi.encodePacked(hex"d694", proxy, hex"01"));

        return address(uint160(uint256(finalHash)));
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
