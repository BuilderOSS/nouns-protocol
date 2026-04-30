// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { IVerificationPolicy } from "../interfaces/IVerificationPolicy.sol";

/// @notice Default verification policy for v1 single-adapter execution
contract SingleAdapterPolicy is IVerificationPolicy {
    function isSatisfied(uint8 attestationCount, uint8 threshold, uint32) external pure returns (bool) {
        if (threshold == 0) return attestationCount > 0;
        return attestationCount >= threshold;
    }
}
