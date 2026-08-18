// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.35;

import { Script, console2 } from "forge-std/Script.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

import { DeployHelpers } from "./DeployHelpers.sol";
import { DeployConstants } from "./DeployConstants.sol";
import { Manager } from "../src/manager/Manager.sol";
import { DAOFactory } from "../src/factory/DAOFactory.sol";
import { Token } from "../src/token/Token.sol";
import { Auction } from "../src/auction/Auction.sol";
import { Governor } from "../src/governance/governor/Governor.sol";
import { Treasury } from "../src/governance/treasury/Treasury.sol";
import { MetadataRenderer } from "../src/token/metadata/MetadataRenderer.sol";
import { MerklePropertyIPFS } from "../src/token/metadata/renderers/MerklePropertyIPFS/MerklePropertyIPFS.sol";
import { ERC1967Proxy } from "../src/lib/proxy/ERC1967Proxy.sol";
import { ERC721RedeemMinter } from "../src/minters/ERC721RedeemMinter.sol";
import { MerkleReserveMinter } from "../src/minters/MerkleReserveMinter.sol";
import { Constants } from "./Constants.sol";

contract DeployV3New is Script, DeployConstants {
    using Strings for uint256;

    struct DeploymentResult {
        address manager;
        address daoFactory;
        address tokenImpl;
        address metadataRendererImpl;
        address merklePropertyMetadataImpl;
        address auctionImpl;
        address treasuryImpl;
        address governorImpl;
        address managerImpl;
        address merkleMinter;
        address redeemMinter;
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
        DeploymentResult memory deployment;

        console2.log("~~~~~~~~~~ CHAIN ID ~~~~~~~~~~~");
        console2.log(chainID);

        console2.log("~~~~~~~~~~ DEPLOYER ~~~~~~~~~~~");
        console2.log(deployerAddress);

        console2.log("~~~~~~~~~~ DEPLOY SALT ~~~~~~~~~~~");
        console2.logBytes32(deploySalt);

        vm.startBroadcast(deployerAddress);

        deployment = _deployAll(deploySalt, deployerAddress, weth, protocolRewards, builderRewardsRecipient);

        vm.stopBroadcast();

        _writeDeploymentFile(chainID, deployment, deploySalt);
        _logDeployment(deployment);
    }

    // solhint-disable-next-line function-max-lines
    function _deployAll(bytes32 deploySalt, address deployerAddress, address weth, address protocolRewards, address builderRewardsRecipient)
        internal
        returns (DeploymentResult memory deployment)
    {
        // Predict Manager proxy address before deploying DAOFactory so the factory can be bound to the final proxy.
        address predictedManagerProxy = DeployHelpers.predictCreate3Address(_deriveSalt(deploySalt, MANAGER_PROXY_SALT), deployerAddress);

        address predictedDAOFactory = DeployHelpers.predictCreate3Address(_deriveSalt(deploySalt, DAO_FACTORY_SALT), deployerAddress);

        // Deploy DAOFactory via CREATE3 for cross-chain deterministic DAO deployments
        // DAOFactory acts as the canonical deployer, enabling identical DAO addresses across chains
        // despite different Manager addresses. Bound to the predicted Manager proxy.
        deployment.daoFactory = DeployHelpers.deployViaCreate3(
            abi.encodePacked(type(DAOFactory).creationCode, abi.encode(predictedManagerProxy)),
            _deriveSalt(deploySalt, DAO_FACTORY_SALT),
            deployerAddress
        );

        // Verify DAOFactory deployed at predicted address
        require(deployment.daoFactory == predictedDAOFactory, "DAOFactory address mismatch");

        // Deploy implementations via CREATE3 factory for bytecode-independent cross-chain determinism
        // CREATE3 enables identical addresses even when constructor args differ per chain
        deployment.tokenImpl = DeployHelpers.deployViaCreate3(
            abi.encodePacked(type(Token).creationCode, abi.encode(predictedManagerProxy)), _deriveSalt(deploySalt, TOKEN_IMPL_SALT), deployerAddress
        );

        deployment.metadataRendererImpl = DeployHelpers.deployViaCreate3(
            abi.encodePacked(type(MetadataRenderer).creationCode, abi.encode(predictedManagerProxy)),
            _deriveSalt(deploySalt, METADATA_RENDERER_IMPL_SALT),
            deployerAddress
        );

        deployment.merklePropertyMetadataImpl = DeployHelpers.deployViaCreate3(
            abi.encodePacked(type(MerklePropertyIPFS).creationCode, abi.encode(predictedManagerProxy)),
            _deriveSalt(deploySalt, MERKLE_PROPERTY_IPFS_SALT),
            deployerAddress
        );

        deployment.auctionImpl = DeployHelpers.deployViaCreate3(
            abi.encodePacked(
                type(Auction).creationCode,
                abi.encode(predictedManagerProxy, protocolRewards, weth, Constants.REWARD_BUILDER_BPS, Constants.REWARD_REFERRAL_BPS)
            ),
            _deriveSalt(deploySalt, AUCTION_IMPL_SALT),
            deployerAddress
        );

        deployment.treasuryImpl = DeployHelpers.deployViaCreate3(
            abi.encodePacked(type(Treasury).creationCode, abi.encode(predictedManagerProxy)),
            _deriveSalt(deploySalt, TREASURY_IMPL_SALT),
            deployerAddress
        );

        deployment.governorImpl = DeployHelpers.deployViaCreate3(
            abi.encodePacked(type(Governor).creationCode, abi.encode(predictedManagerProxy)),
            _deriveSalt(deploySalt, GOVERNOR_IMPL_SALT),
            deployerAddress
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
                    builderRewardsRecipient,
                    deployment.daoFactory
                )
            ),
            _deriveSalt(deploySalt, MANAGER_IMPL_SALT),
            deployerAddress
        );

        // Deploy Manager proxy via CREATE3 with initialization data for atomic ownership setup.
        deployment.manager = DeployHelpers.deployViaCreate3(
            abi.encodePacked(
                type(ERC1967Proxy).creationCode, abi.encode(deployment.managerImpl, abi.encodeWithSignature("initialize(address)", deployerAddress))
            ),
            _deriveSalt(deploySalt, MANAGER_PROXY_SALT),
            deployerAddress
        );

        require(deployment.manager == predictedManagerProxy, "Manager proxy address mismatch");
        require(DAOFactory(deployment.daoFactory).manager() == deployment.manager, "DAOFactory manager mismatch");

        // Deploy minters via CREATE3 for cross-chain determinism
        deployment.merkleMinter = DeployHelpers.deployViaCreate3(
            abi.encodePacked(type(MerkleReserveMinter).creationCode, abi.encode(deployment.manager, protocolRewards)),
            _deriveSalt(deploySalt, MERKLE_RESERVE_MINTER_SALT),
            deployerAddress
        );

        deployment.redeemMinter = DeployHelpers.deployViaCreate3(
            abi.encodePacked(type(ERC721RedeemMinter).creationCode, abi.encode(deployment.manager, protocolRewards)),
            _deriveSalt(deploySalt, ERC721_REDEEM_MINTER_SALT),
            deployerAddress
        );
    }

    function _writeDeploymentFile(uint256 chainID, DeploymentResult memory deployment, bytes32 deploySalt) internal {
        string memory filePath = string(abi.encodePacked("deploys/", chainID.toString(), ".version3_new.txt"));

        vm.writeFile(filePath, "");
        vm.writeLine(filePath, string(abi.encodePacked("Deploy Salt: ", bytes32ToString(deploySalt))));
        vm.writeLine(filePath, string(abi.encodePacked("Manager: ", addressToString(deployment.manager))));
        vm.writeLine(filePath, string(abi.encodePacked("DAO Factory: ", addressToString(deployment.daoFactory))));
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
    }

    function _logDeployment(DeploymentResult memory deployment) internal view {
        console2.log("~~~~~~~~~~ MANAGER IMPL ~~~~~~~~~~~");
        console2.logAddress(deployment.managerImpl);

        console2.log("~~~~~~~~~~ MANAGER PROXY ~~~~~~~~~~~");
        console2.logAddress(deployment.manager);
        console2.log("");

        console2.log("~~~~~~~~~~ DAO FACTORY ~~~~~~~~~~~");
        console2.logAddress(deployment.daoFactory);
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
    }

    function addressToString(address _addr) private pure returns (string memory) {
        return DeployHelpers.addressToString(_addr);
    }

    function bytes32ToString(bytes32 _bytes) private pure returns (string memory) {
        return DeployHelpers.bytes32ToString(_bytes);
    }
}
