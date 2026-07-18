// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

/// @title IDAOFactory
/// @notice Interface for the canonical DAO deployment factory
/// @dev This factory acts as the canonical deployer for all DAO proxies, enabling cross-chain
///      deterministic deployments regardless of the Manager contract's address.
interface IDAOFactory {
    ///                                                          ///
    ///                            EVENTS                        ///
    ///                                                          ///

    /// @notice Emitted when a proxy is deployed
    /// @param deployer The address that initiated the deployment (typically a Manager contract)
    /// @param deployed The address of the deployed proxy
    /// @param salt The salt used for deployment
    event ProxyDeployed(address indexed deployer, address deployed, bytes32 salt);

    ///                                                          ///
    ///                            ERRORS                        ///
    ///                                                          ///

    /// @dev Reverts if the CREATE3 deployment fails
    error DEPLOYMENT_FAILED();

    /// @dev Reverts if the deployed address doesn't match prediction
    error ADDRESS_MISMATCH();

    /// @dev Reverts if caller is not the authorized Manager
    error UNAUTHORIZED();

    ///                                                          ///
    ///                           FUNCTIONS                      ///
    ///                                                          ///

    /// @notice The Manager contract authorized to use this factory
    /// @return The Manager address set in the constructor
    function manager() external view returns (address);

    /// @notice Deploys a proxy contract using CREATE3
    /// @dev Uses this contract (DAOFactory) as the canonical deployer, ensuring all Manager
    ///      contracts produce identical DAO addresses when using the same salt.
    /// @param salt The salt to use for CREATE3 deployment
    /// @param creationCode The creation code for the proxy (typically ERC1967Proxy)
    /// @return deployed The address of the deployed proxy
    function deployProxy(bytes32 salt, bytes memory creationCode) external payable returns (address deployed);

    /// @notice Predicts the address of a proxy that would be deployed with the given salt
    /// @dev This prediction is independent of the caller's address since DAOFactory is the deployer
    /// @param salt The salt to use for prediction
    /// @return predicted The predicted address
    function predictAddress(bytes32 salt) external view returns (address predicted);
}
