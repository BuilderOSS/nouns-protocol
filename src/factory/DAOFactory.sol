// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import { CREATE3 } from "solmate/utils/CREATE3.sol";
import { IDAOFactory } from "./IDAOFactory.sol";

/// @title DAOFactory
/// @notice Canonical factory for deterministic DAO deployments across chains
/// @dev This contract acts as the canonical deployer for all DAO proxies. By having all Manager
///      contracts route their deployments through this single factory, we achieve cross-chain
///      determinism regardless of the Manager's address. The factory uses CREATE3 for bytecode-
///      independent deployments.
///
///      Key benefits:
///      1. Cross-chain determinism: Same salt produces same addresses on all chains
///      2. Manager-independent: Different Manager addresses produce identical DAO addresses
///      3. Bytecode-independent: Implementation changes don't affect predicted addresses
///
///      WHY THIS IS NEEDED:
///      The Manager contract is already deployed at different addresses on different chains.
///      Without DAOFactory, each Manager would produce different DAO addresses because CREATE3
///      includes msg.sender (the Manager address) in its calculation. DAOFactory solves this by
///      acting as a single canonical deployer - all Managers call DAOFactory, which deploys
///      using address(this), ensuring consistent addresses across chains.
///
///      DEPLOYMENT PATTERN:
///      1. Deploy DAOFactory at address X on all chains using CREATE3Factory
///      2. Deploy Manager at different addresses on each chain, all referencing DAOFactory at address X
///      3. When any Manager calls DAOFactory.deployProxy(), DAOFactory uses address(this) as deployer
///      4. Result: Same (deployer=X, salt) produces same DAO addresses across all chains
///
///      This contract should be deployed at the same address on all chains using CREATE3Factory.
contract DAOFactory is IDAOFactory {
    ///                                                          ///
    ///                        IMMUTABLES                        ///
    ///                                                          ///

    /// @notice The Manager contract authorized to use this factory
    /// @dev Set in constructor and immutable. Only this Manager can deploy through this factory.
    ///      Each chain has its own DAOFactory+Manager pair, but all DAOFactories are at the same address.
    address public immutable manager;

    ///                                                          ///
    ///                        CONSTRUCTOR                       ///
    ///                                                          ///

    /// @notice Creates a new DAOFactory bound to a specific Manager
    /// @param _manager The Manager contract address that is authorized to use this factory
    constructor(address _manager) {
        manager = _manager;
    }

    ///                                                          ///
    ///                        DEPLOYMENT                        ///
    ///                                                          ///

    /// @notice Deploys a proxy contract using CREATE3
    /// @dev Uses this contract (DAOFactory) as the canonical deployer via CREATE3 library
    ///      Only the authorized Manager can call this function.
    /// @param salt The salt to use for CREATE3 deployment
    /// @param creationCode The creation code for the proxy (typically ERC1967Proxy)
    /// @return deployed The address of the deployed proxy
    function deployProxy(bytes32 salt, bytes memory creationCode) external payable returns (address deployed) {
        // Only authorized Manager can deploy
        if (msg.sender != manager) revert UNAUTHORIZED();

        // Deploy using CREATE3 library
        // CREATE3.deploy uses address(this) as the deployer, making predictions consistent
        deployed = CREATE3.deploy(salt, creationCode, msg.value);

        // Verify deployment succeeded
        if (deployed == address(0)) revert DEPLOYMENT_FAILED();
        if (deployed.code.length == 0) revert DEPLOYMENT_FAILED();

        // Verify deployed address matches prediction
        address predicted = predictAddress(salt);
        if (deployed != predicted) revert ADDRESS_MISMATCH();

        emit ProxyDeployed(msg.sender, deployed, salt);
    }

    ///                                                          ///
    ///                        PREDICTION                        ///
    ///                                                          ///

    /// @notice Predicts the address of a proxy that would be deployed with the given salt
    /// @dev Uses CREATE3.getDeployed which computes address based on this contract's address
    ///      This ensures predictions are identical regardless of who calls this function
    /// @param salt The salt to use for prediction
    /// @return predicted The predicted address
    function predictAddress(bytes32 salt) public view returns (address predicted) {
        // CREATE3.getDeployed uses address(this) internally, ensuring consistent predictions
        predicted = CREATE3.getDeployed(salt);
    }
}
