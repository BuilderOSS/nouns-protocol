// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

interface IWalletExecutionAdapter {
    function execute(address wallet, address target, uint256 value, bytes calldata data, uint8 operation)
        external
        returns (bytes memory returnData);
}
