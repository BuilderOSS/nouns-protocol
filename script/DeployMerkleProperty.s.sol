// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

import { Script, console2 } from "forge-std/Script.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

import { DeployHelpers } from "./DeployHelpers.sol";
import { MerklePropertyIPFS } from "../src/token/metadata/renderers/MerklePropertyIPFS/MerklePropertyIPFS.sol";

contract DeployMerkleProperty is Script {
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

        console2.log("~~~~~~~~~~ CHAIN ID ~~~~~~~~~~~");
        console2.log(chainID);

        console2.log("~~~~~~~~~~ DEPLOYER ~~~~~~~~~~~");
        console2.log(deployerAddress);

        console2.log("~~~~~~~~~~ DEPLOY SALT ~~~~~~~~~~~");
        console2.logBytes32(deploySalt);

        vm.startBroadcast(deployerAddress);

        address merkleMetadataImpl =
            address(new MerklePropertyIPFS{ salt: _deriveSalt(deploySalt, keccak256("MERKLE_PROPERTY_IPFS")) }(_getKey("Manager")));

        vm.stopBroadcast();

        string memory filePath = string(abi.encodePacked("deploys/", chainID.toString(), ".merkle_property.txt"));

        vm.writeLine(filePath, string(abi.encodePacked("MerklePropertyImpl: ", addressToString(address(merkleMetadataImpl)))));

        console2.log("~~~~~~~~~~ MERKLE PROPERTY IMPL ~~~~~~~~~~~");
        console2.logAddress(merkleMetadataImpl);
    }

    function addressToString(address _addr) private pure returns (string memory) {
        return DeployHelpers.addressToString(_addr);
    }

    function _deriveSalt(bytes32 deploySalt, bytes32 label) private pure returns (bytes32) {
        return keccak256(abi.encode(deploySalt, label));
    }
}
