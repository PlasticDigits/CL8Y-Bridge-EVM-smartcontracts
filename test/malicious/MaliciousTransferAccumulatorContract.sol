// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.30;

import {TokenRegistry} from "../../src/TokenRegistry.sol";

/// @title MaliciousTransferAccumulatorContract
/// @notice Malicious contract for testing transfer accumulator manipulation attempts
contract MaliciousTransferAccumulatorContract {
    TokenRegistry public immutable tokenRegistry;
    uint256 public attemptCount;

    constructor(TokenRegistry _tokenRegistry) {
        tokenRegistry = _tokenRegistry;
    }

    /// @notice Attempts to manipulate transfer accumulator directly
    /// @param token The token to manipulate
    function attemptAccumulatorManipulation(address token) external {
        attemptCount++;
        // This should fail due to access control
        tokenRegistry.updateTokenTransferAccumulator(token, 1000e18);
    }

    /// @notice Attempts to bypass accumulator cap by multiple small updates
    /// @param token The token to manipulate
    /// @param amounts Array of amounts to try updating
    function attemptCapBypass(address token, uint256[] calldata amounts) external {
        for (uint256 i = 0; i < amounts.length; i++) {
            try tokenRegistry.updateTokenTransferAccumulator(token, amounts[i]) {
                attemptCount++;
            } catch {
                // Expected to fail
                break;
            }
        }
    }

    /// @notice Attempts to exploit time window by manipulating block.timestamp
    /// @param token The token to manipulate
    function attemptTimeManipulation(address token) external {
        // Try to update accumulator (should fail due to access control)
        try tokenRegistry.updateTokenTransferAccumulator(token, 500e18) {
            attemptCount++;
        } catch {
            // Expected to fail
        }
    }

    /// @notice Attempts to check accumulator state and exploit any race conditions
    /// @param token The token to check
    function attemptRaceCondition(address token) external {
        TokenRegistry.TransferAccumulator memory accumulator = tokenRegistry.getTokenTransferAccumulator(token);

        // Try to exploit the time difference between reading and writing
        if (accumulator.amount < tokenRegistry.getTokenTransferAccumulatorCap(token)) {
            try tokenRegistry.updateTokenTransferAccumulator(token, 1) {
                attemptCount++;
            } catch {
                // Expected to fail due to access control
            }
        }
    }

    /// @notice Attempts to overflow the accumulator amount
    /// @param token The token to manipulate
    function attemptOverflow(address token) external {
        try tokenRegistry.updateTokenTransferAccumulator(token, type(uint256).max) {
            attemptCount++;
        } catch {
            // Expected to fail
        }
    }

    /// @notice Attempts recursive calls to accumulator functions
    /// @param token The token to manipulate
    /// @param depth Current recursion depth
    function attemptReentrancy(address token, uint256 depth) external {
        if (depth > 0 && depth < 10) {
            try tokenRegistry.updateTokenTransferAccumulator(token, 100e18) {
                this.attemptReentrancy(token, depth - 1);
            } catch {
                // Expected to fail
            }
        }
        attemptCount++;
    }

    /// @notice Reset attempt counter for testing
    function resetAttemptCount() external {
        attemptCount = 0;
    }
}
