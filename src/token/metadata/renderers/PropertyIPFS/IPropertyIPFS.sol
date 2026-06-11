// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

/// @title IPropertyIPFS
/// @author Neokry
/// @notice The external functions and errors for the property IPFS metadata renderer
/// @custom:repo github.com/neokry/builder-renderers
interface IPropertyIPFS {
    ///                                                          ///
    ///                            STRUCTS                       ///
    ///                                                          ///

    struct ItemParam {
        uint256 propertyId;
        string name;
        bool isNewProperty;
    }

    struct IPFSGroup {
        string baseUri;
        string extension;
    }

    struct Item {
        uint16 referenceSlot;
        string name;
    }

    struct Property {
        string name;
        Item[] items;
    }

    ///                                                          ///
    ///                            EVENTS                        ///
    ///                                                          ///

    /// @notice Emitted when a property is added
    event PropertyAdded(uint256 id, string name);

    /// @notice Emitted when the renderer base is updated
    event RendererBaseUpdated(string prevRendererBase, string newRendererBase);

    ///                                                          ///
    ///                            ERRORS                        ///
    ///                                                          ///

    /// @dev Reverts if the founder does not include both a property and item during the initial artwork upload
    error ONE_PROPERTY_AND_ITEM_REQUIRED();

    /// @dev Reverts if an item is added for a non-existent property
    error INVALID_PROPERTY_SELECTED(uint256 selectedPropertyId);

    ///
    error TOO_MANY_PROPERTIES();

    ///                                                          ///
    ///                           FUNCTIONS                      ///
    ///                                                          ///

    /// @notice Adds properties and/or items to be pseudo-randomly chosen from during token minting
    /// @param names The names of the properties to add
    /// @param items The items to add to each property
    /// @param ipfsGroup The IPFS base URI and extension
    function addProperties(string[] calldata names, ItemParam[] calldata items, IPFSGroup calldata ipfsGroup) external;

    /// @notice The number of properties
    function propertiesCount() external view returns (uint256);

    /// @notice The number of items in a property
    /// @param propertyId The property id
    function itemsCount(uint256 propertyId) external view returns (uint256);

    /// @notice The properties and query string for a generated token
    /// @param tokenId The ERC-721 token id
    function getAttributes(uint256 tokenId) external view returns (string memory resultAttributes, string memory queryString);

    /// @notice Gets the raw attributes for a token
    /// @param _tokenId The ERC-721 token id
    function getRawAttributes(uint256 _tokenId) external view returns (uint16[16] memory attributes);

    /// @notice The renderer base
    function rendererBase() external view returns (string memory);
}
