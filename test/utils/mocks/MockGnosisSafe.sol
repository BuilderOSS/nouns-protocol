// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

contract MockGnosisSafe {
    mapping(address => bool) public modules;

    error ONLY_MODULE();
    error INVALID_OPERATION();

    function enableModule(address _module) external {
        modules[_module] = true;
    }

    function disableModule(address _module) external {
        modules[_module] = false;
    }

    function isModuleEnabled(address _module) external view returns (bool) {
        return modules[_module];
    }

    function execTransactionFromModuleReturnData(address _to, uint256 _value, bytes memory _data, uint8 _operation)
        external
        returns (bool success, bytes memory returnData)
    {
        if (!modules[msg.sender]) revert ONLY_MODULE();
        if (_operation != 0) revert INVALID_OPERATION();

        (success, returnData) = _to.call{ value: _value }(_data);
    }

    receive() external payable {}
}
