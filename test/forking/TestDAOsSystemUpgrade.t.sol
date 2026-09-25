// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import { ViaIRTestHelper } from "../utils/ViaIRTestHelper.sol";
import { IManager } from "../../src/manager/IManager.sol";
import { Token } from "../../src/token/Token.sol";
import { MetadataRenderer } from "../../src/token/metadata/MetadataRenderer.sol";
import { Auction } from "../../src/auction/Auction.sol";
import { Treasury } from "../../src/governance/treasury/Treasury.sol";
import { Governor } from "../../src/governance/governor/Governor.sol";
import { GovernorTypesV1 } from "../../src/governance/governor/types/GovernorTypesV1.sol";

interface VmEnvOr {
    function envOr(string calldata name, string calldata defaultValue) external view returns (string memory);
    function envOr(string calldata name, uint256 defaultValue) external view returns (uint256);
    function envOr(string calldata name, bool defaultValue) external view returns (bool);
}

/// @title TestDAOsSystemUpgrade
/// @notice Configurable fork coverage for the deployed V3 upgrade across DAO deployments.
/// @dev Set DAO_CHAINS, DAO_COUNT, or DAO_RANKS to control the matrix. Examples:
///      DAO_CHAINS=all DAO_COUNT=1
///      DAO_CHAINS=base-mainnet DAO_COUNT=5
///      DAO_CHAINS=base-mainnet DAO_RANKS=2,6,10
contract TestDAOsSystemUpgrade is ViaIRTestHelper {
    bytes32 internal constant ERC1967_IMPL_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
    string internal constant DAO_CONFIG_PATH = "test/forking/top-daos.json";
    uint256 internal constant TOKEN_URI_SAMPLE_SIZE = 10;
    address internal constant BASE_MAINNET_MERKLE_PROPERTY_IPFS_IMPL = 0x83A9B0aaC8d38A7C8cCbbE8Ee8B103610BD8A790;
    VmEnvOr internal constant ENV = VmEnvOr(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    error UpgradePreflightFailed();

    struct DAOConfig {
        uint256 rank;
        string name;
        string symbol;
        string totalAuctionSales;
        address token;
        address metadata;
        address governor;
        address auction;
        address treasury;
    }

    struct Implementations {
        address token;
        address metadata;
        address auction;
        address treasury;
        address governor;
    }

    struct DAOState {
        uint256 totalSupply;
        address tokenAuction;
        address tokenMetadata;
        uint256 auctionTokenId;
        uint256 auctionHighestBid;
        address auctionHighestBidder;
        uint40 auctionStartTime;
        uint40 auctionEndTime;
        bool auctionSettled;
        uint256 auctionDuration;
        uint256 auctionReservePrice;
        uint256 auctionTimeBuffer;
        uint256 auctionMinBidIncrement;
        uint256 votingDelay;
        uint256 votingPeriod;
        uint256 proposalThresholdBps;
        uint256 quorumThresholdBps;
        address vetoer;
        address governorToken;
        address governorTreasury;
        uint256 treasuryDelay;
        uint256 treasuryGracePeriod;
        string projectURI;
        string description;
        string contractImage;
        string rendererBase;
        uint256 propertiesCount;
        uint256[] tokenIds;
        address[] tokenOwners;
        bytes32[] tokenURIHashes;
    }

    function test_AllSelectedDAOs_UpgradeFlowAndStatePreserved() public {
        string memory chainSelection = _envStringOr("DAO_CHAINS", "all");
        uint256 daoCount = _envUintOr("DAO_COUNT", 1);
        string memory rankSelection = _envStringOr("DAO_RANKS", "");
        bool registerMissing = _envBoolOr("REGISTER_MISSING", false);

        string[3] memory chainNames = ["base-mainnet", "ethereum-mainnet", "optimism-mainnet"];
        string[3] memory rpcAliases = ["base", "mainnet", "optimism"];
        string[3] memory forkBlockKeys = ["BASE", "ETHEREUM", "OPTIMISM"];
        uint256[3] memory chainIds = [uint256(8453), uint256(1), uint256(10)];
        bool preflightPassed = true;

        for (uint256 i; i < chainNames.length; ++i) {
            if (!_chainSelected(chainSelection, chainNames[i])) continue;

            uint256 fork = _createFork(rpcAliases[i], forkBlockKeys[i]);
            vm.selectFork(fork);
            initTime();

            string memory config = vm.readFile(DAO_CONFIG_PATH);
            string memory networkPath = string.concat(".networks.", chainNames[i]);
            DAOConfig[] memory daos = _loadDAOs(config, networkPath);
            Implementations memory implementations = _loadImplementations(chainIds[i]);
            IManager manager = IManager(_loadAddress(chainIds[i], ".Manager"));

            if (!_preflightDAOs(chainNames[i], daos, manager, implementations, daoCount, rankSelection, registerMissing)) {
                preflightPassed = false;
            }

            if (registerMissing) {
                _upgradeSelectedDAOs(chainNames[i], daos, manager, implementations, daoCount, rankSelection);
            }
        }

        if (!registerMissing && !preflightPassed) revert UpgradePreflightFailed();
    }

    function _preflightDAOs(
        string memory chainName,
        DAOConfig[] memory daos,
        IManager manager,
        Implementations memory implementations,
        uint256 daoCount,
        string memory rankSelection,
        bool registerMissing
    ) internal returns (bool passed) {
        passed = true;
        for (uint256 i; i < daos.length; ++i) {
            if (!_daoSelected(daos[i].rank, daoCount, rankSelection)) continue;

            Implementations memory current = _currentImplementations(daos[i]);
            Implementations memory expected = _expectedImplementations(chainName, current, implementations);
            bool fullyUpgraded = true;

            emit log_named_string("Chain", chainName);
            emit log_named_uint("DAO rank", daos[i].rank);
            emit log_named_string("DAO name", daos[i].name);

            for (uint256 j; j < 5; ++j) {
                address currentImplementation = _implementationAt(current, j);
                address expectedImplementation = _implementationAt(expected, j);
                emit log_named_address(_componentName(j), currentImplementation);
                emit log_named_address(string.concat(_componentName(j), " V3"), expectedImplementation);

                if (currentImplementation != expectedImplementation) {
                    fullyUpgraded = false;
                    bool registered = manager.isRegisteredUpgrade(currentImplementation, expectedImplementation);
                    emit log_named_string(string.concat(_componentName(j), " registration"), registered ? "registered" : "missing");
                    if (!registered) {
                        if (registerMissing) {
                            vm.prank(manager.owner());
                            manager.registerUpgrade(currentImplementation, expectedImplementation);
                            assertTrue(manager.isRegisteredUpgrade(currentImplementation, expectedImplementation), "Fork registration failed");
                        } else {
                            passed = false;
                        }
                    }
                }
            }

            if (fullyUpgraded) emit log("DAO already uses all latest implementations; treating as success");
        }
    }

    function _loadDAOs(string memory config, string memory networkPath) internal pure returns (DAOConfig[] memory daos) {
        string memory path = string.concat(networkPath, "[*]");
        uint256[] memory ranks = abi.decode(vm.parseJson(config, string.concat(path, ".rank")), (uint256[]));
        string[] memory names = abi.decode(vm.parseJson(config, string.concat(path, ".name")), (string[]));
        address[] memory tokens = abi.decode(vm.parseJson(config, string.concat(path, ".token")), (address[]));
        address[] memory metadata = abi.decode(vm.parseJson(config, string.concat(path, ".metadata")), (address[]));
        address[] memory governors = abi.decode(vm.parseJson(config, string.concat(path, ".governor")), (address[]));
        address[] memory auctions = abi.decode(vm.parseJson(config, string.concat(path, ".auction")), (address[]));
        address[] memory treasuries = abi.decode(vm.parseJson(config, string.concat(path, ".treasury")), (address[]));

        daos = new DAOConfig[](ranks.length);
        for (uint256 i; i < ranks.length; ++i) {
            daos[i] = DAOConfig({
                rank: ranks[i],
                name: names[i],
                symbol: "",
                totalAuctionSales: "",
                token: tokens[i],
                metadata: metadata[i],
                governor: governors[i],
                auction: auctions[i],
                treasury: treasuries[i]
            });
        }
    }

    function _upgradeSelectedDAOs(
        string memory chainName,
        DAOConfig[] memory daos,
        IManager manager,
        Implementations memory implementations,
        uint256 daoCount,
        string memory rankSelection
    ) internal {
        for (uint256 i; i < daos.length; ++i) {
            if (!_daoSelected(daos[i].rank, daoCount, rankSelection)) continue;

            Implementations memory current = _currentImplementations(daos[i]);
            Implementations memory expected = _expectedImplementations(chainName, current, implementations);
            bool fullyUpgraded = true;
            for (uint256 j; j < 5; ++j) {
                if (_implementationAt(current, j) != _implementationAt(expected, j)) fullyUpgraded = false;
            }
            if (fullyUpgraded) continue;

            _assertTreasuryOwnsDAO(daos[i]);
            DAOState memory before = _recordState(daos[i]);
            _executeUpgrade(chainName, daos[i], manager, current, expected);
            _assertStatePreserved(daos[i], before, expected);
            _exerciseGovernance(daos[i], before);
        }
    }

    function _executeUpgrade(string memory, DAOConfig memory dao, IManager, Implementations memory current, Implementations memory expected)
        internal
    {
        Auction auction = Auction(payable(dao.auction));
        vm.startPrank(dao.treasury);
        if (!auction.paused()) {
            auction.pause();
        }

        if (current.auction != expected.auction) {
            auction.upgradeTo(expected.auction);
        }
        if (current.token != expected.token) {
            Token(dao.token).upgradeTo(expected.token);
        }
        if (current.metadata != expected.metadata) {
            MetadataRenderer(dao.metadata).upgradeTo(expected.metadata);
        }
        if (current.treasury != expected.treasury) {
            Treasury(payable(dao.treasury)).upgradeTo(expected.treasury);
        }
        if (current.governor != expected.governor) {
            Governor(dao.governor).upgradeTo(expected.governor);
        }

        if (auction.paused()) {
            auction.unpause();
        }

        Governor(dao.governor).updateProposalUpdatablePeriod(0);
        vm.stopPrank();
    }

    function _assertTreasuryOwnsDAO(DAOConfig memory dao) internal {
        assertEq(Token(dao.token).owner(), dao.treasury, "Token owner is not Treasury");
        assertEq(MetadataRenderer(dao.metadata).owner(), dao.treasury, "Metadata owner is not Treasury");
        assertEq(Auction(payable(dao.auction)).owner(), dao.treasury, "Auction owner is not Treasury");
        assertEq(Treasury(payable(dao.treasury)).owner(), dao.governor, "Treasury owner is not Governor");
        assertEq(Governor(dao.governor).owner(), dao.treasury, "Governor owner is not Treasury");
    }

    function _exerciseGovernance(DAOConfig memory dao, DAOState memory before) internal {
        Governor governor = Governor(dao.governor);
        Treasury treasury = Treasury(payable(dao.treasury));
        address proposer = before.tokenOwners[0];
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        targets[0] = address(governor);
        uint256 executedProposalUpdatablePeriod = 2 days;
        calldatas[0] = abi.encodeWithSignature("updateProposalUpdatablePeriod(uint256)", executedProposalUpdatablePeriod);

        vm.startPrank(dao.treasury);
        governor.updateProposalThresholdBps(1);
        governor.updateQuorumThresholdBps(1000);
        governor.updateProposalUpdatablePeriod(1 days);
        vm.stopPrank();

        string memory description = "Fork upgrade proposal";
        vm.prank(proposer);
        bytes32 proposalId = governor.propose(targets, values, calldatas, description);
        assertEq(uint256(governor.state(proposalId)), uint256(GovernorTypesV1.ProposalState.Updatable), "Proposal is not updatable");

        string memory updatedDescription = "Updated fork upgrade proposal";
        vm.prank(proposer);
        bytes32 updatedProposalId =
            governor.updateProposal(proposalId, targets, values, calldatas, updatedDescription, "Verify proposal update after upgrade");
        assertEq(governor.proposalIdReplacedBy(proposalId), updatedProposalId, "Proposal replacement was not recorded");
        assertEq(uint256(governor.state(proposalId)), uint256(GovernorTypesV1.ProposalState.Replaced), "Original proposal was not replaced");

        vm.warp(block.timestamp + governor.proposalUpdatablePeriod() + governor.votingDelay() + 1);
        vm.prank(proposer);
        governor.castVote(updatedProposalId, 1);
        for (uint256 i = 1; i < before.tokenOwners.length; ++i) {
            bool alreadyVoted;
            for (uint256 j; j < i; ++j) {
                if (before.tokenOwners[i] == before.tokenOwners[j]) alreadyVoted = true;
            }
            if (alreadyVoted || before.tokenOwners[i] == proposer) continue;
            vm.prank(before.tokenOwners[i]);
            governor.castVote(updatedProposalId, 1);
        }
        vm.warp(block.timestamp + governor.votingPeriod() + 1);
        assertEq(uint256(governor.state(updatedProposalId)), uint256(GovernorTypesV1.ProposalState.Succeeded), "Updated proposal did not succeed");

        governor.queue(updatedProposalId);
        vm.warp(block.timestamp + treasury.delay() + 1);
        governor.execute(targets, values, calldatas, keccak256(bytes(updatedDescription)), proposer);
        assertEq(governor.proposalUpdatablePeriod(), executedProposalUpdatablePeriod, "Proposal execution did not update Governor");

        vm.prank(dao.treasury);
        governor.updateProposalThresholdBps(before.proposalThresholdBps);
        vm.prank(dao.treasury);
        governor.updateQuorumThresholdBps(before.quorumThresholdBps);
        vm.prank(dao.treasury);
        governor.updateProposalUpdatablePeriod(0);
    }

    function _expectedImplementations(string memory chainName, Implementations memory current, Implementations memory latest)
        internal
        pure
        returns (Implementations memory expected)
    {
        expected.token = latest.token;
        expected.metadata = latest.metadata;
        expected.auction = latest.auction;
        expected.treasury = latest.treasury;
        expected.governor = latest.governor;
        if (keccak256(bytes(chainName)) == keccak256("base-mainnet") && current.metadata == BASE_MAINNET_MERKLE_PROPERTY_IPFS_IMPL) {
            expected.metadata = current.metadata;
        }
    }

    function _recordState(DAOConfig memory dao) internal returns (DAOState memory state) {
        Token token = Token(dao.token);
        Auction auction = Auction(payable(dao.auction));
        Governor governor = Governor(dao.governor);
        Treasury treasury = Treasury(payable(dao.treasury));
        MetadataRenderer metadata = MetadataRenderer(dao.metadata);

        state.totalSupply = token.totalSupply();
        state.tokenAuction = token.auction();
        state.tokenMetadata = token.metadataRenderer();
        (
            state.auctionTokenId,
            state.auctionHighestBid,
            state.auctionHighestBidder,
            state.auctionStartTime,
            state.auctionEndTime,
            state.auctionSettled
        ) = auction.auction();
        state.auctionDuration = auction.duration();
        state.auctionReservePrice = auction.reservePrice();
        state.auctionTimeBuffer = auction.timeBuffer();
        state.auctionMinBidIncrement = auction.minBidIncrement();
        state.votingDelay = governor.votingDelay();
        state.votingPeriod = governor.votingPeriod();
        state.proposalThresholdBps = governor.proposalThresholdBps();
        state.quorumThresholdBps = governor.quorumThresholdBps();
        state.vetoer = governor.vetoer();
        state.governorToken = governor.token();
        state.governorTreasury = governor.treasury();
        state.treasuryDelay = treasury.delay();
        state.treasuryGracePeriod = treasury.gracePeriod();
        state.projectURI = metadata.projectURI();
        state.description = metadata.description();
        state.contractImage = metadata.contractImage();
        state.rendererBase = metadata.rendererBase();
        state.propertiesCount = metadata.propertiesCount();
        uint256 sampleSize = state.totalSupply < TOKEN_URI_SAMPLE_SIZE ? state.totalSupply : TOKEN_URI_SAMPLE_SIZE;
        state.tokenIds = new uint256[](sampleSize);
        state.tokenOwners = new address[](sampleSize);
        state.tokenURIHashes = new bytes32[](sampleSize);
        uint256 randomSeed = uint256(keccak256(abi.encode(dao.token, state.totalSupply, state.auctionTokenId)));
        uint256 sampledTokens;
        uint256 maxAttempts = sampleSize * 50;
        for (uint256 i; i < maxAttempts && sampledTokens < sampleSize; ++i) {
            uint256 tokenId = uint256(keccak256(abi.encode(randomSeed, i))) % (state.auctionTokenId + 1);
            bool duplicate;
            for (uint256 j; j < sampledTokens; ++j) {
                if (state.tokenIds[j] == tokenId) duplicate = true;
            }
            if (duplicate) continue;

            try token.ownerOf(tokenId) returns (address owner) {
                try token.tokenURI(tokenId) returns (string memory uri) {
                    state.tokenIds[sampledTokens] = tokenId;
                    state.tokenOwners[sampledTokens] = owner;
                    state.tokenURIHashes[sampledTokens] = keccak256(bytes(uri));
                    ++sampledTokens;
                } catch { }
            } catch { }
        }
        assertEq(sampledTokens, sampleSize, "Could not find enough readable token URIs");
    }

    function _assertStatePreserved(DAOConfig memory dao, DAOState memory before, Implementations memory expected) internal {
        Token token = Token(dao.token);
        Auction auction = Auction(payable(dao.auction));
        Governor governor = Governor(dao.governor);
        Treasury treasury = Treasury(payable(dao.treasury));
        MetadataRenderer metadata = MetadataRenderer(dao.metadata);
        Implementations memory afterImplementations = _currentImplementations(dao);

        for (uint256 i; i < 5; ++i) {
            assertEq(_implementationAt(afterImplementations, i), _implementationAt(expected, i), "Unexpected final implementation");
        }
        uint256 expectedSupply = before.totalSupply + (before.auctionSettled ? 1 : 0);
        assertEq(token.totalSupply(), expectedSupply, "Unexpected token supply change");
        assertEq(token.auction(), before.tokenAuction, "Token auction changed");
        assertEq(token.metadataRenderer(), before.tokenMetadata, "Token metadata renderer changed");
        (uint256 tokenId, uint256 highestBid, address highestBidder, uint40 startTime, uint40 endTime, bool settled) = auction.auction();
        if (before.auctionSettled) {
            assertEq(tokenId, before.auctionTokenId + 1, "Next auction token was not created");
            assertEq(highestBid, 0, "New auction has a bid");
            assertEq(highestBidder, address(0), "New auction has a bidder");
            assertFalse(settled, "New auction is already settled");
        } else {
            assertEq(tokenId, before.auctionTokenId, "Auction token changed");
            assertEq(highestBid, before.auctionHighestBid, "Auction bid changed");
            assertEq(highestBidder, before.auctionHighestBidder, "Auction bidder changed");
            assertEq(startTime, before.auctionStartTime, "Auction start changed");
            assertEq(endTime, before.auctionEndTime, "Auction end changed");
            assertEq(settled, before.auctionSettled, "Auction settled state changed");
        }
        assertEq(auction.duration(), before.auctionDuration, "Auction duration changed");
        assertEq(auction.reservePrice(), before.auctionReservePrice, "Auction reserve changed");
        assertEq(auction.timeBuffer(), before.auctionTimeBuffer, "Auction time buffer changed");
        assertEq(auction.minBidIncrement(), before.auctionMinBidIncrement, "Auction increment changed");
        assertFalse(auction.paused(), "Auction was not unpaused");
        assertEq(governor.votingDelay(), before.votingDelay, "Voting delay changed");
        assertEq(governor.votingPeriod(), before.votingPeriod, "Voting period changed");
        assertEq(governor.proposalThresholdBps(), before.proposalThresholdBps, "Proposal threshold changed");
        assertEq(governor.quorumThresholdBps(), before.quorumThresholdBps, "Quorum threshold changed");
        assertEq(governor.vetoer(), before.vetoer, "Vetoer changed");
        assertEq(governor.token(), before.governorToken, "Governor token changed");
        assertEq(governor.treasury(), before.governorTreasury, "Governor treasury changed");
        assertEq(treasury.delay(), before.treasuryDelay, "Treasury delay changed");
        assertEq(treasury.gracePeriod(), before.treasuryGracePeriod, "Treasury grace period changed");
        assertEq(metadata.projectURI(), before.projectURI, "Project URI changed");
        assertEq(metadata.description(), before.description, "Description changed");
        assertEq(metadata.contractImage(), before.contractImage, "Contract image changed");
        assertEq(metadata.rendererBase(), before.rendererBase, "Renderer base changed");
        assertEq(metadata.propertiesCount(), before.propertiesCount, "Metadata properties changed");
        assertEq(token.totalSupply(), expectedSupply, "Token supply changed during token checks");
        for (uint256 i; i < before.tokenOwners.length; ++i) {
            assertEq(token.ownerOf(before.tokenIds[i]), before.tokenOwners[i], "Existing token owner changed");
            assertEq(keccak256(bytes(token.tokenURI(before.tokenIds[i]))), before.tokenURIHashes[i], "Existing token URI changed");
        }
        assertEq(governor.proposalUpdatablePeriod(), 0, "Proposal updatable period was not disabled");
    }

    function _currentImplementations(DAOConfig memory dao) internal view returns (Implementations memory implementations) {
        implementations.token = _implementation(dao.token);
        implementations.metadata = _implementation(dao.metadata);
        implementations.auction = _implementation(dao.auction);
        implementations.treasury = _implementation(dao.treasury);
        implementations.governor = _implementation(dao.governor);
    }

    function _implementationAt(Implementations memory implementations, uint256 index) internal pure returns (address) {
        if (index == 0) return implementations.token;
        if (index == 1) return implementations.metadata;
        if (index == 2) return implementations.auction;
        if (index == 3) return implementations.treasury;
        return implementations.governor;
    }

    function _loadImplementations(uint256 chainId) internal view returns (Implementations memory implementations) {
        string memory addresses = vm.readFile(string.concat("addresses/", _uintToString(chainId), ".json"));
        implementations.token = _loadAddress(addresses, ".Token");
        implementations.metadata = _loadAddress(addresses, ".MetadataRenderer");
        implementations.auction = _loadAddress(addresses, ".Auction");
        implementations.treasury = _loadAddress(addresses, ".Treasury");
        implementations.governor = _loadAddress(addresses, ".Governor");
    }

    function _loadAddress(uint256 chainId, string memory key) internal view returns (address) {
        return _loadAddress(vm.readFile(string.concat("addresses/", _uintToString(chainId), ".json")), key);
    }

    function _loadAddress(string memory json, string memory key) internal pure returns (address) {
        return abi.decode(vm.parseJson(json, key), (address));
    }

    function _implementation(address proxy) internal view returns (address) {
        return address(uint160(uint256(vm.load(proxy, ERC1967_IMPL_SLOT))));
    }

    function _chainSelected(string memory selection, string memory chain) internal pure returns (bool) {
        if (keccak256(bytes(selection)) == keccak256(bytes("all"))) return true;
        return _csvContains(selection, chain);
    }

    function _daoSelected(uint256 rank, uint256 count, string memory ranks) internal pure returns (bool) {
        if (bytes(ranks).length != 0) return _csvContainsUint(ranks, rank);
        return rank <= count;
    }

    function _csvContains(string memory csv, string memory value) internal pure returns (bool) {
        bytes memory input = bytes(csv);
        bytes memory target = bytes(value);
        uint256 start;
        for (uint256 i; i <= input.length; ++i) {
            if (i != input.length && input[i] != ",") continue;
            if (i - start == target.length) {
                bool matches = true;
                for (uint256 j; j < target.length; ++j) {
                    if (input[start + j] != target[j]) matches = false;
                }
                if (matches) return true;
            }
            start = i + 1;
        }
        return false;
    }

    function _csvContainsUint(string memory csv, uint256 value) internal pure returns (bool) {
        bytes memory input = bytes(csv);
        uint256 start;
        for (uint256 i; i <= input.length; ++i) {
            if (i != input.length && input[i] != ",") continue;
            uint256 parsed;
            for (uint256 j = start; j < i; ++j) {
                if (input[j] < "0" || input[j] > "9") return false;
                parsed = parsed * 10 + uint8(input[j]) - uint8(bytes1("0"));
            }
            if (parsed == value) return true;
            start = i + 1;
        }
        return false;
    }

    function _componentName(uint256 index) internal pure returns (string memory) {
        if (index == 0) return "Token";
        if (index == 1) return "MetadataRenderer";
        if (index == 2) return "Auction";
        if (index == 3) return "Treasury";
        return "Governor";
    }

    function _envStringOr(string memory name, string memory defaultValue) internal view returns (string memory) {
        return ENV.envOr(name, defaultValue);
    }

    function _envUintOr(string memory name, uint256 defaultValue) internal view returns (uint256) {
        return ENV.envOr(name, defaultValue);
    }

    function _envBoolOr(string memory name, bool defaultValue) internal view returns (bool) {
        return ENV.envOr(name, defaultValue);
    }

    function _createFork(string memory rpcAlias, string memory chainKey) internal returns (uint256) {
        uint256 blockNumber = _envUintOr(string.concat("FORK_BLOCK_", chainKey), _envUintOr("FORK_BLOCK", 0));
        if (blockNumber == 0) return vm.createFork(rpcAlias);
        return vm.createFork(rpcAlias, blockNumber);
    }

    function _uintToString(uint256 value) internal pure returns (string memory) {
        if (value == 0) return "0";
        uint256 digits;
        uint256 copy = value;
        while (copy != 0) {
            digits++;
            copy /= 10;
        }
        bytes memory result = new bytes(digits);
        while (value != 0) {
            result[--digits] = bytes1(uint8(48 + (value % 10)));
            value /= 10;
        }
        return string(result);
    }
}
