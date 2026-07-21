// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import { IUUPS } from "../lib/interfaces/IUUPS.sol";
import { IOwnable } from "../lib/interfaces/IOwnable.sol";

/// @title IManager
/// @author Rohan Kulkarni
/// @notice The external Manager events, errors, structs and functions
interface IManager is IUUPS, IOwnable {
    ///                                                          ///
    ///                            EVENTS                        ///
    ///                                                          ///
    /// @notice Emitted when a DAO is deployed
    /// @param token The ERC-721 token address
    /// @param metadata The metadata renderer address
    /// @param auction The auction address
    /// @param treasury The treasury address
    /// @param governor The governor address
    event DAODeployed(address token, address metadata, address auction, address treasury, address governor);

    /// @notice Emitted when a DAO is deployed deterministically
    /// @param deployer The deployer address
    /// @param deploySalt The base salt used for deterministic deployment
    /// @param token The ERC-721 token address
    /// @param metadata The metadata renderer address
    /// @param auction The auction address
    /// @param treasury The treasury address
    /// @param governor The governor address
    event DAODeployedDeterministic(
        address indexed deployer, bytes32 indexed deploySalt, address token, address metadata, address auction, address treasury, address governor
    );

    /// @notice Emitted when an upgrade is registered by the Builder DAO
    /// @param baseImpl The base implementation address
    /// @param upgradeImpl The upgrade implementation address
    event UpgradeRegistered(address baseImpl, address upgradeImpl);

    /// @notice Emitted when an upgrade is unregistered by the Builder DAO
    /// @param baseImpl The base implementation address
    /// @param upgradeImpl The upgrade implementation address
    event UpgradeRemoved(address baseImpl, address upgradeImpl);

    /// @notice Event emitted when metadata renderer is updated.
    /// @param sender address of the updater
    /// @param renderer new metadata renderer address
    event MetadataRendererUpdated(address sender, address renderer);

    ///                                                          ///
    ///                            ERRORS                        ///
    ///                                                          ///

    /// @dev Reverts if at least one founder is not provided upon deploy
    error FOUNDER_REQUIRED();

    /// @dev Reverts if caller is not the token owner
    error ONLY_TOKEN_OWNER();

    ///                                                          ///
    ///                            STRUCTS                       ///
    ///                                                          ///

    /// @notice The founder parameters
    /// @param wallet The wallet address
    /// @param ownershipPct The percent ownership of the token
    /// @param vestExpiry The timestamp that vesting expires
    struct FounderParams {
        address wallet;
        uint256 ownershipPct;
        uint256 vestExpiry;
    }

    /// @notice DAO Version Information information struct
    struct DAOVersionInfo {
        string token;
        string metadata;
        string auction;
        string treasury;
        string governor;
    }

    /// @notice The ERC-721 token parameters
    /// @param initStrings The encoded token name, symbol, collection description, collection image uri, renderer base uri
    /// @param metadataRenderer Optional custom metadata renderer (uses Manager's default if address(0))
    /// @param reservedUntilTokenId The tokenId that a DAO's auctions will start at
    struct TokenParams {
        bytes initStrings;
        address metadataRenderer;
        uint256 reservedUntilTokenId;
    }

    /// @notice The auction parameters
    /// @param reservePrice The reserve price of each auction
    /// @param duration The duration of each auction
    /// @param founderRewardRecipent The address to send founder rewards to
    /// @param founderRewardBps Percent of the auction bid in BPS to send to the founder recipient
    struct AuctionParams {
        uint256 reservePrice;
        uint256 duration;
        address founderRewardRecipent;
        uint16 founderRewardBps;
    }

    /// @notice The governance parameters
    /// @param timelockDelay The time delay to execute a queued transaction
    /// @param votingDelay The time delay to vote on a created proposal
    /// @param votingPeriod The time period to vote on a proposal
    /// @param proposalThresholdBps The basis points of the token supply required to create a proposal
    /// @param quorumThresholdBps The basis points of the token supply required to reach quorum
    /// @param vetoer The address authorized to veto proposals (address(0) if none desired)
    /// @param proposalUpdatablePeriod The time period a proposal is editable after creation
    struct GovParams {
        uint256 timelockDelay;
        uint256 votingDelay;
        uint256 votingPeriod;
        uint256 proposalThresholdBps;
        uint256 quorumThresholdBps;
        address vetoer;
        uint256 proposalUpdatablePeriod;
    }

    ///                                                          ///
    ///                           FUNCTIONS                      ///
    ///                                                          ///

    /// @notice The token implementation address
    function tokenImpl() external view returns (address);

    /// @notice The metadata renderer implementation address
    function metadataImpl() external view returns (address);

    /// @notice The auction house implementation address
    function auctionImpl() external view returns (address);

    /// @notice The treasury implementation address
    function treasuryImpl() external view returns (address);

    /// @notice The governor implementation address
    function governorImpl() external view returns (address);

    /// @notice Deprecated: deploys a DAO with custom token, auction, and governance settings for backward compatibility only.
    /// @dev New integrations should use deterministic deployment
    /// @param founderParams The DAO founder(s)
    /// @param tokenParams The ERC-721 token settings
    /// @param auctionParams The auction settings
    /// @param govParams The governance settings
    /// @return token The deployed token address
    /// @return metadataRenderer The deployed metadata renderer address
    /// @return auction The deployed auction address
    /// @return treasury The deployed treasury address
    /// @return governor The deployed governor address
    function deploy(
        FounderParams[] calldata founderParams,
        TokenParams calldata tokenParams,
        AuctionParams calldata auctionParams,
        GovParams calldata govParams
    ) external returns (address token, address metadataRenderer, address auction, address treasury, address governor);

    /// @notice Deploys a DAO deterministically using CREATE2 and explicit implementation addresses
    /// @dev SECURITY NOTES:
    ///      - deploySalt should be unique for each deployment. Using the same salt twice will cause revert.
    ///      - msg.sender is included in salt derivation to prevent cross-deployer collisions
    ///      - Recommended: use keccak256(abi.encode(daoName, timestamp, nonce)) or similar for deploySalt
    ///
    ///      GAS COSTS: Deterministic deployment may cost slightly more gas than legacy deploy()
    ///      due to CREATE2 overhead. However, benefits include:
    ///      - Predictable addresses for pre-funding or integration
    ///      - Custom implementation flexibility
    ///      - Cross-chain address consistency (if desired)
    /// @param founderParams The DAO founder(s)
    /// @param tokenParams The ERC-721 token settings
    /// @param auctionParams The auction settings
    /// @param govParams The governance settings
    /// @param deploySalt The base salt used to derive per-contract CREATE2 salts (must be unique)
    /// @return token The deployed token address
    /// @return metadataRenderer The deployed metadata renderer address
    /// @return auction The deployed auction address
    /// @return treasury The deployed treasury address
    /// @return governor The deployed governor address
    function deployDeterministic(
        FounderParams[] calldata founderParams,
        TokenParams calldata tokenParams,
        AuctionParams calldata auctionParams,
        GovParams calldata govParams,
        bytes32 deploySalt
    ) external returns (address token, address metadataRenderer, address auction, address treasury, address governor);

    /// @notice Predicts deterministic DAO addresses using an explicit implementation bundle
    /// @param deployer The deployer address used to namespace the deterministic salt
    /// @param deploySalt The base salt used to derive per-contract CREATE2 salts
    /// @return token The predicted token address
    /// @return metadataRenderer The predicted metadata renderer address
    /// @return auction The predicted auction address
    /// @return treasury The predicted treasury address
    /// @return governor The predicted governor address
    function predictDeterministicAddresses(address deployer, bytes32 deploySalt)
        external
        view
        returns (address token, address metadataRenderer, address auction, address treasury, address governor);

    /// @notice A DAO's remaining contract addresses from its token address
    /// @param token The ERC-721 token address
    /// @return metadataRenderer The metadata renderer address
    /// @return auction The auction address
    /// @return treasury The treasury address
    /// @return governor The governor address
    function getAddresses(address token) external returns (address metadataRenderer, address auction, address treasury, address governor);

    /// @notice If an implementation is registered by the Builder DAO as an optional upgrade
    /// @param baseImpl The base implementation address
    /// @param upgradeImpl The upgrade implementation address
    function isRegisteredUpgrade(address baseImpl, address upgradeImpl) external view returns (bool);

    /// @notice Called by the Builder DAO to offer opt-in implementation upgrades for all other DAOs
    /// @param baseImpl The base implementation address
    /// @param upgradeImpl The upgrade implementation address
    function registerUpgrade(address baseImpl, address upgradeImpl) external;

    /// @notice Called by the Builder DAO to remove an upgrade
    /// @param baseImpl The base implementation address
    /// @param upgradeImpl The upgrade implementation address
    function removeUpgrade(address baseImpl, address upgradeImpl) external;
}
