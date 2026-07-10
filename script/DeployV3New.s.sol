// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.35;

import "forge-std/Script.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

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

contract DeployV3New is Script {
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

        _writeDeploymentFile(chainID, deployment);
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

        deployment.managerImpl0 = address(
            new Manager{ salt: _deriveSalt(deploySalt, keccak256("MANAGER_IMPL_0")) }(
                address(0), address(0), address(0), address(0), address(0), address(0)
            )
        );

        manager = Manager(
            address(
                new ERC1967Proxy{ salt: _deriveSalt(deploySalt, keccak256("MANAGER_PROXY")) }(
                    deployment.managerImpl0, abi.encodeWithSignature("initialize(address)", deployerAddress)
                )
            )
        );
        deployment.manager = address(manager);

        deployment.tokenImpl = address(new Token(address(manager)));
        deployment.metadataRendererImpl = address(new MetadataRenderer(address(manager)));
        deployment.merklePropertyMetadataImpl =
            address(new MerklePropertyIPFS{ salt: _deriveSalt(deploySalt, keccak256("MERKLE_PROPERTY_IPFS")) }(address(manager)));
        deployment.auctionImpl =
            address(new Auction(address(manager), protocolRewards, weth, Constants.REWARD_BUILDER_BPS, Constants.REWARD_REFERRAL_BPS));
        deployment.treasuryImpl = address(new Treasury(address(manager)));
        deployment.governorImpl = address(new Governor(address(manager)));

        deployment.managerImpl = address(
            new Manager{ salt: _deriveSalt(deploySalt, keccak256("MANAGER_IMPL")) }(
                deployment.tokenImpl,
                deployment.metadataRendererImpl,
                deployment.auctionImpl,
                deployment.treasuryImpl,
                deployment.governorImpl,
                builderRewardsRecipient
            )
        );

        manager.upgradeTo(deployment.managerImpl);

        deployment.merkleMinter =
            address(new MerkleReserveMinter{ salt: _deriveSalt(deploySalt, keccak256("MERKLE_RESERVE_MINTER")) }(address(manager), protocolRewards));

        deployment.redeemMinter =
            address(new ERC721RedeemMinter{ salt: _deriveSalt(deploySalt, keccak256("ERC721_REDEEM_MINTER")) }(manager, protocolRewards));

        deployment.migrationDeployer = address(
            new L2MigrationDeployer{ salt: _deriveSalt(deploySalt, keccak256("L2_MIGRATION_DEPLOYER")) }(
                address(manager), deployment.merkleMinter, crossDomainMessenger
            )
        );
    }

    function _writeDeploymentFile(uint256 chainID, DeploymentResult memory deployment) internal {
        string memory filePath = string(abi.encodePacked("deploys/", chainID.toString(), ".version3_new.txt"));

        vm.writeFile(filePath, "");
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

    function _deriveSalt(bytes32 deploySalt, bytes32 label) private pure returns (bytes32) {
        return keccak256(abi.encode(deploySalt, label));
    }
}
