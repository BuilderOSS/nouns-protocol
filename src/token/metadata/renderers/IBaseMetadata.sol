// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

/// @title IBaseMetadata
/// @author Neokry
/// @notice The external Base Metadata errors and functions
interface IBaseMetadata {
    ///                                                          ///
    ///                            EVENTS                        ///
    ///                                                          ///
    /// @notice Emitted when the contract image is updated
    /// @param prevImage The previous contract image
    /// @param newImage The new contract image
    event ContractImageUpdated(string prevImage, string newImage);

    /// @notice Emitted when the collection description is updated
    /// @param prevDescription The previous description
    /// @param newDescription The new description
    event DescriptionUpdated(string prevDescription, string newDescription);

    /// @notice Emitted when the collection uri is updated
    /// @param lastURI The previous URI
    /// @param newURI The new URI
    event WebsiteURIUpdated(string lastURI, string newURI);

    /// @notice Additional token properties have been set
    /// @param _additionalJsonProperties The additional token properties
    event AdditionalTokenPropertiesSet(AdditionalTokenProperty[] _additionalJsonProperties);

    /// @notice This event emits when the metadata of a token is changed.
    /// @param _tokenId The token ID
    event MetadataUpdate(uint256 _tokenId);

    /// @notice This event emits when the metadata of a range of tokens is changed.
    /// @param _fromTokenId The starting token ID
    /// @param _toTokenId The ending token ID
    event BatchMetadataUpdate(uint256 _fromTokenId, uint256 _toTokenId);

    ///                                                          ///
    ///                            ERRORS                        ///
    ///                                                          ///

    /// @dev Reverts if the caller was not the contract manager
    error ONLY_MANAGER();

    /// @dev Reverts if the caller isn't the token contract
    error ONLY_TOKEN();

    /// @dev Reverts if querying attributes for a token not minted
    error TOKEN_NOT_MINTED(uint256 tokenId);

    ///                                                          ///
    ///                            STRUCTS                       ///
    ///                                                          ///

    struct AdditionalTokenProperty {
        string key;
        string value;
        bool quote;
    }

    ///                                                          ///
    ///                           FUNCTIONS                      ///
    ///                                                          ///

    /// @notice Initializes a DAO's token metadata renderer
    /// @param initStrings The encoded token and metadata initialization strings
    /// @param token The associated ERC-721 token address
    function initialize(bytes calldata initStrings, address token) external;

    /// @notice Generates attributes for a token upon mint
    /// @param tokenId The ERC-721 token id
    function onMinted(uint256 tokenId) external returns (bool);

    /// @notice The token URI
    /// @param tokenId The ERC-721 token id
    function tokenURI(uint256 tokenId) external view returns (string memory);

    /// @notice The contract URI
    function contractURI() external view returns (string memory);

    /// @notice The contract image
    function contractImage() external view returns (string memory);

    /// @notice The collection description
    function description() external view returns (string memory);

    /// @notice The collection description
    function projectURI() external view returns (string memory);

    /// @notice The associated ERC-721 token
    function token() external view returns (address);

    /// @notice Get metadata owner address
    function owner() external view returns (address);

    /// @notice If the contract implements an interface
    /// @param _interfaceId The interface id
    function supportsInterface(bytes4 _interfaceId) external pure returns (bool);
}
