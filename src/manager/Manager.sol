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

    ///                                                          ///
    ///                          CONSTRUCTOR                     ///
    ///                                                          ///

    constructor(
        address _tokenImpl,
        address _metadataImpl,
        address _auctionImpl,
        address _treasuryImpl,
        address _governorImpl,
        address _builderRewardsRecipient
    ) payable initializer {
        tokenImpl = _tokenImpl;
        metadataImpl = _metadataImpl;
        auctionImpl = _auctionImpl;
        treasuryImpl = _treasuryImpl;
        governorImpl = _governorImpl;
        builderRewardsRecipient = _builderRewardsRecipient;
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
        _validateImplementationParams(_implementationParams);

        return _deployDeterministic(
            _founderParams, _tokenParams, _auctionParams, _govParams, _deploySalt, _implementationParams
        );
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

    function _deploy(
        FounderParams[] calldata _founderParams,
        TokenParams calldata _tokenParams,
        AuctionParams calldata _auctionParams,
        GovParams calldata _govParams
    )
        internal
        returns (address token, address metadata, address auction, address treasury, address governor)
    {
        address founder = _founderParams[0].wallet;
        if (founder == address(0)) revert FOUNDER_REQUIRED();

        (token, metadata, auction, treasury, governor) = _deployLegacyProxies(_getMetadataImpl(_tokenParams));

        daoAddressesByToken[token] = DAOAddresses({ metadata: metadata, auction: auction, treasury: treasury, governor: governor });

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

    function _deployDeterministic(
        FounderParams[] calldata _founderParams,
        TokenParams calldata _tokenParams,
        AuctionParams calldata _auctionParams,
        GovParams calldata _govParams,
        bytes32 _deploySalt,
        ImplementationParams calldata _implementationParams
    )
        internal
        returns (address token, address metadata, address auction, address treasury, address governor)
    {
        address founder = _founderParams[0].wallet;
        if (founder == address(0)) revert FOUNDER_REQUIRED();

        (token, metadata, auction, treasury, governor) = _deployDeterministicProxies(msg.sender, _deploySalt, _implementationParams);

        daoAddressesByToken[token] = DAOAddresses({ metadata: metadata, auction: auction, treasury: treasury, governor: governor });

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

    function _deployLegacyProxies(address _metadataImplToUse)
        internal
        returns (address token, address metadata, address auction, address treasury, address governor)
    {
        token = _deployProxy(tokenImpl);

        bytes32 salt = bytes32(uint256(uint160(token)) << 96);

        metadata = _deployProxy(_metadataImplToUse, salt);
        auction = _deployProxy(auctionImpl, salt);
        treasury = _deployProxy(treasuryImpl, salt);
        governor = _deployProxy(governorImpl, salt);
    }

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

    function _getMetadataImpl(TokenParams calldata _tokenParams) internal view returns (address) {
        return _tokenParams.metadataRenderer != address(0) ? _tokenParams.metadataRenderer : metadataImpl;
    }

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

    function _validateImplementationParams(ImplementationParams calldata _implementationParams) internal pure {
        if (
            _implementationParams.token == address(0) || _implementationParams.metadataRenderer == address(0)
                || _implementationParams.auction == address(0) || _implementationParams.treasury == address(0)
                || _implementationParams.governor == address(0)
        ) {
            revert IMPLEMENTATION_REQUIRED();
        }
    }

    function _predictProxyAddress(address _implementation, bytes32 _salt) internal view returns (address) {
        bytes memory creationCode = abi.encodePacked(type(ERC1967Proxy).creationCode, abi.encode(_implementation, ""));
        bytes32 hash = keccak256(abi.encodePacked(bytes1(0xff), address(this), _salt, keccak256(creationCode)));
        return address(uint160(uint256(hash)));
    }

    function _deployProxy(address _implementation) internal returns (address) {
        return address(new ERC1967Proxy(_implementation, ""));
    }

    function _deployProxy(address _implementation, bytes32 _salt) internal returns (address) {
        return address(new ERC1967Proxy{ salt: _salt }(_implementation, ""));
    }

    function _deriveSalt(address _deployer, bytes32 _deploySalt, bytes32 _label) internal pure returns (bytes32) {
        return keccak256(abi.encode(_deployer, _deploySalt, _label));
    }
}
