// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

abstract contract VersionedContract {
    function contractVersion() external pure returns (string memory) {
        return "2.1.0";
    }
}
