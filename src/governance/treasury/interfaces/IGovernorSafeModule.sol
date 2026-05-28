// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

/// @notice Treasury-compatible execution module for a Gnosis Safe avatar
interface IGovernorSafeModule {
    function treasury() external view returns (address);

    function execTransactionFromModule(address safe, address target, uint256 value, bytes calldata data, uint8 operation)
        external
        returns (bytes memory returnData);
}
