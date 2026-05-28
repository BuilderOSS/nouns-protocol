// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { IWalletExecutionAdapter } from "../../../src/bridge/interfaces/IWalletExecutionAdapter.sol";

contract MockWalletExecutionAdapter is IWalletExecutionAdapter {
    function execute(address, address _target, uint256 _value, bytes calldata _data, uint8)
        external
        returns (bytes memory returnData)
    {
        (bool success, bytes memory _returnData) = _target.call{ value: _value }(_data);
        require(success, "EXEC_FAILED");
        return _returnData;
    }
}
