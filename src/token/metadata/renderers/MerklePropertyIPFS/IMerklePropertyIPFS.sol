// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

/// @title IMerklePropertyIPFS
/// @author Neokry
/// @notice The external functions and errors for the merkle property IPFS metadata renderer
/// @custom:repo github.com/neokry/builder-renderers
interface IMerklePropertyIPFS {
    ///                                                          ///
    ///                          STRUCTS                         ///
    ///                                                          ///
    /// @notice The parameters to use for setting attributes
    /// @param tokenId The token ID
    /// @param attributes The attributes to set
    /// @param proof The merkle proof
    struct SetAttributeParams {
        uint256 tokenId;
        uint16[16] attributes;
        bytes32[] proof;
    }

    ///                                                          ///
    ///                          ERRORs                          ///
    ///                                                          ///

    /// @notice Invalid merkle proof
    /// @param tokenId The token ID
    /// @param proof The merkle proof
    /// @param merkleRoot The merkle root
    error INVALID_MERKLE_PROOF(uint256 tokenId, bytes32[] proof, bytes32 merkleRoot);

    ///                                                          ///
    ///                          FUNCTIONS                       ///
    ///                                                          ///

    /// @notice Gets the attribute merkle root
    /// @return root The attribute merkle root
    function attributeMerkleRoot() external view returns (bytes32 root);

    /// @notice Sets the attribute merkle root
    /// @param attributeMerkleRoot_ The new attribute merkle root
    function setAttributeMerkleRoot(bytes32 attributeMerkleRoot_) external;

    /// @notice Sets the attributes for a token
    /// @param _params The parameters to use
    function setAttributes(SetAttributeParams calldata _params) external;

    /// @notice Sets the attributes for many tokens
    /// @param _params The parameters to use
    function setManyAttributes(SetAttributeParams[] calldata _params) external;
}
