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

        // Get optional params with defaults
        address destManagedAdmin = bridgeOwner;
        address destGuardian = bridgeOwner;
        uint8 bridgeMode = 0; // MANAGED by default
        uint8 verificationThreshold = 1;
        uint64 modeChangeMinDelay = uint64(1 days);
        uint64 modeChangeCooldown = uint64(1 days);

        // Try to read optional environment variables
        try vm.envAddress("DEST_MANAGED_ADMIN") returns (address addr) {
            destManagedAdmin = addr;
        } catch {}
        try vm.envAddress("DEST_GUARDIAN") returns (address addr) {
            destGuardian = addr;
        } catch {}
        try vm.envUint("BRIDGE_MODE") returns (uint256 mode) {
            bridgeMode = uint8(mode);
        } catch {}
        try vm.envUint("VERIFICATION_THRESHOLD") returns (uint256 threshold) {
            verificationThreshold = uint8(threshold);
        } catch {}
        try vm.envUint("MODE_CHANGE_MIN_DELAY") returns (uint256 delay) {
            modeChangeMinDelay = uint64(delay);
        } catch {}
        try vm.envUint("MODE_CHANGE_COOLDOWN") returns (uint256 cooldown) {
            modeChangeCooldown = uint64(cooldown);
        } catch {}

        IManager.BridgeDeployParams memory params = IManager.BridgeDeployParams({
            daoId: vm.envBytes32("DAO_ID"),
            sourceTreasury: vm.envAddress("SOURCE_TREASURY"),
            sourceChainId: vm.envUint("SOURCE_CHAIN_ID"),
            destinationChainId: vm.envUint("DESTINATION_CHAIN_ID"),
            destinationEid: uint32(vm.envUint("DESTINATION_EID")),
            transportAdapterId: uint8(vm.envUint("TRANSPORT_ADAPTER_ID")),
            layerZeroEndpoint: vm.envAddress("LZ_ENDPOINT"),
            bridgeOwner: bridgeOwner,
            destinationManagedAdmin: destManagedAdmin,
            destinationGuardian: destGuardian,
            mode: BridgeTypes.BridgeMode(bridgeMode),
            verificationThreshold: verificationThreshold,
            modeChangeMinDelay: modeChangeMinDelay,
            modeChangeCooldown: modeChangeCooldown
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
