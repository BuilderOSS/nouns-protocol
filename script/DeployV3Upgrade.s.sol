// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.35;

import "forge-std/Script.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

import { IManager } from "../src/manager/IManager.sol";
import { Manager } from "../src/manager/Manager.sol";
import { Governor } from "../src/governance/governor/Governor.sol";

contract DeployV3Upgrade is Script {
    using Strings for uint256;

    string configFile;

    function _getKey(string memory key) internal view returns (address result) {
        (result) = abi.decode(vm.parseJson(configFile, string.concat(".", key)), (address));
    }

    function run() public {
        uint256 chainID = block.chainid;

        configFile = vm.readFile(string.concat("./addresses/", Strings.toString(chainID), ".json"));

        address deployerAddress = vm.addr(vm.envUint("PRIVATE_KEY"));
        IManager managerProxy = IManager(_getKey("Manager"));
        address oldManagerImpl = _getKey("ManagerImpl");
        address oldGovernorImpl = _getKey("Governor");
        address auctionImpl = _getKey("Auction");
        address treasuryImpl = _getKey("Treasury");
        address tokenImpl = _getKey("Token");
        address metadataRendererImpl = _getKey("MetadataRenderer");
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
            builderRewardsRecipient,
            chainID
        );
    }

    function _deployUpgrade(
        address deployerAddress,
        IManager managerProxy,
        address oldManagerImpl,
        address oldGovernorImpl,
        address auctionImpl,
        address treasuryImpl,
        address tokenImpl,
        address metadataRendererImpl,
        address builderRewardsRecipient,
        uint256 chainID
    ) private {
        console2.log("~~~~~~~~~~ CHAIN ID ~~~~~~~~~~~");
        console2.log(chainID);
        console2.log("~~~~~~~~~~ DEPLOYER ~~~~~~~~~~~");
        console2.log(deployerAddress);
        console2.log("~~~~~~~~~~ MANAGER PROXY ~~~~~~~~~~~");
        console2.logAddress(address(managerProxy));
        console2.log("~~~~~~~~~~ OLD GOVERNOR IMPL ~~~~~~~~~~~");
        console2.logAddress(oldGovernorImpl);
        console2.log("~~~~~~~~~~ OLD MANAGER IMPL ~~~~~~~~~~~");
        console2.logAddress(oldManagerImpl);

        vm.startBroadcast(deployerAddress);

        address newGovernorImpl = address(new Governor(address(managerProxy)));
        address newManagerImpl =
            address(new Manager(tokenImpl, metadataRendererImpl, auctionImpl, treasuryImpl, newGovernorImpl, builderRewardsRecipient));

        managerProxy.upgradeTo(newManagerImpl);

        vm.stopBroadcast();

        string memory filePath = string(abi.encodePacked("deploys/", chainID.toString(), ".version3_upgrade.txt"));

        vm.writeFile(filePath, "");
        vm.writeLine(filePath, string(abi.encodePacked("Old Governor implementation: ", addressToString(oldGovernorImpl))));
        vm.writeLine(filePath, string(abi.encodePacked("New Governor implementation: ", addressToString(newGovernorImpl))));
        vm.writeLine(filePath, string(abi.encodePacked("Old Manager implementation: ", addressToString(oldManagerImpl))));
        vm.writeLine(filePath, string(abi.encodePacked("New Manager implementation: ", addressToString(newManagerImpl))));

        console2.log("~~~~~~~~~~ NEW GOVERNOR IMPL ~~~~~~~~~~~");
        console2.logAddress(newGovernorImpl);
        console2.log("~~~~~~~~~~ NEW MANAGER IMPL ~~~~~~~~~~~");
        console2.logAddress(newManagerImpl);
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
}
