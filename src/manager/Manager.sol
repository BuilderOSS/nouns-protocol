// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import { UUPS } from "../lib/proxy/UUPS.sol";
import { Ownable } from "../lib/utils/Ownable.sol";
import { ERC1967Proxy } from "../lib/proxy/ERC1967Proxy.sol";

import { ManagerStorageV1 } from "./storage/ManagerStorageV1.sol";
import { IManager } from "./IManager.sol";
import { IToken } from "../token/IToken.sol";
import { IBaseMetadata } from "../token/metadata/interfaces/IBaseMetadata.sol";
import { IAuction } from "../auction/IAuction.sol";
import { ITreasury } from "../governance/treasury/ITreasury.sol";
import { IGovernor } from "../governance/governor/IGovernor.sol";
import { IOwnable } from "../lib/interfaces/IOwnable.sol";
import { IDAOFactory } from "../factory/IDAOFactory.sol";

import { VersionedContract } from "../VersionedContract.sol";
import { IVersionedContract } from "../lib/interfaces/IVersionedContract.sol";

/// @title Manager
/// @author Neokry & Rohan Kulkarni
/// @custom:repo github.com/ourzora/nouns-protocol
/// @notice The DAO deployer and upgrade manager
contract Manager is IManager, VersionedContract, UUPS, Ownable, ManagerStorageV1 {
    bytes32 internal constant TOKEN_SALT_LABEL = keccak256("TOKEN");
    bytes32 internal constant METADATA_SALT_LABEL = keccak256("METADATA");
    bytes32 internal constant AUCTION_SALT_LABEL = keccak256("AUCTION");
    bytes32 internal constant TREASURY_SALT_LABEL = keccak256("TREASURY");
    bytes32 internal constant GOVERNOR_SALT_LABEL = keccak256("GOVERNOR");

    error IMPLEMENTATION_REQUIRED();
    error INVALID_IMPLEMENTATION();
    error DAO_FACTORY_NOT_DEPLOYED();
    error FACTORY_DEPLOYMENT_FAILED();

    ///                                                          ///
    ///                          IMMUTABLES                      ///
    ///                                                          ///
    /// @notice The token implementation address
    address public immutable tokenImpl;

    /// @notice The metadata renderer implementation address
    address public immutable metadataImpl;

    /// @notice The auction house implementation address
    address public immutable auctionImpl;

    /// @notice The treasury implementation address
    address public immutable treasuryImpl;

    /// @notice The governor implementation address
    address public immutable governorImpl;

    /// @notice The address to send Builder DAO rewards to
    address public immutable builderRewardsRecipient;

    /// @notice The DAOFactory address for canonical deterministic deployments
    /// @dev DAOFactory acts as the canonical deployer for all DAO proxies, ensuring cross-chain
    ///      deterministic addresses regardless of Manager address. The factory should be deployed
    ///      at the same address on all chains using CREATE3Factory.
    address public immutable daoFactory;

    ///                                                          ///
    ///                          CONSTRUCTOR                     ///
    ///                                                          ///

    constructor(
        address _tokenImpl,
        address _metadataImpl,
        address _auctionImpl,
        address _treasuryImpl,
        address _governorImpl,
        address _builderRewardsRecipient,
        address _daoFactory
    ) payable initializer {
        // Validate that DAOFactory is deployed
        _validateDAOFactory(_daoFactory);

        tokenImpl = _tokenImpl;
        metadataImpl = _metadataImpl;
        auctionImpl = _auctionImpl;
        treasuryImpl = _treasuryImpl;
        governorImpl = _governorImpl;
        builderRewardsRecipient = _builderRewardsRecipient;
        daoFactory = _daoFactory;
    }

    ///                                                          ///
    ///                          INITIALIZER                     ///
    ///                                                          ///

    /// @notice Initializes ownership of the manager contract
    /// @param _newOwner The owner address to set (will be transferred to the Builder DAO once its deployed)
    function initialize(address _newOwner) external initializer {
        // Ensure an owner is specified
        if (_newOwner == address(0)) revert ADDRESS_ZERO();

        // Set the contract owner
        __Ownable_init(_newOwner);
    }

    ///                                                          ///
    ///                           DAO DEPLOY                     ///
    ///                                                          ///

    /// @notice Deprecated: deploys a DAO with custom token, auction, and governance settings for backward compatibility only.
    /// @dev New integrations should use deterministic deployment with explicit ImplementationParams.
    /// @param _founderParams The DAO founders
    /// @param _tokenParams The ERC-721 token settings
    /// @param _auctionParams The auction settings
    /// @param _govParams The governance settings
    /// @return token The deployed token address
    /// @return metadata The deployed metadata renderer address
    /// @return auction The deployed auction address
    /// @return treasury The deployed treasury address
    /// @return governor The deployed governor address
    function deploy(
        FounderParams[] calldata _founderParams,
        TokenParams calldata _tokenParams,
        AuctionParams calldata _auctionParams,
        GovParams calldata _govParams
    ) external returns (address token, address metadata, address auction, address treasury, address governor) {
        return _deploy(_founderParams, _tokenParams, _auctionParams, _govParams);
    }

    /// @notice Deploys a DAO with deterministic contract addresses using CREATE2 and explicit implementation addresses
    /// @param _founderParams The DAO founders
    /// @param _tokenParams The ERC-721 token settings
    /// @param _auctionParams The auction settings
    /// @param _govParams The governance settings
    /// @param _deploySalt The base salt used to derive per-contract salts
    /// @param _implementationParams The explicit implementation bundle used for deterministic deployment
    /// @return token The deployed token address
    /// @return metadata The deployed metadata renderer address
    /// @return auction The deployed auction address
    /// @return treasury The deployed treasury address
    /// @return governor The deployed governor address
    function deployDeterministic(
        FounderParams[] calldata _founderParams,
        TokenParams calldata _tokenParams,
        AuctionParams calldata _auctionParams,
        GovParams calldata _govParams,
        bytes32 _deploySalt,
        ImplementationParams calldata _implementationParams
    ) external returns (address token, address metadata, address auction, address treasury, address governor) {
        // Validate that DAOFactory is deployed
        _validateDAOFactory(daoFactory);

        _validateImplementationParams(_implementationParams);

        return _deployDeterministic(_founderParams, _tokenParams, _auctionParams, _govParams, _deploySalt, _implementationParams);
    }

    /// @notice Predicts deterministic DAO addresses using an explicit implementation bundle
    /// @param _deployer The deployer address used to namespace the deterministic salt
    /// @param _deploySalt The base salt used to derive per-contract salts
    /// @param _implementationParams The explicit implementation bundle used for deterministic prediction
    /// @return token The predicted token address
    /// @return metadata The predicted metadata renderer address
    /// @return auction The predicted auction address
    /// @return treasury The predicted treasury address
    /// @return governor The predicted governor address
    function predictDeterministicAddresses(address _deployer, bytes32 _deploySalt, ImplementationParams calldata _implementationParams)
        external
        view
        returns (address token, address metadata, address auction, address treasury, address governor)
    {
        _validateImplementationParams(_implementationParams);

        return _predictDeterministicAddresses(_deployer, _deploySalt, _implementationParams);
    }

    ///                                                          ///
    ///                          SET METADATA                    ///
    ///                                                          ///

    /// @notice Set a new metadata renderer
    /// @param _token The token address
    /// @param _newRendererImpl new renderer address to use
    /// @param _setupRenderer data to setup new renderer with
    /// @return metadata The deployed metadata renderer address
    function setMetadataRenderer(address _token, address _newRendererImpl, bytes memory _setupRenderer) external returns (address metadata) {
        if (msg.sender != IOwnable(_token).owner()) {
            revert ONLY_TOKEN_OWNER();
        }

        metadata = address(new ERC1967Proxy(_newRendererImpl, ""));
        daoAddressesByToken[_token].metadata = metadata;

        if (_setupRenderer.length > 0) {
            IBaseMetadata(metadata).initialize(_setupRenderer, _token);
        }

        IToken(_token).setMetadataRenderer(IBaseMetadata(metadata));

        emit MetadataRendererUpdated({ sender: msg.sender, renderer: metadata });
    }

    ///                                                          ///
    ///                         DAO ADDRESSES                    ///
    ///                                                          ///

    /// @notice A DAO's contract addresses from its token
    /// @param _token The ERC-721 token address
    /// @return metadata Metadata deployed address
    /// @return auction Auction deployed address
    /// @return treasury Treasury deployed address
    /// @return governor Governor deployed address
    function getAddresses(address _token) public view returns (address metadata, address auction, address treasury, address governor) {
        DAOAddresses storage addresses = daoAddressesByToken[_token];

        metadata = addresses.metadata;
        auction = addresses.auction;
        treasury = addresses.treasury;
        governor = addresses.governor;
    }

    ///                                                          ///
    ///                          DAO UPGRADES                    ///
    ///                                                          ///

    /// @notice If an implementation is registered by the Builder DAO as an optional upgrade
    /// @param _baseImpl The base implementation address
    /// @param _upgradeImpl The upgrade implementation address
    function isRegisteredUpgrade(address _baseImpl, address _upgradeImpl) external view returns (bool) {
        return isUpgrade[_baseImpl][_upgradeImpl];
    }

    /// @notice Called by the Builder DAO to offer implementation upgrades for created DAOs
    /// @param _baseImpl The base implementation address
    /// @param _upgradeImpl The upgrade implementation address
    function registerUpgrade(address _baseImpl, address _upgradeImpl) external onlyOwner {
        isUpgrade[_baseImpl][_upgradeImpl] = true;

        emit UpgradeRegistered(_baseImpl, _upgradeImpl);
    }

    /// @notice Called by the Builder DAO to remove an upgrade
    /// @param _baseImpl The base implementation address
    /// @param _upgradeImpl The upgrade implementation address
    function removeUpgrade(address _baseImpl, address _upgradeImpl) external onlyOwner {
        delete isUpgrade[_baseImpl][_upgradeImpl];

        emit UpgradeRemoved(_baseImpl, _upgradeImpl);
    }

    /// @notice Safely get the contract version of a target contract.
    /// @param target The ERC-721 token address
    /// @dev Assume `target` is a contract
    /// @return Contract version if found, empty string if not.
    function _safeGetVersion(address target) internal pure returns (string memory) {
        try IVersionedContract(target).contractVersion() returns (string memory version) {
            return version;
        } catch {
            return "";
        }
    }

    /// @notice Safely get the contract version of all DAO contracts given a token address.
    /// @param token The ERC-721 token address
    /// @return Contract versions if found, empty string if not.
    function getDAOVersions(address token) external view returns (DAOVersionInfo memory) {
        (address metadata, address auction, address treasury, address governor) = getAddresses(token);
        return DAOVersionInfo({
            token: _safeGetVersion(token),
            metadata: _safeGetVersion(metadata),
            auction: _safeGetVersion(auction),
            treasury: _safeGetVersion(treasury),
            governor: _safeGetVersion(governor)
        });
    }

    /// @notice Returns the latest implementation versions
    function getLatestVersions() external view returns (DAOVersionInfo memory) {
        return DAOVersionInfo({
            token: _safeGetVersion(tokenImpl),
            metadata: _safeGetVersion(metadataImpl),
            auction: _safeGetVersion(auctionImpl),
            treasury: _safeGetVersion(treasuryImpl),
            governor: _safeGetVersion(governorImpl)
        });
    }

    ///                                                          ///
    ///                         MANAGER UPGRADE                  ///
    ///                                                          ///

    /// @notice Ensures the caller is authorized to upgrade the contract
    /// @dev This function is called in `upgradeTo` & `upgradeToAndCall`
    /// @param _newImpl The new implementation address
    function _authorizeUpgrade(address _newImpl) internal override onlyOwner { }

    /// @notice Initializes all DAO contracts with provided parameters
    /// @dev Shared initialization logic used by both legacy and deterministic deployment
    /// @param token The deployed token proxy address
    /// @param metadata The deployed metadata renderer proxy address
    /// @param auction The deployed auction proxy address
    /// @param treasury The deployed treasury proxy address
    /// @param governor The deployed governor proxy address
    /// @param founder The founder address who will receive initial ownership
    /// @param _founderParams The DAO founders
    /// @param _tokenParams The ERC-721 token settings
    /// @param _auctionParams The auction settings
    /// @param _govParams The governance settings
    function _initializeDAO(
        address token,
        address metadata,
        address auction,
        address treasury,
        address governor,
        address founder,
        FounderParams[] calldata _founderParams,
        TokenParams calldata _tokenParams,
        AuctionParams calldata _auctionParams,
        GovParams calldata _govParams
    ) internal {
        IToken(token)
            .initialize({
                founders: _founderParams,
                initStrings: _tokenParams.initStrings,
                reservedUntilTokenId: _tokenParams.reservedUntilTokenId,
                metadataRenderer: metadata,
                auction: auction,
                initialOwner: founder
            });
        IBaseMetadata(metadata).initialize({ initStrings: _tokenParams.initStrings, token: token });
        IAuction(auction)
            .initialize({
                token: token,
                founder: founder,
                treasury: treasury,
                duration: _auctionParams.duration,
                reservePrice: _auctionParams.reservePrice,
                founderRewardRecipent: _auctionParams.founderRewardRecipent,
                founderRewardBps: _auctionParams.founderRewardBps
            });
        ITreasury(treasury).initialize({ governor: governor, timelockDelay: _govParams.timelockDelay });
        IGovernor(governor)
            .initialize({
                treasury: treasury,
                token: token,
                vetoer: _govParams.vetoer,
                votingDelay: _govParams.votingDelay,
                votingPeriod: _govParams.votingPeriod,
                proposalThresholdBps: _govParams.proposalThresholdBps,
                quorumThresholdBps: _govParams.quorumThresholdBps
            });

        emit DAODeployed({ token: token, metadata: metadata, auction: auction, treasury: treasury, governor: governor });
    }

    /// @notice Internal function for legacy DAO deployment
    /// @dev Uses non-deterministic salt based on token address for backward compatibility
    /// @param _founderParams The DAO founders
    /// @param _tokenParams The ERC-721 token settings
    /// @param _auctionParams The auction settings
    /// @param _govParams The governance settings
    /// @return token The deployed token address
    /// @return metadata The deployed metadata renderer address
    /// @return auction The deployed auction address
    /// @return treasury The deployed treasury address
    /// @return governor The deployed governor address
    function _deploy(
        FounderParams[] calldata _founderParams,
        TokenParams calldata _tokenParams,
        AuctionParams calldata _auctionParams,
        GovParams calldata _govParams
    ) internal returns (address token, address metadata, address auction, address treasury, address governor) {
        address founder = _founderParams[0].wallet;
        if (founder == address(0)) revert FOUNDER_REQUIRED();

        (token, metadata, auction, treasury, governor) = _deployLegacyProxies(_getMetadataImpl(_tokenParams));

        daoAddressesByToken[token] = DAOAddresses({ metadata: metadata, auction: auction, treasury: treasury, governor: governor });

        _initializeDAO(token, metadata, auction, treasury, governor, founder, _founderParams, _tokenParams, _auctionParams, _govParams);
    }

    /// @notice Internal function for deterministic DAO deployment using CREATE2
    /// @dev Deploys all contracts with predictable addresses using provided implementation bundle
    /// @param _founderParams The DAO founders
    /// @param _tokenParams The ERC-721 token settings
    /// @param _auctionParams The auction settings
    /// @param _govParams The governance settings
    /// @param _deploySalt The base salt used to derive per-contract salts
    /// @param _implementationParams The explicit implementation bundle
    /// @return token The deployed token address
    /// @return metadata The deployed metadata renderer address
    /// @return auction The deployed auction address
    /// @return treasury The deployed treasury address
    /// @return governor The deployed governor address
    function _deployDeterministic(
        FounderParams[] calldata _founderParams,
        TokenParams calldata _tokenParams,
        AuctionParams calldata _auctionParams,
        GovParams calldata _govParams,
        bytes32 _deploySalt,
        ImplementationParams calldata _implementationParams
    ) internal returns (address token, address metadata, address auction, address treasury, address governor) {
        address founder = _founderParams[0].wallet;
        if (founder == address(0)) revert FOUNDER_REQUIRED();

        (token, metadata, auction, treasury, governor) = _deployDeterministicProxies(msg.sender, _deploySalt, _implementationParams);

        daoAddressesByToken[token] = DAOAddresses({ metadata: metadata, auction: auction, treasury: treasury, governor: governor });

        emit DAODeployedDeterministic(msg.sender, _deploySalt, token, metadata, auction, treasury, governor);

        _initializeDAO(token, metadata, auction, treasury, governor, founder, _founderParams, _tokenParams, _auctionParams, _govParams);
    }

    /// @notice Deploys all DAO proxies using legacy non-deterministic pattern
    /// @dev Token is deployed first without salt, then its address (shifted left 96 bits) becomes the salt for other contracts.
    ///      The bit shift (<< 96) moves the 160-bit address into the upper portion of the 256-bit salt,
    ///      leaving lower bits as zeros. This ensures a unique salt per deployment while maintaining backward compatibility.
    ///      Uses CREATE for token (no salt) and CREATE2 for other contracts (with salt), NOT CREATE3.
    /// @param _metadataImplToUse The metadata renderer implementation to use (can be custom or default)
    /// @return token The deployed token proxy address
    /// @return metadata The deployed metadata renderer proxy address
    /// @return auction The deployed auction proxy address
    /// @return treasury The deployed treasury proxy address
    /// @return governor The deployed governor proxy address
    function _deployLegacyProxies(address _metadataImplToUse)
        internal
        returns (address token, address metadata, address auction, address treasury, address governor)
    {
        // Deploy token using CREATE (no salt) - non-deterministic
        token = address(new ERC1967Proxy(tokenImpl, ""));

        // Use the token address to precompute the DAO's remaining addresses
        bytes32 salt = bytes32(uint256(uint160(token)) << 96);

        // Deploy remaining DAO contracts using CREATE2 (with salt) - deterministic based on token address
        metadata = address(new ERC1967Proxy{ salt: salt }(_metadataImplToUse, ""));
        auction = address(new ERC1967Proxy{ salt: salt }(auctionImpl, ""));
        treasury = address(new ERC1967Proxy{ salt: salt }(treasuryImpl, ""));
        governor = address(new ERC1967Proxy{ salt: salt }(governorImpl, ""));
    }

    /// @notice Deploys all DAO proxies with deterministic addresses using CREATE2
    /// @dev Each contract uses a namespaced salt derived from deployer address, base salt, and contract-specific label.
    ///      This prevents collisions across deployers and ensures unique addresses per contract type.
    /// @param _deployer The address initiating the deployment (used in salt derivation to prevent cross-deployer collisions)
    /// @param _deploySalt The base salt provided by caller (should be unique per DAO deployment)
    /// @param _implementationParams The implementation addresses to use for each proxy
    /// @return token The deployed token proxy address
    /// @return metadata The deployed metadata renderer proxy address
    /// @return auction The deployed auction proxy address
    /// @return treasury The deployed treasury proxy address
    /// @return governor The deployed governor proxy address
    function _deployDeterministicProxies(address _deployer, bytes32 _deploySalt, ImplementationParams calldata _implementationParams)
        internal
        returns (address token, address metadata, address auction, address treasury, address governor)
    {
        token = _deployProxy(_implementationParams.token, _deriveSalt(_deployer, _deploySalt, TOKEN_SALT_LABEL));
        metadata = _deployProxy(_implementationParams.metadataRenderer, _deriveSalt(_deployer, _deploySalt, METADATA_SALT_LABEL));
        auction = _deployProxy(_implementationParams.auction, _deriveSalt(_deployer, _deploySalt, AUCTION_SALT_LABEL));
        treasury = _deployProxy(_implementationParams.treasury, _deriveSalt(_deployer, _deploySalt, TREASURY_SALT_LABEL));
        governor = _deployProxy(_implementationParams.governor, _deriveSalt(_deployer, _deploySalt, GOVERNOR_SALT_LABEL));
    }

    /// @notice Returns the metadata renderer implementation to use
    /// @dev Allows custom renderer or defaults to the Manager's immutable metadataImpl
    /// @param _tokenParams The token parameters containing optional custom renderer
    /// @return The metadata renderer implementation address to use
    function _getMetadataImpl(TokenParams calldata _tokenParams) internal view returns (address) {
        return _tokenParams.metadataRenderer != address(0) ? _tokenParams.metadataRenderer : metadataImpl;
    }

    /// @notice Predicts deterministic DAO contract addresses without deploying
    /// @dev Uses same salt derivation as _deployDeterministicProxies for accurate prediction
    /// @param _deployer The address that will deploy (affects salt calculation)
    /// @param _deploySalt The base salt to be used
    /// @param _implementationParams The implementation addresses
    /// @return token The predicted token address
    /// @return metadata The predicted metadata renderer address
    /// @return auction The predicted auction address
    /// @return treasury The predicted treasury address
    /// @return governor The predicted governor address
    function _predictDeterministicAddresses(address _deployer, bytes32 _deploySalt, ImplementationParams calldata _implementationParams)
        internal
        view
        returns (address token, address metadata, address auction, address treasury, address governor)
    {
        token = _predictProxyAddress(_implementationParams.token, _deriveSalt(_deployer, _deploySalt, TOKEN_SALT_LABEL));
        metadata = _predictProxyAddress(_implementationParams.metadataRenderer, _deriveSalt(_deployer, _deploySalt, METADATA_SALT_LABEL));
        auction = _predictProxyAddress(_implementationParams.auction, _deriveSalt(_deployer, _deploySalt, AUCTION_SALT_LABEL));
        treasury = _predictProxyAddress(_implementationParams.treasury, _deriveSalt(_deployer, _deploySalt, TREASURY_SALT_LABEL));
        governor = _predictProxyAddress(_implementationParams.governor, _deriveSalt(_deployer, _deploySalt, GOVERNOR_SALT_LABEL));
    }

    /// @notice Validates that implementation parameters contain valid contract addresses
    /// @dev Checks for non-zero addresses and verifies bytecode exists at each address
    /// @param _implementationParams The implementation bundle to validate
    function _validateImplementationParams(ImplementationParams calldata _implementationParams) internal view {
        if (
            _implementationParams.token == address(0) || _implementationParams.metadataRenderer == address(0)
                || _implementationParams.auction == address(0) || _implementationParams.treasury == address(0)
                || _implementationParams.governor == address(0)
        ) {
            revert IMPLEMENTATION_REQUIRED();
        }

        // Verify each address contains bytecode (is a contract)
        if (
            _implementationParams.token.code.length == 0 || _implementationParams.metadataRenderer.code.length == 0
                || _implementationParams.auction.code.length == 0 || _implementationParams.treasury.code.length == 0
                || _implementationParams.governor.code.length == 0
        ) {
            revert INVALID_IMPLEMENTATION();
        }
    }

    /// @notice Validates that the DAOFactory is deployed
    /// @dev Ensures the factory exists before attempting deterministic deployments
    ///      The factory must have bytecode at daoFactory address.
    ///      Access control is enforced by the DAOFactory itself via its manager immutable.
    /// @param _daoFactory The DAOFactory address to validate
    function _validateDAOFactory(address _daoFactory) internal view {
        if (_daoFactory.code.length == 0) {
            revert DAO_FACTORY_NOT_DEPLOYED();
        }
    }

    /// @notice Predicts the address of a CREATE3-deployed proxy via DAOFactory
    /// @dev Delegates to DAOFactory's predictAddress function for accurate predictions
    ///      CRITICAL: Address depends ONLY on (DAOFactory, salt), NOT on Manager address or bytecode
    ///      This enables cross-chain determinism - same DAOFactory + salt = same address
    ///      regardless of which Manager is calling it or what the implementation address is
    /// @param _implementation The implementation address (NOT used in address calculation, only for compatibility)
    /// @param _salt The salt to use for CREATE3 deployment
    /// @return The predicted proxy address
    function _predictProxyAddress(address _implementation, bytes32 _salt) internal view returns (address) {
        // Use DAOFactory's prediction function - DAOFactory is the canonical deployer
        // This ensures all Managers produce identical predictions
        return IDAOFactory(daoFactory).predictAddress(_salt);
    }

    /// @notice Deploys an ERC1967 proxy without salt (non-deterministic)
    /// @dev Used by legacy deployment for the initial token contract
    /// @param _implementation The implementation address
    /// @return The deployed proxy address
    function _deployProxy(address _implementation) internal returns (address) {
        return address(new ERC1967Proxy(_implementation, ""));
    }

    /// @notice Deploys an ERC1967 proxy with CREATE3 salt (deterministic) via DAOFactory
    /// @dev Uses DAOFactory as canonical deployer for bytecode-independent cross-chain determinism
    ///      This enables identical DAO addresses across chains REGARDLESS of Manager or implementation addresses
    ///      DAOFactory interface: deployProxy(bytes32 salt, bytes memory creationCode) returns (address)
    /// @param _implementation The implementation address
    /// @param _salt The CREATE3 salt
    /// @return The deployed proxy address
    function _deployProxy(address _implementation, bytes32 _salt) internal returns (address) {
        // Build the initialization code for ERC1967Proxy
        bytes memory creationCode = abi.encodePacked(type(ERC1967Proxy).creationCode, abi.encode(_implementation, ""));

        // Deploy via DAOFactory - this is the canonical deployer for all DAO proxies
        address deployed = IDAOFactory(daoFactory).deployProxy(_salt, creationCode);

        // Verify the deployed address matches our prediction
        address predicted = _predictProxyAddress(_implementation, _salt);
        if (deployed != predicted) revert FACTORY_DEPLOYMENT_FAILED();

        // Verify contract was actually deployed
        if (deployed.code.length == 0) revert FACTORY_DEPLOYMENT_FAILED();

        return deployed;
    }

    /// @notice Derives a unique salt for CREATE3 deployment by combining deployer, user salt, and contract label
    /// @dev This three-part derivation prevents collisions:
    ///      - _deployer prevents different users from interfering with each other's deployments
    ///      - _deploySalt allows same user to deploy multiple DAOs with different addresses
    ///      - _label ensures each contract type gets a unique salt within the same deployment
    ///      SECURITY: Deployers should use unique _deploySalt values to avoid collisions
    ///      Works identically for CREATE2 and CREATE3 - only the address calculation differs
    /// @param _deployer The address initiating deployment (typically msg.sender)
    /// @param _deploySalt The base salt chosen by the deployer
    /// @param _label The contract-specific label (TOKEN_SALT_LABEL, METADATA_SALT_LABEL, etc.)
    /// @return The derived salt for CREATE3 deployment
    function _deriveSalt(address _deployer, bytes32 _deploySalt, bytes32 _label) internal pure returns (bytes32) {
        return keccak256(abi.encode(_deployer, _deploySalt, _label));
    }
}
