// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.35;

import "forge-std/Script.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

import { DeployHelpers } from "./DeployHelpers.sol";
import { DeployConstants } from "./DeployConstants.sol";
import { Manager } from "../src/manager/Manager.sol";
import { Token } from "../src/token/Token.sol";
import { Auction } from "../src/auction/Auction.sol";
import { Governor } from "../src/governance/governor/Governor.sol";
import { Treasury } from "../src/governance/treasury/Treasury.sol";
import { MetadataRenderer } from "../src/token/metadata/MetadataRenderer.sol";
import { MerklePropertyIPFS } from "../src/token/metadata/renderers/MerklePropertyIPFS/MerklePropertyIPFS.sol";
import { ERC1967Proxy } from "../src/lib/proxy/ERC1967Proxy.sol";
import { ERC721RedeemMinter } from "../src/minters/ERC721RedeemMinter.sol";
import { MerkleReserveMinter } from "../src/minters/MerkleReserveMinter.sol";
import { L2MigrationDeployer } from "../src/deployers/L2MigrationDeployer.sol";
import { Constants } from "./Constants.sol";

contract DeployV3New is Script, DeployConstants {
    using Strings for uint256;

    struct DeploymentResult {
        address managerImpl0;
        address manager;
        address tokenImpl;
        address metadataRendererImpl;
        address merklePropertyMetadataImpl;
        address auctionImpl;
        address treasuryImpl;
        address governorImpl;
        address managerImpl;
        address merkleMinter;
        address redeemMinter;
        address migrationDeployer;
    }

    string configFile;

    function _getKey(string memory key) internal view returns (address result) {
        (result) = abi.decode(vm.parseJson(configFile, string.concat(".", key)), (address));
    }

    function run() public {
        uint256 chainID = block.chainid;
        uint256 key = vm.envUint("PRIVATE_KEY");
        string memory salt = vm.envString("DEPLOY_SALT");
        bytes32 deploySalt = keccak256(bytes(salt));

        configFile = vm.readFile(string.concat("./addresses/", Strings.toString(chainID), ".json"));

        address weth = _getKey("WETH");
        address deployerAddress = vm.addr(key);
        address protocolRewards = _getKey("ProtocolRewards");
        address builderRewardsRecipient = _getKey("BuilderRewardsRecipient");
        address crossDomainMessenger = _getKey("CrossDomainMessenger");
        DeploymentResult memory deployment;

        console2.log("~~~~~~~~~~ CHAIN ID ~~~~~~~~~~~");
        console2.log(chainID);

        console2.log("~~~~~~~~~~ DEPLOYER ~~~~~~~~~~~");
        console2.log(deployerAddress);

        console2.log("~~~~~~~~~~ DEPLOY SALT ~~~~~~~~~~~");
        console2.logBytes32(deploySalt);

        vm.startBroadcast(deployerAddress);

        deployment = _deployAll(deploySalt, deployerAddress, weth, protocolRewards, builderRewardsRecipient, crossDomainMessenger);

        vm.stopBroadcast();

        _writeDeploymentFile(chainID, deployment, deploySalt);
        _logDeployment(deployment);
    }

    function _deployAll(
        bytes32 deploySalt,
        address deployerAddress,
        address weth,
        address protocolRewards,
        address builderRewardsRecipient,
        address crossDomainMessenger
    ) internal returns (DeploymentResult memory deployment) {
        Manager manager;

        // Deploy Manager implementation (bootstrap) via CREATE2 factory
        // CRITICAL: Use all-zero constructor args for cross-chain determinism
        // builderRewardsRecipient is chain-specific, so we use address(0) here
        // Manager proxy will be upgraded to the real implementation immediately after
        deployment.managerImpl0 = DeployHelpers.deployViaFactory(
            abi.encodePacked(
                type(Manager).creationCode, abi.encode(address(0), address(0), address(0), address(0), address(0), address(0))
            ),
            _deriveSalt(deploySalt, MANAGER_IMPL_0_SALT)
        );

        // Deploy Manager proxy via CREATE2 factory for cross-chain determinism
        // NOTE: Include initialization data in proxy constructor for atomic deployment
        // This prevents front-running attacks where someone else calls initialize() before we do
        // Cross-chain determinism is maintained because deployerAddress is same across chains
        manager = Manager(
            DeployHelpers.deployViaFactory(
                abi.encodePacked(
                    type(ERC1967Proxy).creationCode,
                    abi.encode(deployment.managerImpl0, abi.encodeWithSignature("initialize(address)", deployerAddress))
                ),
                _deriveSalt(deploySalt, MANAGER_PROXY_SALT)
            )
        );
        deployment.manager = address(manager);

        // Deploy implementations via CREATE3 factory for bytecode-independent cross-chain determinism
        // CREATE3 enables identical addresses even when constructor args differ per chain
        deployment.tokenImpl = DeployHelpers.deployViaCreate3(
            abi.encodePacked(type(Token).creationCode, abi.encode(address(manager))), _deriveSalt(deploySalt, TOKEN_IMPL_SALT)
        );

        deployment.metadataRendererImpl = DeployHelpers.deployViaCreate3(
            abi.encodePacked(type(MetadataRenderer).creationCode, abi.encode(address(manager))), _deriveSalt(deploySalt, METADATA_RENDERER_IMPL_SALT)
        );

        deployment.merklePropertyMetadataImpl = DeployHelpers.deployViaCreate3(
            abi.encodePacked(type(MerklePropertyIPFS).creationCode, abi.encode(address(manager))), _deriveSalt(deploySalt, MERKLE_PROPERTY_IPFS_SALT)
        );

        deployment.auctionImpl = DeployHelpers.deployViaCreate3(
            abi.encodePacked(
                type(Auction).creationCode,
                abi.encode(address(manager), protocolRewards, weth, Constants.REWARD_BUILDER_BPS, Constants.REWARD_REFERRAL_BPS)
            ),
            _deriveSalt(deploySalt, AUCTION_IMPL_SALT)
        );

        deployment.treasuryImpl = DeployHelpers.deployViaCreate3(
            abi.encodePacked(type(Treasury).creationCode, abi.encode(address(manager))), _deriveSalt(deploySalt, TREASURY_IMPL_SALT)
        );

        deployment.governorImpl = DeployHelpers.deployViaCreate3(
            abi.encodePacked(type(Governor).creationCode, abi.encode(address(manager))), _deriveSalt(deploySalt, GOVERNOR_IMPL_SALT)
        );

        deployment.managerImpl = DeployHelpers.deployViaCreate3(
            abi.encodePacked(
                type(Manager).creationCode,
                abi.encode(
                    deployment.tokenImpl,
                    deployment.metadataRendererImpl,
                    deployment.auctionImpl,
                    deployment.treasuryImpl,
                    deployment.governorImpl,
                    builderRewardsRecipient
                )
            ),
            _deriveSalt(deploySalt, MANAGER_IMPL_SALT)
        );

        manager.upgradeTo(deployment.managerImpl);

        // Deploy minters and migration deployer via CREATE3 for cross-chain determinism
        deployment.merkleMinter = DeployHelpers.deployViaCreate3(
            abi.encodePacked(type(MerkleReserveMinter).creationCode, abi.encode(address(manager), protocolRewards)),
            _deriveSalt(deploySalt, MERKLE_RESERVE_MINTER_SALT)
        );

        deployment.redeemMinter = DeployHelpers.deployViaCreate3(
            abi.encodePacked(type(ERC721RedeemMinter).creationCode, abi.encode(manager, protocolRewards)),
            _deriveSalt(deploySalt, ERC721_REDEEM_MINTER_SALT)
        );

        deployment.migrationDeployer = DeployHelpers.deployViaCreate3(
            abi.encodePacked(type(L2MigrationDeployer).creationCode, abi.encode(address(manager), deployment.merkleMinter, crossDomainMessenger)),
            _deriveSalt(deploySalt, L2_MIGRATION_DEPLOYER_SALT)
        );
    }

    function _writeDeploymentFile(uint256 chainID, DeploymentResult memory deployment, bytes32 deploySalt) internal {
        string memory filePath = string(abi.encodePacked("deploys/", chainID.toString(), ".version3_new.txt"));

        vm.writeFile(filePath, "");
        vm.writeLine(filePath, string(abi.encodePacked("Deploy Salt: ", bytes32ToString(deploySalt))));
        vm.writeLine(filePath, string(abi.encodePacked("Manager: ", addressToString(deployment.manager))));
        vm.writeLine(filePath, string(abi.encodePacked("Token implementation: ", addressToString(deployment.tokenImpl))));
        vm.writeLine(filePath, string(abi.encodePacked("Metadata Renderer implementation: ", addressToString(deployment.metadataRendererImpl))));
        vm.writeLine(
            filePath, string(abi.encodePacked("Merkle Property IPFS implementation: ", addressToString(deployment.merklePropertyMetadataImpl)))
        );
        vm.writeLine(filePath, string(abi.encodePacked("Auction implementation: ", addressToString(deployment.auctionImpl))));
        vm.writeLine(filePath, string(abi.encodePacked("Treasury implementation: ", addressToString(deployment.treasuryImpl))));
        vm.writeLine(filePath, string(abi.encodePacked("Governor implementation: ", addressToString(deployment.governorImpl))));
        vm.writeLine(filePath, string(abi.encodePacked("Manager implementation: ", addressToString(deployment.managerImpl))));
        vm.writeLine(filePath, string(abi.encodePacked("Merkle Reserve Minter: ", addressToString(deployment.merkleMinter))));
        vm.writeLine(filePath, string(abi.encodePacked("ERC721 Redeem Minter: ", addressToString(deployment.redeemMinter))));
        vm.writeLine(filePath, string(abi.encodePacked("Migration Deployer: ", addressToString(deployment.migrationDeployer))));
    }

    function _logDeployment(DeploymentResult memory deployment) internal view {
        console2.log("~~~~~~~~~~ MANAGER IMPL 0 ~~~~~~~~~~~");
        console2.logAddress(deployment.managerImpl0);

        console2.log("~~~~~~~~~~ MANAGER IMPL 1 ~~~~~~~~~~~");
        console2.logAddress(deployment.managerImpl);

        console2.log("~~~~~~~~~~ MANAGER PROXY ~~~~~~~~~~~");
        console2.logAddress(deployment.manager);
        console2.log("");

        console2.log("~~~~~~~~~~ TOKEN IMPL ~~~~~~~~~~~");
        console2.logAddress(deployment.tokenImpl);

        console2.log("~~~~~~~~~~ METADATA RENDERER IMPL ~~~~~~~~~~~");
        console2.logAddress(deployment.metadataRendererImpl);

        console2.log("~~~~~~~~~~ MERKLE PROPERTY IPFS IMPL ~~~~~~~~~~~");
        console2.logAddress(deployment.merklePropertyMetadataImpl);

        console2.log("~~~~~~~~~~ AUCTION IMPL ~~~~~~~~~~~");
        console2.logAddress(deployment.auctionImpl);

        console2.log("~~~~~~~~~~ TREASURY IMPL ~~~~~~~~~~~");
        console2.logAddress(deployment.treasuryImpl);

        console2.log("~~~~~~~~~~ GOVERNOR IMPL ~~~~~~~~~~~");
        console2.logAddress(deployment.governorImpl);

        console2.log("~~~~~~~~~~ MERKLE RESERVE MINTER ~~~~~~~~~~~");
        console2.logAddress(deployment.merkleMinter);

        console2.log("~~~~~~~~~~ ERC721 REDEEM MINTER ~~~~~~~~~~~");
        console2.logAddress(deployment.redeemMinter);

        console2.log("~~~~~~~~~~ MIGRATION DEPLOYER ~~~~~~~~~~~");
        console2.logAddress(deployment.migrationDeployer);
    }

    function addressToString(address _addr) private pure returns (string memory) {
        bytes memory s = new bytes(40);
        for (uint256 i = 0; i < 20; i++) {
            bytes1 b = bytes1(uint8(uint256(uint160(_addr)) / (2 ** (8 * (19 - i)))));
            bytes1 hi = bytes1(uint8(b) / 16);
            bytes1 lo = bytes1(uint8(b) - 16 * uint8(hi));
            s[2 * i] = char(hi);
            s[2 * i + 1] = char(lo);
        }
        return string(abi.encodePacked("0x", string(s)));
    }

    function char(bytes1 b) private pure returns (bytes1 c) {
        if (uint8(b) < 10) return bytes1(uint8(b) + 0x30);
        else return bytes1(uint8(b) + 0x57);
    }

    function bytes32ToString(bytes32 _bytes) private pure returns (string memory) {
        bytes memory s = new bytes(64);
        for (uint256 i = 0; i < 32; i++) {
            bytes1 b = _bytes[i];
            bytes1 hi = bytes1(uint8(b) / 16);
            bytes1 lo = bytes1(uint8(b) - 16 * uint8(hi));
            s[2 * i] = char(hi);
            s[2 * i + 1] = char(lo);
        }
        return string(abi.encodePacked("0x", string(s)));
    }
}
