// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { IGnosisSafe } from "./interfaces/IGnosisSafe.sol";
import { IGovernorSafeModule } from "./interfaces/IGovernorSafeModule.sol";

/// @title GovernorSafeModule
/// @author Nouns Builder
/// @notice Minimal module bridge that lets treasury trigger enabled safe module execution
contract GovernorSafeModule is IGovernorSafeModule {
    /// @notice Treasury authorized to route calls through this module
    address public immutable treasury;

    error ONLY_TREASURY();
    error ADDRESS_ZERO();
    error MODULE_EXECUTION_FAILED();

    constructor(address _treasury) {
        if (_treasury == address(0)) revert ADDRESS_ZERO();
        treasury = _treasury;
    }

    /// @notice Execute a transaction from an enabled module context on Safe
    /// @dev The safe must have this module enabled
    function execTransactionFromModule(address _safe, address _target, uint256 _value, bytes calldata _data, uint8 _operation)
        external
        returns (bytes memory returnData)
    {
        if (msg.sender != treasury) revert ONLY_TREASURY();
        if (_safe == address(0) || _target == address(0)) revert ADDRESS_ZERO();

        (bool success, bytes memory _returnData) =
            IGnosisSafe(_safe).execTransactionFromModuleReturnData(_target, _value, _data, _operation);
        if (!success) revert MODULE_EXECUTION_FAILED();

        return _returnData;
    }
}
