// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.30;

import {TokenRegistry} from "../../src/TokenRegistry.sol";

/// @title MaliciousTokenRegistryAdmin
/// @notice Malicious contract for testing access control bypass attempts
contract MaliciousTokenRegistryAdmin {
    /// @notice Attempts to add a token without proper authorization
    /// @param tokenRegistry The TokenRegistry contract to attack
    /// @param token The token address to add
    function attemptMaliciousTokenAdd(TokenRegistry tokenRegistry, address token) external {
        // This should fail due to access control
        tokenRegistry.addToken(token, TokenRegistry.BridgeTypeLocal.MintBurn, 1000e18);
    }

    /// @notice Attempts to manipulate bridge type without authorization
    /// @param tokenRegistry The TokenRegistry contract to attack
    /// @param token The token address to modify
    function attemptBridgeTypeManipulation(TokenRegistry tokenRegistry, address token) external {
        tokenRegistry.setTokenBridgeType(token, TokenRegistry.BridgeTypeLocal.LockUnlock);
    }

    /// @notice Attempts to manipulate transfer accumulator cap without authorization
    /// @param tokenRegistry The TokenRegistry contract to attack
    /// @param token The token address to modify
    function attemptCapManipulation(TokenRegistry tokenRegistry, address token) external {
        tokenRegistry.setTokenTransferAccumulatorCap(token, type(uint256).max);
    }

    /// @notice Attempts to update transfer accumulator without authorization
    /// @param tokenRegistry The TokenRegistry contract to attack
    /// @param token The token address to modify
    function attemptAccumulatorUpdate(TokenRegistry tokenRegistry, address token) external {
        tokenRegistry.updateTokenTransferAccumulator(token, 1000e18);
    }

    /// @notice Attempts to add destination chain keys without authorization
    /// @param tokenRegistry The TokenRegistry contract to attack
    /// @param token The token address to modify
    /// @param chainKey The chain key to add
    /// @param destTokenAddr The destination token address
    function attemptDestChainKeyAdd(TokenRegistry tokenRegistry, address token, bytes32 chainKey, bytes32 destTokenAddr)
        external
    {
        tokenRegistry.addTokenDestChainKey(token, chainKey, destTokenAddr, 18);
    }

    /// @notice Attempts multiple malicious operations in sequence
    /// @param tokenRegistry The TokenRegistry contract to attack
    /// @param token The token address to manipulate
    function attemptMultipleMaliciousOps(TokenRegistry tokenRegistry, address token) external {
        try tokenRegistry.addToken(token, TokenRegistry.BridgeTypeLocal.MintBurn, 1000e18) {
            // If this succeeds (shouldn't), try more operations
            tokenRegistry.setTokenTransferAccumulatorCap(token, type(uint256).max);
            tokenRegistry.updateTokenTransferAccumulator(token, type(uint256).max);
        } catch {
            // Expected to fail due to access control
        }
    }
}
