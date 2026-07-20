// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.35;

import { Script, console2 } from "forge-std/Script.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

import { DeployHelpers } from "./DeployHelpers.sol";
import { DeployConstants } from "./DeployConstants.sol";
import { Manager } from "../src/manager/Manager.sol";
import { ERC721RedeemMinter } from "../src/minters/ERC721RedeemMinter.sol";

contract DeployContracts is Script, DeployConstants {
    using Strings for uint256;

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

        address deployerAddress = vm.addr(key);
        address managerAddress = _getKey("Manager");
        address protocolRewards = _getKey("ProtocolRewards");

        console2.log("~~~~~~~~~~ CHAIN ID ~~~~~~~~~~~");
        console2.log(chainID);

        console2.log("~~~~~~~~~~ DEPLOYER ~~~~~~~~~~~");
        console2.log(deployerAddress);

        console2.log("~~~~~~~~~~ MANAGER ~~~~~~~~~~~");
        console2.log(managerAddress);

        console2.log("~~~~~~~~~~ PROTOCOL REWARDS ~~~~~~~~~~~");
        console2.log(protocolRewards);

        console2.log("~~~~~~~~~~ DEPLOY SALT ~~~~~~~~~~~");
        console2.logBytes32(deploySalt);

        vm.startBroadcast(deployerAddress);

        bytes32 redeemMinterSalt = _deriveSalt(deploySalt, ERC721_REDEEM_MINTER_SALT);
        address predictedRedeemMinter = DeployHelpers.predictCreate3Address(redeemMinterSalt, deployerAddress);
        address redeemMinter = DeployHelpers.deployViaCreate3(
            abi.encodePacked(type(ERC721RedeemMinter).creationCode, abi.encode(Manager(managerAddress), protocolRewards)), redeemMinterSalt
        );
        require(redeemMinter == predictedRedeemMinter, "ERC721RedeemMinter address mismatch");

        vm.stopBroadcast();

        string memory filePath = string(abi.encodePacked("deploys/", chainID.toString(), ".erc721_redeem_minter.txt"));

        vm.writeFile(filePath, "");
        vm.writeLine(filePath, string(abi.encodePacked("ERC721 Redeem Minter: ", addressToString(redeemMinter))));

        console2.log("~~~~~~~~~~ ERC721 REDEEM MINTER ~~~~~~~~~~~");
        console2.logAddress(redeemMinter);
    }

    function addressToString(address _addr) private pure returns (string memory) {
        return DeployHelpers.addressToString(_addr);
    }
}
