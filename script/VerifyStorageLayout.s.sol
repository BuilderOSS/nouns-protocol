// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Script.sol";

/**
 * @title VerifyStorageLayout
 * @notice Script to verify storage layout hasn't changed for upgradeable contracts
 * @dev Run this before any upgrade to ensure storage safety
 *
 * Usage:
 *   forge script script/VerifyStorageLayout.s.sol
 *
 * This script generates storage layouts and compares against baseline files.
 * Baseline files are stored in repository:
 *   - .storage-layout-manager.txt
 *   - .storage-layout-treasury.txt
 *   - .storage-layout-governor.txt
 *
 * To update baselines after intentional storage changes:
 *   1. Review the changes carefully
 *   2. Ensure new storage slots are appended, not inserted
 *   3. Run: make update-storage-layout
 *   4. Commit the updated baseline files
 */
contract VerifyStorageLayout is Script {
    string[] public contracts = [
        "src/manager/Manager.sol:Manager",
        "src/governance/treasury/Treasury.sol:Treasury",
        "src/governance/governor/Governor.sol:Governor"
    ];

    string[] public baselineFiles = [
        ".storage-layout-manager.txt",
        ".storage-layout-treasury.txt",
        ".storage-layout-governor.txt"
    ];

    function run() external {
        console.log("=== Storage Layout Verification ===\n");

        bool allMatch = true;

        for (uint256 i = 0; i < contracts.length; i++) {
            console.log("Checking:", contracts[i]);

            // Generate current storage layout
            string[] memory inputs = new string[](5);
            inputs[0] = "forge";
            inputs[1] = "inspect";
            inputs[2] = contracts[i];
            inputs[3] = "storage-layout";
            inputs[4] = "--silent";

            bytes memory currentLayout = vm.ffi(inputs);

            // Read baseline
            string memory baselinePath = string.concat(vm.projectRoot(), "/", baselineFiles[i]);

            try vm.readFile(baselinePath) returns (string memory baselineContent) {
                bytes memory baselineLayout = bytes(baselineContent);

                // Compare
                if (keccak256(currentLayout) == keccak256(baselineLayout)) {
                    console.log("  [OK] Storage layout matches baseline\n");
                } else {
                    console.log("  [FAIL] STORAGE LAYOUT MISMATCH!");
                    console.log("  Baseline file:", baselineFiles[i]);
                    console.log("  This may indicate a dangerous storage collision.");
                    console.log("  Review changes carefully before proceeding.\n");
                    allMatch = false;
                }
            } catch {
                console.log("  [WARN] No baseline file found:", baselineFiles[i]);
                console.log("  Run 'make update-storage-layout' to create baseline.\n");
                allMatch = false;
            }
        }

        if (allMatch) {
            console.log("=== All storage layouts verified ===");
        } else {
            console.log("=== VERIFICATION FAILED ===");
            console.log("Storage layout changes detected or baselines missing.");
            revert("Storage layout verification failed");
        }
    }
}
