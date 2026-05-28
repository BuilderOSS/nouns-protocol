// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

/// @notice Minimal Gnosis Safe interface used by treasury execution module
interface IGnosisSafe {
    function execTransactionFromModuleReturnData(address to, uint256 value, bytes memory data, uint8 operation)
        external
        returns (bool success, bytes memory returnData);

    function isModuleEnabled(address module) external view returns (bool);
}
