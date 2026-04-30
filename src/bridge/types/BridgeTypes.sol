// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

/// @notice Common bridge-related custom types
interface BridgeTypes {
    enum BridgeMode {
        MANAGED,
        SOVEREIGN
    }

    enum CommandType {
        EXECUTE,
        ADD_WALLET,
        UPDATE_WALLET,
        REMOVE_WALLET,
        SET_POLICY,
        SET_ADAPTER,
        SET_MODE
    }

    struct BridgeEnvelope {
        bytes32 daoId;
        uint256 sourceChainId;
        uint256 destinationChainId;
        address sourceSender;
        uint64 nonce;
        uint64 deadline;
        bytes payload;
    }

    struct Command {
        CommandType commandType;
        bytes data;
    }

    struct ExecuteCommand {
        uint32 walletId;
        address target;
        uint256 value;
        bytes data;
        uint8 operation;
    }

    struct WalletConfig {
        address wallet;
        address adapter;
        address policy;
        bytes32 policyHash;
        bool active;
    }

    struct WalletConfigCommand {
        uint32 walletId;
        address wallet;
        address adapter;
        address policy;
        bytes32 policyHash;
        bool active;
    }

    struct RemoveWalletCommand {
        uint32 walletId;
    }

    struct SetPolicyCommand {
        address policy;
        uint8 threshold;
        uint32 adapterSetVersion;
    }

    struct SetAdapterCommand {
        uint8 adapterId;
        address adapter;
    }

    struct SetModeCommand {
        BridgeMode mode;
        uint64 eta;
        bool execute;
        bool cancel;
    }
}
