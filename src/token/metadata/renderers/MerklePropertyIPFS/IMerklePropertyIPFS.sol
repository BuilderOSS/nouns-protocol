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
    ///                          EVENTS                          ///
    ///                                                          ///

    /// @notice Emitted when the attribute merkle root is updated
    /// @param oldRoot The previous attribute merkle root
    /// @param newRoot The new attribute merkle root
    event AttributeMerkleRootUpdated(bytes32 indexed oldRoot, bytes32 indexed newRoot);

    ///                                                          ///
    ///                          ERRORs                          ///
    ///                                                          ///

    /// @notice Invalid merkle proof
    /// @param tokenId The token ID
    /// @param proof The merkle proof
    /// @param merkleRoot The merkle root
    error INVALID_MERKLE_PROOF(uint256 tokenId, bytes32[] proof, bytes32 merkleRoot);

    /// @notice Invalid attribute property count
    /// @param tokenId The token ID
    /// @param claimedCount The claimed property count from attributes
    /// @param actualCount The actual property count in the renderer
    error INVALID_ATTRIBUTE_PROPERTY_COUNT(uint256 tokenId, uint256 claimedCount, uint256 actualCount);

    /// @notice Invalid attribute item index
    /// @param tokenId The token ID
    /// @param propertyId The property ID
    /// @param itemIndex The invalid item index
    /// @param maxIndex The maximum valid index
    error INVALID_ATTRIBUTE_ITEM_INDEX(uint256 tokenId, uint256 propertyId, uint256 itemIndex, uint256 maxIndex);

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
