// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

/// @notice Minimal LayerZero endpoint v2 send interface used by adapter
interface ILayerZeroEndpointV2 {
    function send(uint32 dstEid, bytes calldata message, bytes calldata options, address payable refundAddress)
        external
        payable
        returns (bytes32 guid);
}
