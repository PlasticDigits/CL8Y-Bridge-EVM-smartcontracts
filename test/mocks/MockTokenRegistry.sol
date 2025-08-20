// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.30;

import {TokenRegistry} from "../../src/TokenRegistry.sol";

contract MockTokenRegistry {
    mapping(address token => mapping(bytes32 destChainKey => bool)) public isTokenDestChainKeyRegistered;
    mapping(address token => mapping(bytes32 destChainKey => bytes32)) public tokenDestChainTokenAddress;
    mapping(address token => TokenRegistry.BridgeTypeLocal) public tokenBridgeType;

    bool public shouldRevertOnNotRegistered = false;

    function setTokenDestChainKeyRegistered(address token, bytes32 destChainKey, bool registered) external {
        isTokenDestChainKeyRegistered[token][destChainKey] = registered;
    }

    function setTokenDestChainTokenAddress(address token, bytes32 destChainKey, bytes32 tokenAddress) external {
        tokenDestChainTokenAddress[token][destChainKey] = tokenAddress;
    }

    function setTokenBridgeType(address token, TokenRegistry.BridgeTypeLocal bridgeType) external {
        tokenBridgeType[token] = bridgeType;
    }

    // Removed accumulator and cap logic; rate limiting is handled by guard modules

    function setShouldRevertOnNotRegistered(bool shouldRevert) external {
        shouldRevertOnNotRegistered = shouldRevert;
    }

    function revertIfTokenDestChainKeyNotRegistered(address token, bytes32 destChainKey) external view {
        if (shouldRevertOnNotRegistered || !isTokenDestChainKeyRegistered[token][destChainKey]) {
            revert("Token dest chain key not registered");
        }
    }

    function getTokenDestChainTokenAddress(address token, bytes32 destChainKey) external view returns (bytes32) {
        return tokenDestChainTokenAddress[token][destChainKey];
    }

    function getTokenBridgeType(address token) external view returns (TokenRegistry.BridgeTypeLocal) {
        return tokenBridgeType[token];
    }

    // No-op: account updates removed
}
