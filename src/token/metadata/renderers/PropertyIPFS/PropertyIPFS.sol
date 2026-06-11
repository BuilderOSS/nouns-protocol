// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { MetadataBuilder } from "micro-onchain-metadata-utils/MetadataBuilder.sol";
import { MetadataJSONKeys } from "micro-onchain-metadata-utils/MetadataJSONKeys.sol";
import { UriEncode } from "sol-uriencode/src/UriEncode.sol";

import { IManager } from "../../../../manager/IManager.sol";
import { UUPS } from "../../../../lib/proxy/UUPS.sol";
import { IPropertyIPFS } from "./IPropertyIPFS.sol";
import { BaseMetadata } from "../BaseMetadata.sol";

/// @title Property IPFS Metadata Renderer
/// @author Neokry
/// @notice A metadata renderer that generates token attributes from a set of properties and items
/// @custom:repo github.com/neokry/builder-renderers
contract PropertyIPFS is IPropertyIPFS, BaseMetadata, UUPS {
    ///                                                          ///
    ///                          STRUCTS                         ///
    ///                                                          ///

    /// @custom:storage-location erc7201:nounsbuilder.storage.PropertyIPFSRenderer
    struct PropertyIPFSStorage {
        string _rendererBase;
        Property[] _properties;
        IPFSGroup[] _ipfsData;
        mapping(uint256 => uint16[16]) _attributes;
    }

    ///                                                          ///
    ///                          CONSTANTS                       ///
    ///                                                          ///

    // keccak256(abi.encode(uint256(keccak256("nounsbuilder.storage.PropertyIPFSRenderer")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant PropertyIPFSStorageLocation = 0x6e86adc91987cfd0c2727f2061f4e6022e5e9212736e682f4eb1f6949f6a7b00;

    ///                                                          ///
    ///                          IMMUTABLES                      ///
    ///                                                          ///

    /// @notice The contract upgrade manager
    address private immutable manager;

    ///                                                          ///
    ///                          STORAGE                         ///
    ///                                                          ///

    function _getPropertyIPFSStorage() private pure returns (PropertyIPFSStorage storage $) {
        assembly {
            $.slot := PropertyIPFSStorageLocation
        }
    }

    ///                                                          ///
    ///                          CONSTRUCTOR                     ///
    ///                                                          ///

    /// @param _manager The contract upgrade manager address
    constructor(address _manager) payable initializer {
        manager = _manager;
    }

    ///                                                          ///
    ///                          INITILIZER                      ///
    ///                                                          ///

    /// @notice Initializes a DAO's token metadata renderer
    /// @param _initStrings The encoded token and metadata initialization strings
    /// @param _token The ERC-721 token address
    function initialize(bytes calldata _initStrings, address _token) external override initializer {
        // Ensure the caller is the contract manager
        if (msg.sender != address(manager)) {
            revert ONLY_MANAGER();
        }

        PropertyIPFSStorage storage $ = _getPropertyIPFSStorage();

        // Decode the token initialization strings
        (,, string memory _description, string memory _contractImage, string memory _projectURI, string memory _rendererBase) =
            abi.decode(_initStrings, (string, string, string, string, string, string));

        __BaseMetadata_init(_token, _projectURI, _description, _contractImage);

        $._rendererBase = _rendererBase;
    }

    ///                                                          ///
    ///                     PROPERTIES & ITEMS                   ///
    ///                                                          ///

    /// @notice The number of properties
    /// @return properties array length
    function propertiesCount() external view returns (uint256) {
        PropertyIPFSStorage storage $ = _getPropertyIPFSStorage();
        return $._properties.length;
    }

    /// @notice The number of items in a property
    /// @param _propertyId The property id
    /// @return items array length
    function itemsCount(uint256 _propertyId) external view returns (uint256) {
        PropertyIPFSStorage storage $ = _getPropertyIPFSStorage();
        return $._properties[_propertyId].items.length;
    }

    /// @notice The number of items in the IPFS data store
    /// @return ipfs data array size
    function ipfsDataCount() external view returns (uint256) {
        PropertyIPFSStorage storage $ = _getPropertyIPFSStorage();
        return $._ipfsData.length;
    }

    /// @notice Adds properties and/or items to be pseudo-randomly chosen from during token minting
    /// @param _names The names of the properties to add
    /// @param _items The items to add to each property
    /// @param _ipfsGroup The IPFS base URI and extension
    function addProperties(string[] calldata _names, ItemParam[] calldata _items, IPFSGroup calldata _ipfsGroup) external onlyOwner {
        _addProperties(_names, _items, _ipfsGroup);
    }

    /// @notice Deletes existing properties and/or items to be pseudo-randomly chosen from during token minting, replacing them with provided properties. WARNING: This function can alter or break existing token metadata if the number of properties for this renderer change before/after the upsert. If the properties selected in any tokens do not exist in the new version those token will not render
    /// @dev We do not require the number of properties for an reset to match the existing property length, to allow multi-stage property additions (for e.g. when there are more properties than can fit in a single transaction)
    /// @param _names The names of the properties to add
    /// @param _items The items to add to each property
    /// @param _ipfsGroup The IPFS base URI and extension
    function deleteAndRecreateProperties(string[] calldata _names, ItemParam[] calldata _items, IPFSGroup calldata _ipfsGroup) external onlyOwner {
        PropertyIPFSStorage storage $ = _getPropertyIPFSStorage();
        delete $._ipfsData;
        delete $._properties;
        _addProperties(_names, _items, _ipfsGroup);
    }

    function _addProperties(string[] calldata _names, ItemParam[] calldata _items, IPFSGroup calldata _ipfsGroup) internal {
        PropertyIPFSStorage storage $ = _getPropertyIPFSStorage();

        // Cache the existing amount of IPFS data stored
        uint256 dataLength = $._ipfsData.length;

        // Add the IPFS group information
        $._ipfsData.push(_ipfsGroup);

        // Cache the number of existing properties
        uint256 numStoredProperties = $._properties.length;

        // Cache the number of new properties
        uint256 numNewProperties = _names.length;

        // Cache the number of new items
        uint256 numNewItems = _items.length;

        // If this is the first time adding metadata:
        if (numStoredProperties == 0) {
            // Ensure at least one property and one item are included
            if (numNewProperties == 0 || numNewItems == 0) {
                revert ONE_PROPERTY_AND_ITEM_REQUIRED();
            }
        }

        unchecked {
            // Check if not too many items are stored
            if (numStoredProperties + numNewProperties > 15) {
                revert TOO_MANY_PROPERTIES();
            }

            // For each new property:
            for (uint256 i = 0; i < numNewProperties; ++i) {
                // Append storage space
                $._properties.push();

                // Get the new property id
                uint256 propertyId = numStoredProperties + i;

                // Store the property name
                $._properties[propertyId].name = _names[i];

                emit PropertyAdded(propertyId, _names[i]);
            }

            // For each new item:
            for (uint256 i = 0; i < numNewItems; ++i) {
                // Cache the id of the associated property
                uint256 _propertyId = _items[i].propertyId;

                // Offset the id if the item is for a new property
                // Note: Property ids under the hood are offset by 1
                if (_items[i].isNewProperty) {
                    _propertyId += numStoredProperties;
                }

                // Ensure the item is for a valid property
                if (_propertyId >= $._properties.length) {
                    revert INVALID_PROPERTY_SELECTED(_propertyId);
                }

                // Get the pointer to the other items for the property
                Item[] storage items = $._properties[_propertyId].items;

                // Append storage space
                items.push();

                // Get the index of the new item
                // Cannot underflow as the items array length is ensured to be at least 1
                uint256 newItemIndex = items.length - 1;

                // Store the new item
                Item storage newItem = items[newItemIndex];

                // Store the new item's name and reference slot
                newItem.name = _items[i].name;
                newItem.referenceSlot = uint16(dataLength);
            }
        }
    }

    ///                                                          ///
    ///                     ATTRIBUTE GENERATION                 ///
    ///                                                          ///

    /// @notice Generates attributes for a token upon mint
    /// @param _tokenId The ERC-721 token id
    function onMinted(uint256 _tokenId) external override returns (bool) {
        PropertyIPFSStorage storage $ = _getPropertyIPFSStorage();

        // Ensure the caller is the token contract
        if (msg.sender != token()) revert ONLY_TOKEN();

        // Get the pointer to store generated attributes
        uint16[16] storage tokenAttributes = $._attributes[_tokenId];

        // If the attributes are already set from _setAttributes they don't need to be generated
        if (tokenAttributes[0] != 0) return true;

        // Compute some randomness for the token id
        uint256 seed = _generateSeed(_tokenId);

        // Cache the total number of properties available
        uint256 numProperties = $._properties.length;

        if (numProperties == 0) {
            return false;
        }

        // Store the total as reference in the first slot of the token's array of attributes
        tokenAttributes[0] = uint16(numProperties);

        unchecked {
            // For each property:
            for (uint256 i = 0; i < numProperties; ++i) {
                // Get the number of items to choose from
                uint256 numItems = $._properties[i].items.length;

                // Use the token's seed to select an item
                tokenAttributes[i + 1] = uint16(seed % numItems);

                // Adjust the randomness
                seed >>= 16;
            }
        }

        return true;
    }

    /// @notice The atribute at a given token id and attribute id
    /// @param _tokenId The ERC-721 token id
    /// @param _attributeId The attribute id
    function attributes(uint256 _tokenId, uint256 _attributeId) public view returns (uint16) {
        PropertyIPFSStorage storage $ = _getPropertyIPFSStorage();
        return $._attributes[_tokenId][_attributeId];
    }

    /// @notice The properties and query string for a generated token
    /// @param _tokenId The ERC-721 token id
    function getAttributes(uint256 _tokenId) public view returns (string memory resultAttributes, string memory queryString) {
        PropertyIPFSStorage storage $ = _getPropertyIPFSStorage();

        // Get the token's query string
        queryString =
            string.concat("?contractAddress=", Strings.toHexString(uint256(uint160(address(this))), 20), "&tokenId=", Strings.toString(_tokenId));

        // Get the token's generated attributes
        uint16[16] memory tokenAttributes = $._attributes[_tokenId];

        // Cache the number of properties when the token was minted
        uint256 numProperties = tokenAttributes[0];

        // Ensure the given token was minted
        if (numProperties == 0) revert TOKEN_NOT_MINTED(_tokenId);

        // Get an array to store the token's generated attribtues
        MetadataBuilder.JSONItem[] memory arrayAttributesItems = new MetadataBuilder.JSONItem[](numProperties);

        unchecked {
            // For each of the token's properties:
            for (uint256 i = 0; i < numProperties; ++i) {
                // Get its name and list of associated items
                Property memory property = $._properties[i];

                // Get the randomly generated index of the item to select for this token
                uint256 attribute = tokenAttributes[i + 1];

                // Get the associated item data
                Item memory item = property.items[attribute];

                // Store the encoded attributes and query string
                MetadataBuilder.JSONItem memory itemJSON = arrayAttributesItems[i];

                itemJSON.key = property.name;
                itemJSON.value = item.name;
                itemJSON.quote = true;

                queryString = string.concat(queryString, "&images=", _getItemImage(item, property.name));
            }

            resultAttributes = MetadataBuilder.generateJSON(arrayAttributesItems);
        }
    }

    /// @notice Gets the raw attributes for a token
    /// @param _tokenId The ERC-721 token id
    function getRawAttributes(uint256 _tokenId) external view returns (uint16[16] memory) {
        PropertyIPFSStorage storage $ = _getPropertyIPFSStorage();
        return $._attributes[_tokenId];
    }

    /// @notice The IPFS data at a given id
    /// @param _ipfsDataId The IPFS data id
    function ipfsData(uint256 _ipfsDataId) external view returns (IPFSGroup memory) {
        PropertyIPFSStorage storage $ = _getPropertyIPFSStorage();
        return $._ipfsData[_ipfsDataId];
    }

    /// @notice The properties at a given id
    /// @param _propertyId The property id
    function properties(uint256 _propertyId) external view returns (Property memory) {
        PropertyIPFSStorage storage $ = _getPropertyIPFSStorage();
        return $._properties[_propertyId];
    }

    /// @dev Sets the attributes for a token
    function _setAttributes(uint256 _tokenId, uint16[16] calldata _attributes) internal {
        PropertyIPFSStorage storage $ = _getPropertyIPFSStorage();
        $._attributes[_tokenId] = _attributes;
    }

    /// @dev Generates a psuedo-random seed for a token id
    function _generateSeed(uint256 _tokenId) private view returns (uint256) {
        return uint256(keccak256(abi.encode(_tokenId, blockhash(block.number - 1), block.prevrandao, block.timestamp)));
    }

    /// @dev Encodes the reference URI of an item
    function _getItemImage(Item memory _item, string memory _propertyName) private view returns (string memory) {
        PropertyIPFSStorage storage $ = _getPropertyIPFSStorage();

        return UriEncode.uriEncode(
            string(
                abi.encodePacked(
                    $._ipfsData[_item.referenceSlot].baseUri,
                    _propertyName,
                    "/",
                    _item.name,
                    $._ipfsData[_item.referenceSlot].extension
                )
            )
        );
    }

    ///                                                          ///
    ///                            URIs                          ///
    ///                                                          ///

    /// @notice The token URI
    /// @param _tokenId The ERC-721 token id
    function tokenURI(uint256 _tokenId) external view returns (string memory) {
        PropertyIPFSStorage storage $ = _getPropertyIPFSStorage();

        AdditionalTokenProperty[] memory additionalTokenProperties = getAdditionalTokenProperties();

        (string memory _attributes, string memory queryString) = getAttributes(_tokenId);

        MetadataBuilder.JSONItem[] memory items = new MetadataBuilder.JSONItem[](4 + additionalTokenProperties.length);

        items[0] = MetadataBuilder.JSONItem({ key: MetadataJSONKeys.keyName, value: string.concat(_name(), " #", Strings.toString(_tokenId)), quote: true });
        items[1] = MetadataBuilder.JSONItem({ key: MetadataJSONKeys.keyDescription, value: description(), quote: true });
        items[2] = MetadataBuilder.JSONItem({ key: MetadataJSONKeys.keyImage, value: string.concat($._rendererBase, queryString), quote: true });
        items[3] = MetadataBuilder.JSONItem({ key: MetadataJSONKeys.keyProperties, value: _attributes, quote: false });

        for (uint256 i = 0; i < additionalTokenProperties.length; i++) {
            AdditionalTokenProperty memory tokenProperties = additionalTokenProperties[i];
            items[4 + i] = MetadataBuilder.JSONItem({ key: tokenProperties.key, value: tokenProperties.value, quote: tokenProperties.quote });
        }

        return MetadataBuilder.generateEncodedJSON(items);
    }

    ///                                                          ///
    ///                       METADATA SETTINGS                  ///
    ///                                                          ///

    /// @notice The renderer base
    function rendererBase() external view returns (string memory) {
        PropertyIPFSStorage storage $ = _getPropertyIPFSStorage();
        return $._rendererBase;
    }

    /// @notice If the contract implements an interface
    /// @param _interfaceId The interface id
    function supportsInterface(bytes4 _interfaceId) public pure virtual override returns (bool) {
        return super.supportsInterface(_interfaceId) || _interfaceId == type(IPropertyIPFS).interfaceId;
    }

    ///                                                          ///
    ///                       UPDATE SETTINGS                    ///
    ///                                                          ///

    /// @notice Updates the renderer base
    /// @param _newRendererBase The new renderer base
    function updateRendererBase(string memory _newRendererBase) external onlyOwner {
        PropertyIPFSStorage storage $ = _getPropertyIPFSStorage();
        emit RendererBaseUpdated($._rendererBase, _newRendererBase);

        $._rendererBase = _newRendererBase;
    }

    ///                                                          ///
    ///                        METADATA UPGRADE                  ///
    ///                                                          ///

    /// @notice Ensures the caller is authorized to upgrade the contract to a valid implementation
    /// @dev This function is called in UUPS `upgradeTo` & `upgradeToAndCall`
    /// @param _impl The address of the new implementation
    function _authorizeUpgrade(address _impl) internal view virtual override onlyOwner {
        if (!IManager(manager).isRegisteredUpgrade(_getImplementation(), _impl)) revert INVALID_UPGRADE(_impl);
    }
}
