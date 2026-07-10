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
        $._attributeMerkleRoot = attributeMerkleRoot_;
    }

    ///                                                          ///
    ///                          ATTRIBUTES                      ///
    ///                                                          ///

    /// @notice Sets the attributes for a token
    /// @param _params The parameters to use
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

        // Verify the attributes and tokenId are valid
        if (!MerkleProof.verify(_params.proof, $._attributeMerkleRoot, keccak256(abi.encodePacked(_params.tokenId, _params.attributes)))) {
            revert INVALID_MERKLE_PROOF(_params.tokenId, _params.proof, $._attributeMerkleRoot);
        }

        // Set the attributes
        _setAttributes(_params.tokenId, _params.attributes);
    }

    /// @notice If the contract implements an interface
    /// @param _interfaceId The interface id
    function supportsInterface(bytes4 _interfaceId) public pure override returns (bool) {
        return super.supportsInterface(_interfaceId) || _interfaceId == type(IMerklePropertyIPFS).interfaceId;
    }
}
