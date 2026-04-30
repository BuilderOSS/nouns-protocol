// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

interface IVerificationPolicy {
    function isSatisfied(uint8 attestationCount, uint8 threshold, uint32 adapterSetVersion)
        external
        view
        returns (bool);
}
