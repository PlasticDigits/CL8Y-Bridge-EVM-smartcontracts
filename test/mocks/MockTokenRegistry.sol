// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.30;

import {TokenRegistry} from "../../src/TokenRegistry.sol";

contract MockTokenRegistry {
    mapping(address token => mapping(bytes32 destChainKey => bool)) public isTokenDestChainKeyRegistered;
    mapping(address token => mapping(bytes32 destChainKey => bytes32)) public tokenDestChainTokenAddress;
    mapping(address token => TokenRegistry.BridgeTypeLocal) public tokenBridgeType;
    mapping(address token => uint256) public transferAccumulator;
    mapping(address token => uint256) public transferAccumulatorCap;

    bool public shouldRevertOnNotRegistered = false;
    bool public shouldRevertOnCapExceeded = false;

    function setTokenDestChainKeyRegistered(address token, bytes32 destChainKey, bool registered) external {
        isTokenDestChainKeyRegistered[token][destChainKey] = registered;
    }

    function setTokenDestChainTokenAddress(address token, bytes32 destChainKey, bytes32 tokenAddress) external {
        tokenDestChainTokenAddress[token][destChainKey] = tokenAddress;
    }

    function setTokenBridgeType(address token, TokenRegistry.BridgeTypeLocal bridgeType) external {
        tokenBridgeType[token] = bridgeType;
    }

    function setTransferAccumulatorCap(address token, uint256 cap) external {
        transferAccumulatorCap[token] = cap;
    }

    function setTransferAccumulator(address token, uint256 amount) external {
        transferAccumulator[token] = amount;
    }

    function setShouldRevertOnNotRegistered(bool shouldRevert) external {
        shouldRevertOnNotRegistered = shouldRevert;
    }

    function setShouldRevertOnCapExceeded(bool shouldRevert) external {
        shouldRevertOnCapExceeded = shouldRevert;
    }

    function revertIfTokenDestChainKeyNotRegistered(address token, bytes32 destChainKey) external view {
        if (shouldRevertOnNotRegistered || !isTokenDestChainKeyRegistered[token][destChainKey]) {
            revert("Token dest chain key not registered");
        }
    }

    function revertIfOverTransferAccumulatorCap(address token, uint256 amount) external view {
        if (shouldRevertOnCapExceeded || transferAccumulator[token] + amount > transferAccumulatorCap[token]) {
            revert("Over transfer accumulator cap");
        }
    }

    function getTokenDestChainTokenAddress(address token, bytes32 destChainKey) external view returns (bytes32) {
        return tokenDestChainTokenAddress[token][destChainKey];
    }

    function getTokenBridgeType(address token) external view returns (TokenRegistry.BridgeTypeLocal) {
        return tokenBridgeType[token];
    }

    function updateTokenTransferAccumulator(address token, uint256 amount) external {
        transferAccumulator[token] += amount;
    }
}
