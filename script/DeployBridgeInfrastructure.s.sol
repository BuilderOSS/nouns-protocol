// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import { IManager } from "../src/manager/IManager.sol";
import { BridgeTypes } from "../src/bridge/types/BridgeTypes.sol";

contract DeployBridgeInfrastructure is Script {
    function run() external {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address broadcaster = vm.addr(privateKey);

        address managerAddress = vm.envAddress("MANAGER");
        address bridgeOwner = vm.envAddress("BRIDGE_OWNER");

        IManager.BridgeDeployParams memory params = IManager.BridgeDeployParams({
            daoId: vm.envBytes32("DAO_ID"),
            sourceTreasury: vm.envAddress("SOURCE_TREASURY"),
            sourceChainId: vm.envUint("SOURCE_CHAIN_ID"),
            destinationChainId: vm.envUint("DESTINATION_CHAIN_ID"),
            destinationEid: uint32(vm.envUint("DESTINATION_EID")),
            transportAdapterId: uint8(vm.envUint("TRANSPORT_ADAPTER_ID")),
            layerZeroEndpoint: vm.envAddress("LZ_ENDPOINT"),
            bridgeOwner: bridgeOwner,
            destinationManagedAdmin: vm.envOr("DEST_MANAGED_ADMIN", bridgeOwner),
            destinationGuardian: vm.envOr("DEST_GUARDIAN", bridgeOwner),
            mode: BridgeTypes.BridgeMode(uint8(vm.envOr("BRIDGE_MODE", uint256(0)))),
            verificationThreshold: uint8(vm.envOr("VERIFICATION_THRESHOLD", uint256(1))),
            modeChangeMinDelay: uint64(vm.envOr("MODE_CHANGE_MIN_DELAY", uint256(1 days))),
            modeChangeCooldown: uint64(vm.envOr("MODE_CHANGE_COOLDOWN", uint256(1 days)))
        });

        vm.startBroadcast(broadcaster);
        IManager.BridgeAddresses memory deployed = IManager(managerAddress).deployBridgeInfrastructure(params);
        vm.stopBroadcast();

        console2.log("sourceBridgeAdapter", deployed.sourceBridgeAdapter);
        console2.log("destinationExecutor", deployed.destinationExecutor);
        console2.log("transportAdapter", deployed.transportAdapter);
        console2.log("safeWalletAdapter", deployed.safeWalletAdapter);
        console2.log("verificationPolicy", deployed.verificationPolicy);
    }
}
