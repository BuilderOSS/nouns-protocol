// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.35;

import { Script, console2 } from "forge-std/Script.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

import { IManager } from "../src/manager/IManager.sol";

contract SetupDaoScript is Script {
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

        bytes memory initStrings = abi.encode(
            "Test 999", "TST", "This is the desc", "https://contract-image.png", "https://project-uri.json", "https://renderer.com/render"
        );

        IManager.TokenParams memory tokenParams =
            IManager.TokenParams({ initStrings: initStrings, metadataRenderer: address(0), reservedUntilTokenId: 10 });

        IManager.AuctionParams memory auctionParams =
            IManager.AuctionParams({ duration: 24 hours, reservePrice: 0.01 ether, founderRewardRecipent: address(0xB0B), founderRewardBps: 20 });

        IManager.GovParams memory govParams = IManager.GovParams({
            votingDelay: 2 days, votingPeriod: 2 days, proposalThresholdBps: 50, quorumThresholdBps: 1000, vetoer: address(0), timelockDelay: 2 days
        });

        IManager.FounderParams[] memory founders = new IManager.FounderParams[](1);
        founders[0] = IManager.FounderParams({ wallet: deployerAddress, ownershipPct: 10, vestExpiry: 30 days });

        IManager manager = IManager(_getKey("Manager"));

        (address token, address metadata, address auction, address treasury, address governor) =
            manager.predictDeterministicAddresses(deployerAddress, deploySalt);

        console2.log("~~~~~~~~~~ PREDICTED TOKEN ~~~~~~~~~~~");
        console2.logAddress(token);
        console2.log("~~~~~~~~~~ PREDICTED METADATA ~~~~~~~~~~~");
        console2.logAddress(metadata);
        console2.log("~~~~~~~~~~ PREDICTED AUCTION ~~~~~~~~~~~");
        console2.logAddress(auction);
        console2.log("~~~~~~~~~~ PREDICTED TREASURY ~~~~~~~~~~~");
        console2.logAddress(treasury);
        console2.log("~~~~~~~~~~ PREDICTED GOVERNOR ~~~~~~~~~~~");
        console2.logAddress(governor);

        _requireNotDeployed(token, "TOKEN_ALREADY_DEPLOYED");
        _requireNotDeployed(metadata, "METADATA_ALREADY_DEPLOYED");
        _requireNotDeployed(auction, "AUCTION_ALREADY_DEPLOYED");
        _requireNotDeployed(treasury, "TREASURY_ALREADY_DEPLOYED");
        _requireNotDeployed(governor, "GOVERNOR_ALREADY_DEPLOYED");

        vm.startBroadcast(deployerAddress);

        manager.deployDeterministic(founders, tokenParams, auctionParams, govParams, deploySalt);

        //now that we have a DAO process a proposal

        vm.stopBroadcast();
    }

    function _requireNotDeployed(address target, string memory message) internal view {
        if (target.code.length != 0) revert(message);
    }
}
