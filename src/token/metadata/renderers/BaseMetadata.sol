// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import { IERC721Metadata } from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import { MetadataBuilder } from "micro-onchain-metadata-utils/MetadataBuilder.sol";
import { MetadataJSONKeys } from "micro-onchain-metadata-utils/MetadataJSONKeys.sol";

import { IOwnable } from "../../../lib/interfaces/IOwnable.sol";
import { Initializable } from "../../../lib/utils/Initializable.sol";
import { VersionedContract } from "../../../VersionedContract.sol";
import { IBaseMetadata } from "./IBaseMetadata.sol";

/// @title Base Metadata
/// @author Neokry
/// @notice The base contract for a DAO's artwork generator and renderer
/// @custom:repo github.com/neokry/builder-renderers
abstract contract BaseMetadata is IBaseMetadata, Initializable, VersionedContract {
    ///                                                          ///
    ///                          STRUCTS                         ///
    ///                                                          ///
    /// @custom:storage-location erc7201:nounsbuilder.storage.BaseMetadata
    struct BaseMetadataStorage {
        address _token;
        string _projectURI;
        string _description;
        string _contractImage;
        AdditionalTokenProperty[] _additionalTokenProperties;
    }

    ///                                                          ///
    ///                          CONSTANTS                       ///
    ///                                                          ///

    // keccak256(abi.encode(uint256(keccak256("nounsbuilder.storage.BaseMetadataRenderer")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant BaseMetadataStorageLocation = 0x2fa7648083c65a0ac045c9c0db3cad5a2f7ea16eb0ee0e12b4ab33de41044700;

    ///                                                          ///
    ///                          STORAGE                         ///
    ///                                                          ///

    function _getBaseMetadataStorage() private pure returns (BaseMetadataStorage storage $) {
        assembly {
            $.slot := BaseMetadataStorageLocation
        }
    }

    ///                                                          ///
    ///                          MODIFIERS                       ///
    ///                                                          ///

    /// @notice Checks the token owner if the current action is allowed
    modifier onlyOwner() {
        if (owner() != msg.sender) {
            revert IOwnable.ONLY_OWNER();
        }

        _;
    }

    ///                                                          ///
    ///                          INITIALIZER                     ///
    ///                                                          ///

    /// @notice Initializes the contract
    /// @param token_ The token contract
    /// @param projectURI_ The project URI
    /// @param description_ The collection description
    /// @param contractImage_ The contract image
    function __BaseMetadata_init(address token_, string memory projectURI_, string memory description_, string memory contractImage_)
        internal
        onlyInitializing
    {
        BaseMetadataStorage storage $ = _getBaseMetadataStorage();

        $._token = token_;
        $._projectURI = projectURI_;
        $._description = description_;
        $._contractImage = contractImage_;
    }

    ///                                                          ///
    ///                     PROPERTIES                           ///
    ///                                                          ///

    /// @notice Updates the additional token properties associated with the metadata.
    /// @dev Be careful to not conflict with already used keys such as "name", "description", "properties",
    /// @param _additionalTokenProperties The additional token properties to set
    function setAdditionalTokenProperties(AdditionalTokenProperty[] memory _additionalTokenProperties) external onlyOwner {
        BaseMetadataStorage storage $ = _getBaseMetadataStorage();

        delete $._additionalTokenProperties;
        for (uint256 i = 0; i < _additionalTokenProperties.length; i++) {
            $._additionalTokenProperties.push(_additionalTokenProperties[i]);
        }

        emit AdditionalTokenPropertiesSet(_additionalTokenProperties);
    }

    /// @notice Gets the additional token properties
    /// @return _additionalTokenProperties The additional token properties
    function getAdditionalTokenProperties() public view returns (AdditionalTokenProperty[] memory _additionalTokenProperties) {
        BaseMetadataStorage storage $ = _getBaseMetadataStorage();
        _additionalTokenProperties = new AdditionalTokenProperty[]($._additionalTokenProperties.length);

        for (uint256 i = 0; i < $._additionalTokenProperties.length; i++) {
            _additionalTokenProperties[i] = $._additionalTokenProperties[i];
        }
    }

    ///                                                          ///
    ///                            URIs                          ///
    ///                                                          ///

    /// @notice Internal getter function for token name
    function _name() internal view returns (string memory) {
        BaseMetadataStorage storage $ = _getBaseMetadataStorage();
        return IERC721Metadata($._token).name();
    }

    /// @notice The contract URI
    function contractURI() external view override returns (string memory) {
        BaseMetadataStorage storage $ = _getBaseMetadataStorage();
        MetadataBuilder.JSONItem[] memory items = new MetadataBuilder.JSONItem[](4);

        items[0] = MetadataBuilder.JSONItem({ key: MetadataJSONKeys.keyName, value: _name(), quote: true });
        items[1] = MetadataBuilder.JSONItem({ key: MetadataJSONKeys.keyDescription, value: $._description, quote: true });
        items[2] = MetadataBuilder.JSONItem({ key: MetadataJSONKeys.keyImage, value: $._contractImage, quote: true });
        items[3] = MetadataBuilder.JSONItem({ key: "external_url", value: $._projectURI, quote: true });

        return MetadataBuilder.generateEncodedJSON(items);
    }

    ///                                                          ///
    ///                       METADATA SETTINGS                  ///
    ///                                                          ///

    /// @notice The associated ERC-721 token
    function token() public view returns (address) {
        BaseMetadataStorage storage $ = _getBaseMetadataStorage();
        return $._token;
    }

    /// @notice The contract image
    function contractImage() public view returns (string memory) {
        BaseMetadataStorage storage $ = _getBaseMetadataStorage();
        return $._contractImage;
    }

    /// @notice The collection description
    function description() public view returns (string memory) {
        BaseMetadataStorage storage $ = _getBaseMetadataStorage();
        return $._description;
    }

    /// @notice The collection description
    function projectURI() public view returns (string memory) {
        BaseMetadataStorage storage $ = _getBaseMetadataStorage();
        return $._projectURI;
    }

    /// @notice Get the owner of the metadata (here delegated to the token owner)
    function owner() public view returns (address) {
        BaseMetadataStorage storage $ = _getBaseMetadataStorage();
        return IOwnable($._token).owner();
    }

    /// @notice If the contract implements an interface
    /// @param _interfaceId The interface id
    function supportsInterface(bytes4 _interfaceId) public pure virtual returns (bool) {
        return _interfaceId == 0x01ffc9a7 || _interfaceId == type(IBaseMetadata).interfaceId;
    }

    ///                                                          ///
    ///                       UPDATE SETTINGS                    ///
    ///                                                          ///

    /// @notice Updates the contract image
    /// @param _newContractImage The new contract image
    function updateContractImage(string memory _newContractImage) external onlyOwner {
        BaseMetadataStorage storage $ = _getBaseMetadataStorage();
        emit ContractImageUpdated($._contractImage, _newContractImage);

        $._contractImage = _newContractImage;
    }

    /// @notice Updates the collection description
    /// @param _newDescription The new description
    function updateDescription(string memory _newDescription) external onlyOwner {
        BaseMetadataStorage storage $ = _getBaseMetadataStorage();
        emit DescriptionUpdated($._description, _newDescription);

        $._description = _newDescription;
    }

    /// @notice Updates the project URI
    /// @param _newProjectURI The new project URI
    function updateProjectURI(string memory _newProjectURI) external onlyOwner {
        BaseMetadataStorage storage $ = _getBaseMetadataStorage();
        emit WebsiteURIUpdated($._projectURI, _newProjectURI);

        $._projectURI = _newProjectURI;
    }
}
