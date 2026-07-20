// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import { MerkleProof } from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

import { IMerklePropertyIPFS } from "./IMerklePropertyIPFS.sol";
import { PropertyIPFS } from "../PropertyIPFS/PropertyIPFS.sol";

/// @title Merkle Property IPFS Metadata Renderer
/// @author Neokry
/// @notice A property metadata renderer that allows setting attributes using a merkle proof
/// @custom:repo github.com/neokry/builder-renderers
contract MerklePropertyIPFS is IMerklePropertyIPFS, PropertyIPFS {
    ///                                                          ///
    ///                          STRUCTS                         ///
    ///                                                          ///
    /// @custom:storage-location erc7201:nounsbuilder.storage.MerklePropertyIPFSRenderer
    struct MerkleStorage {
        bytes32 _attributeMerkleRoot;
    }

    ///                                                          ///
    ///                          CONSTANTS                       ///
    ///                                                          ///

    // keccak256(abi.encode(uint256(keccak256("nounsbuilder.storage.MerklePropertyIPFSRenderer")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant MerkleStorageLocation = 0x229b75c6355fd6ea600c084f9eb4b91be4eb40c79db7f3ada8e7a1d5e6033200;

    ///                                                          ///
    ///                          STORAGE                         ///
    ///                                                          ///

    function _getMerkleStorage() private pure returns (MerkleStorage storage $) {
        assembly {
            $.slot := MerkleStorageLocation
        }
    }

    ///                                                          ///
    ///                          CONSTRUCTOR                     ///
    ///                                                          ///

    /// @notice Creates a new merkle metadata renderer
    /// @param _manager The contract upgrade manager address
    constructor(address _manager) PropertyIPFS(_manager) { }

    ///                                                          ///
    ///                          MERKLE ROOT                     ///
    ///                                                          ///

    /// @notice Gets the attribute merkle root
    /// @return root The attribute merkle root
    function attributeMerkleRoot() external view returns (bytes32 root) {
        MerkleStorage storage $ = _getMerkleStorage();
        root = $._attributeMerkleRoot;
    }

    /// @notice Sets the attribute merkle root
    /// @param attributeMerkleRoot_ The new attribute merkle root
    function setAttributeMerkleRoot(bytes32 attributeMerkleRoot_) external onlyOwner {
        MerkleStorage storage $ = _getMerkleStorage();
        bytes32 oldRoot = $._attributeMerkleRoot;
        $._attributeMerkleRoot = attributeMerkleRoot_;

        emit AttributeMerkleRootUpdated(oldRoot, attributeMerkleRoot_);
    }

    ///                                                          ///
    ///                          ATTRIBUTES                      ///
    ///                                                          ///

    /// @notice Sets the attributes for a token using a Merkle proof
    /// @param _params The parameters containing tokenId, attributes, and Merkle proof
    /// @dev This function is permissionless but requires a valid Merkle proof against the owner-controlled root.
    ///      IMPORTANT: This function can be called BEFORE a token is minted. This is intentional and enables:
    ///      - Pre-mint attribute assignment for reveal workflows
    ///      - Merkle allowlists with predetermined traits
    ///      - Gas-optimized batch operations where attributes are set separately from minting
    ///      When attributes are pre-set, onMinted() will skip pseudorandom generation and preserve these values.
    ///      Only attribute combinations in the Merkle tree (controlled by owner via setAttributeMerkleRoot) can be set.
    function setAttributes(SetAttributeParams calldata _params) external {
        _setAttributesWithProof(_params);
    }

    /// @notice Sets the attributes for many tokens
    /// @param _params The parameters to use
    function setManyAttributes(SetAttributeParams[] calldata _params) external {
        uint256 len = _params.length;
        unchecked {
            for (uint256 i; i < len; ++i) {
                _setAttributesWithProof(_params[i]);
            }
        }
    }

    /// @dev Sets the attributes for a token using merkle proofs
    function _setAttributesWithProof(SetAttributeParams calldata _params) private {
        MerkleStorage storage $ = _getMerkleStorage();

        // Step 1: Verify Merkle proof
        if (!MerkleProof.verify(_params.proof, $._attributeMerkleRoot, keccak256(abi.encodePacked(_params.tokenId, _params.attributes)))) {
            revert INVALID_MERKLE_PROOF(_params.tokenId, _params.proof, $._attributeMerkleRoot);
        }

        // Step 2: Validate attributes are renderable
        _validateAttributes(_params.tokenId, _params.attributes);

        // Step 3: Set the attributes (now guaranteed to be valid)
        _setAttributes(_params.tokenId, _params.attributes);
    }

    /// @notice Validates that attributes are valid for the current property configuration
    /// @dev Validates that Merkle-proved attributes are renderable against current property configuration
    /// @param _tokenId The token ID (for error messages)
    /// @param _attributes The attributes to validate
    function _validateAttributes(uint256 _tokenId, uint16[16] calldata _attributes) private view {
        PropertyIPFSStorage storage $ = _getPropertyIPFSStorage();

        // Get claimed property count from attributes[0]
        uint256 claimedPropertyCount = _attributes[0];

        // Get actual property count from renderer
        uint256 actualPropertyCount = $._properties.length;

        // Validate property count is non-zero
        if (claimedPropertyCount == 0) {
            revert INVALID_ATTRIBUTE_PROPERTY_COUNT(_tokenId, 0, actualPropertyCount);
        }

        // Validate property count is within bounds (max 15 properties) - check this before mismatch
        if (claimedPropertyCount > 15) {
            revert INVALID_ATTRIBUTE_PROPERTY_COUNT(_tokenId, claimedPropertyCount, 15);
        }

        // Validate property count matches current configuration
        if (claimedPropertyCount != actualPropertyCount) {
            revert INVALID_ATTRIBUTE_PROPERTY_COUNT(_tokenId, claimedPropertyCount, actualPropertyCount);
        }

        // Validate each item index is within bounds for its property
        unchecked {
            for (uint256 i = 0; i < claimedPropertyCount; ++i) {
                uint256 itemIndex = _attributes[i + 1];
                uint256 itemsLength = $._properties[i].items.length;

                if (itemIndex >= itemsLength) {
                    revert INVALID_ATTRIBUTE_ITEM_INDEX(_tokenId, i, itemIndex, itemsLength - 1);
                }
            }
        }
    }

    /// @notice If the contract implements an interface
    /// @param _interfaceId The interface id
    function supportsInterface(bytes4 _interfaceId) public pure override returns (bool) {
        return super.supportsInterface(_interfaceId) || _interfaceId == type(IMerklePropertyIPFS).interfaceId;
    }
}
