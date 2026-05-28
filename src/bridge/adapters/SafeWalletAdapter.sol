// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { IWalletExecutionAdapter } from "../interfaces/IWalletExecutionAdapter.sol";
import { IGnosisSafe } from "../../governance/treasury/interfaces/IGnosisSafe.sol";

/// @notice Wallet adapter that executes calls through an enabled Safe module path
contract SafeWalletAdapter is IWalletExecutionAdapter {
    uint8 internal constant SAFE_OP_CALL = 0;

    address public immutable executor;

    error ONLY_EXECUTOR();
    error INVALID_ADDRESS();
    error INVALID_OPERATION();
    error SAFE_EXECUTION_FAILED();

    constructor(address _executor) {
        if (_executor == address(0)) revert INVALID_ADDRESS();
        executor = _executor;
    }

    function execute(address _wallet, address _target, uint256 _value, bytes calldata _data, uint8 _operation)
        external
        returns (bytes memory returnData)
    {
        if (msg.sender != executor) revert ONLY_EXECUTOR();
        if (_wallet == address(0) || _target == address(0)) revert INVALID_ADDRESS();
        if (_operation != SAFE_OP_CALL) revert INVALID_OPERATION();

        (bool success, bytes memory _returnData) =
            IGnosisSafe(_wallet).execTransactionFromModuleReturnData(_target, _value, _data, _operation);
        if (!success) revert SAFE_EXECUTION_FAILED();

        return _returnData;
    }
}
