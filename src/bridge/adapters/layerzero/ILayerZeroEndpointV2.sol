// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

/// @notice Origin struct passed to lzReceive
struct Origin {
    uint32 srcEid;
    bytes32 sender;
    uint64 nonce;
}

/// @notice Minimal LayerZero endpoint v2 interface used by adapter
interface ILayerZeroEndpointV2 {
    function send(uint32 dstEid, bytes calldata message, bytes calldata options, address payable refundAddress)
        external
        payable
        returns (bytes32 guid);

    function quote(uint32 dstEid, bytes calldata message, bytes calldata options, bool payInLzToken)
        external
        view
        returns (uint256 nativeFee, uint256 lzTokenFee);

    function setDelegate(address delegate) external;
}
