// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.35;

import "forge-std/Script.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

import { DeployHelpers } from "./DeployHelpers.sol";
import { DeployConstants } from "./DeployConstants.sol";
import { IManager } from "../src/manager/IManager.sol";
import { Manager } from "../src/manager/Manager.sol";
import { DAOFactory } from "../src/factory/DAOFactory.sol";
import { Governor } from "../src/governance/governor/Governor.sol";
import { Token } from "../src/token/Token.sol";
import { Auction } from "../src/auction/Auction.sol";
import { Treasury } from "../src/governance/treasury/Treasury.sol";
import { MetadataRenderer } from "../src/token/metadata/MetadataRenderer.sol";
import { Constants } from "./Constants.sol";

contract DeployV3Upgrade is Script, DeployConstants {
    using Strings for uint256;

    string configFile;

    function _getKey(string memory key) internal view returns (address result) {
        (result) = abi.decode(vm.parseJson(configFile, string.concat(".", key)), (address));
    }

    function run() public {
        uint256 chainID = block.chainid;
        string memory salt = vm.envString("DEPLOY_SALT");
        bytes32 deploySalt = keccak256(bytes(salt));

        configFile = vm.readFile(string.concat("./addresses/", Strings.toString(chainID), ".json"));

        address deployerAddress = vm.addr(vm.envUint("PRIVATE_KEY"));
        IManager managerProxy = IManager(_getKey("Manager"));
        address oldManagerImpl = _getKey("ManagerImpl");
        address oldGovernorImpl = _getKey("Governor");
        address auctionImpl = _getKey("Auction");
        address treasuryImpl = _getKey("Treasury");
        address tokenImpl = _getKey("Token");
        address metadataRendererImpl = _getKey("MetadataRenderer");
        address protocolRewards = _getKey("ProtocolRewards");
        address weth = _getKey("WETH");
        address builderRewardsRecipient = _getKey("BuilderRewardsRecipient");

        _deployUpgrade(
            deployerAddress,
            managerProxy,
            oldManagerImpl,
            oldGovernorImpl,
            auctionImpl,
            treasuryImpl,
            tokenImpl,
            metadataRendererImpl,
            protocolRewards,
            weth,
            builderRewardsRecipient,
            chainID,
            deploySalt
        );
    }

    // solhint-disable-next-line function-max-lines
    function _deployUpgrade(
        address deployerAddress,
        IManager managerProxy,
        address oldManagerImpl,
        address oldGovernorImpl,
        address auctionImpl,
        address treasuryImpl,
        address tokenImpl,
        address metadataRendererImpl,
        address protocolRewards,
        address weth,
        address builderRewardsRecipient,
        uint256 chainID,
        bytes32 deploySalt
    ) private {
        console2.log("~~~~~~~~~~ CHAIN ID ~~~~~~~~~~~");
        console2.log(chainID);
        console2.log("~~~~~~~~~~ DEPLOYER ~~~~~~~~~~~");
        console2.log(deployerAddress);
        console2.log("~~~~~~~~~~ DEPLOY SALT ~~~~~~~~~~~");
        console2.logBytes32(deploySalt);
        console2.log("~~~~~~~~~~ MANAGER PROXY ~~~~~~~~~~~");
        console2.logAddress(address(managerProxy));
        console2.log("~~~~~~~~~~ OLD GOVERNOR IMPL ~~~~~~~~~~~");
        console2.logAddress(oldGovernorImpl);
        console2.log("~~~~~~~~~~ OLD MANAGER IMPL ~~~~~~~~~~~");
        console2.logAddress(oldManagerImpl);

        vm.startBroadcast(deployerAddress);

        // Deploy DAOFactory via CREATE3 for cross-chain deterministic DAO deployments
        // DAOFactory acts as the canonical deployer, enabling identical DAO addresses across chains
        // despite different Manager addresses. Bound to this specific Manager proxy.
        address daoFactory = DeployHelpers.deployViaCreate3(
            abi.encodePacked(type(DAOFactory).creationCode, abi.encode(address(managerProxy))), _deriveSalt(deploySalt, DAO_FACTORY_SALT)
        );

        // Deploy all new implementations via CREATE3 factory for bytecode-independent cross-chain determinism
        // CREATE3 enables identical addresses even when constructor args differ per chain

        // Token implementation
        address newTokenImpl = DeployHelpers.deployViaCreate3(
            abi.encodePacked(type(Token).creationCode, abi.encode(address(managerProxy))), _deriveSalt(deploySalt, TOKEN_IMPL_SALT)
        );

        // MetadataRenderer implementation
        address newMetadataRendererImpl = DeployHelpers.deployViaCreate3(
            abi.encodePacked(type(MetadataRenderer).creationCode, abi.encode(address(managerProxy))),
            _deriveSalt(deploySalt, METADATA_RENDERER_IMPL_SALT)
        );

        // Auction implementation
        address newAuctionImpl = DeployHelpers.deployViaCreate3(
            abi.encodePacked(
                type(Auction).creationCode,
                abi.encode(address(managerProxy), protocolRewards, weth, Constants.REWARD_BUILDER_BPS, Constants.REWARD_REFERRAL_BPS)
            ),
            _deriveSalt(deploySalt, AUCTION_IMPL_SALT)
        );

        // Treasury implementation
        address newTreasuryImpl = DeployHelpers.deployViaCreate3(
            abi.encodePacked(type(Treasury).creationCode, abi.encode(address(managerProxy))), _deriveSalt(deploySalt, TREASURY_IMPL_SALT)
        );

        // Governor implementation
        address newGovernorImpl = DeployHelpers.deployViaCreate3(
            abi.encodePacked(type(Governor).creationCode, abi.encode(address(managerProxy))), _deriveSalt(deploySalt, GOVERNOR_IMPL_SALT)
        );

        // Manager implementation
        address newManagerImpl = DeployHelpers.deployViaCreate3(
            abi.encodePacked(
                type(Manager).creationCode,
                abi.encode(
                    newTokenImpl, newMetadataRendererImpl, newAuctionImpl, newTreasuryImpl, newGovernorImpl, builderRewardsRecipient, daoFactory
                )
            ),
            _deriveSalt(deploySalt, MANAGER_IMPL_SALT)
        );

        // NOTE: the following upgrade steps are commented out because they are only needed for testnet, on mainnet the upgrade is done via multisigs
        // managerProxy.upgradeTo(newManagerImpl);
        // managerProxy.registerUpgrade(tokenImpl, newTokenImpl);
        // managerProxy.registerUpgrade(metadataRendererImpl, newMetadataRendererImpl);
        // managerProxy.registerUpgrade(auctionImpl, newAuctionImpl);
        // managerProxy.registerUpgrade(treasuryImpl, newTreasuryImpl);
        // managerProxy.registerUpgrade(oldGovernorImpl, newGovernorImpl);

        vm.stopBroadcast();

        string memory filePath = string(abi.encodePacked("deploys/", chainID.toString(), ".version3_upgrade.txt"));

        vm.writeFile(filePath, "");
        vm.writeLine(filePath, string(abi.encodePacked("Deploy Salt: ", bytes32ToString(deploySalt))));
        vm.writeLine(filePath, string(abi.encodePacked("DAO Factory: ", addressToString(daoFactory))));
        vm.writeLine(filePath, string(abi.encodePacked("Old Token implementation: ", addressToString(tokenImpl))));
        vm.writeLine(filePath, string(abi.encodePacked("New Token implementation: ", addressToString(newTokenImpl))));
        vm.writeLine(filePath, string(abi.encodePacked("Old Metadata Renderer implementation: ", addressToString(metadataRendererImpl))));
        vm.writeLine(filePath, string(abi.encodePacked("New Metadata Renderer implementation: ", addressToString(newMetadataRendererImpl))));
        vm.writeLine(filePath, string(abi.encodePacked("Old Auction implementation: ", addressToString(auctionImpl))));
        vm.writeLine(filePath, string(abi.encodePacked("New Auction implementation: ", addressToString(newAuctionImpl))));
        vm.writeLine(filePath, string(abi.encodePacked("Old Treasury implementation: ", addressToString(treasuryImpl))));
        vm.writeLine(filePath, string(abi.encodePacked("New Treasury implementation: ", addressToString(newTreasuryImpl))));
        vm.writeLine(filePath, string(abi.encodePacked("Old Governor implementation: ", addressToString(oldGovernorImpl))));
        vm.writeLine(filePath, string(abi.encodePacked("New Governor implementation: ", addressToString(newGovernorImpl))));
        vm.writeLine(filePath, string(abi.encodePacked("Old Manager implementation: ", addressToString(oldManagerImpl))));
        vm.writeLine(filePath, string(abi.encodePacked("New Manager implementation: ", addressToString(newManagerImpl))));

        console2.log("~~~~~~~~~~ DAO FACTORY ~~~~~~~~~~~");
        console2.logAddress(daoFactory);
        console2.log("~~~~~~~~~~ NEW TOKEN IMPL ~~~~~~~~~~~");
        console2.logAddress(newTokenImpl);
        console2.log("~~~~~~~~~~ NEW METADATA RENDERER IMPL ~~~~~~~~~~~");
        console2.logAddress(newMetadataRendererImpl);
        console2.log("~~~~~~~~~~ NEW AUCTION IMPL ~~~~~~~~~~~");
        console2.logAddress(newAuctionImpl);
        console2.log("~~~~~~~~~~ NEW TREASURY IMPL ~~~~~~~~~~~");
        console2.logAddress(newTreasuryImpl);
        console2.log("~~~~~~~~~~ NEW GOVERNOR IMPL ~~~~~~~~~~~");
        console2.logAddress(newGovernorImpl);
        console2.log("~~~~~~~~~~ NEW MANAGER IMPL ~~~~~~~~~~~");
        console2.logAddress(newManagerImpl);
    }

    function addressToString(address _addr) private pure returns (string memory) {
        return DeployHelpers.addressToString(_addr);
    }

    function bytes32ToString(bytes32 _bytes) private pure returns (string memory) {
        return DeployHelpers.bytes32ToString(_bytes);
    }
}
