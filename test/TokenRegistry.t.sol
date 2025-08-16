// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {TokenRegistry} from "../src/TokenRegistry.sol";
import {ChainRegistry} from "../src/ChainRegistry.sol";
import {AccessManager} from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

// Mock contracts for testing
import {MockTokenRegistry} from "./mocks/MockTokenRegistry.sol";
import {MockReentrantToken} from "./mocks/MockReentrantToken.sol";
import {MockFailingToken} from "./mocks/MockFailingToken.sol";

// Malicious contracts for security testing
import {MaliciousTokenRegistryAdmin} from "./malicious/MaliciousTokenRegistryAdmin.sol";
import {MaliciousTransferAccumulatorContract} from "./malicious/MaliciousTransferAccumulatorContract.sol";

contract TokenRegistryTest is Test {
    TokenRegistry public tokenRegistry;
    ChainRegistry public chainRegistry;
    AccessManager public accessManager;

    // Test addresses
    address public owner = address(1);
    address public admin = address(2);
    address public user = address(3);
    address public unauthorizedUser = address(4);

    // Test tokens
    address public token1 = address(0x1001);
    address public token2 = address(0x1002);
    address public token3 = address(0x1003);

    // Test chain keys
    bytes32 public chainKey1;
    bytes32 public chainKey2;
    bytes32 public chainKey3;

    // Test token addresses on destination chains
    bytes32 public destTokenAddr1 = bytes32(uint256(0x2001));
    bytes32 public destTokenAddr2 = bytes32(uint256(0x2002));

    // Events to test
    event TokenAdded(address indexed token, TokenRegistry.BridgeTypeLocal bridgeType, uint256 transferAccumulatorCap);

    function setUp() public {
        // Deploy access manager with owner
        vm.prank(owner);
        accessManager = new AccessManager(owner);

        // Deploy chain registry
        chainRegistry = new ChainRegistry(address(accessManager));

        // Deploy token registry
        tokenRegistry = new TokenRegistry(address(accessManager), chainRegistry);

        // Setup roles and permissions
        vm.startPrank(owner);

        uint64 adminRole = 1;
        accessManager.grantRole(adminRole, admin, 0);

        // Set function roles for TokenRegistry
        bytes4[] memory tokenRegistrySelectors = new bytes4[](9);
        tokenRegistrySelectors[0] = tokenRegistry.addToken.selector;
        tokenRegistrySelectors[1] = tokenRegistry.updateTokenTransferAccumulator.selector;
        tokenRegistrySelectors[2] = tokenRegistry.setTokenBridgeType.selector;
        tokenRegistrySelectors[3] = tokenRegistry.setTokenTransferAccumulatorCap.selector;
        tokenRegistrySelectors[4] = tokenRegistry.addTokenDestChainKey.selector;
        tokenRegistrySelectors[5] = tokenRegistry.removeTokenDestChainKey.selector;
        tokenRegistrySelectors[6] = tokenRegistry.setTokenDestChainTokenAddress.selector;

        accessManager.setTargetFunctionRole(address(tokenRegistry), tokenRegistrySelectors, adminRole);

        // Set function roles for ChainRegistry
        bytes4[] memory chainRegistrySelectors = new bytes4[](6);
        chainRegistrySelectors[0] = chainRegistry.addEVMChainKey.selector;
        chainRegistrySelectors[1] = chainRegistry.addCOSMWChainKey.selector;
        chainRegistrySelectors[2] = chainRegistry.addSOLChainKey.selector;
        chainRegistrySelectors[3] = chainRegistry.addOtherChainType.selector;
        chainRegistrySelectors[4] = chainRegistry.addChainKey.selector;
        chainRegistrySelectors[5] = chainRegistry.removeChainKey.selector;

        accessManager.setTargetFunctionRole(address(chainRegistry), chainRegistrySelectors, adminRole);

        vm.stopPrank();

        // Setup test chain keys
        vm.startPrank(admin);
        chainRegistry.addEVMChainKey(1); // Ethereum mainnet
        chainRegistry.addEVMChainKey(56); // BSC
        chainRegistry.addCOSMWChainKey("cosmoshub-4"); // Cosmos Hub

        chainKey1 = chainRegistry.getChainKeyEVM(1);
        chainKey2 = chainRegistry.getChainKeyEVM(56);
        chainKey3 = chainRegistry.getChainKeyCOSMW("cosmoshub-4");
        vm.stopPrank();
    }

    // Constructor Tests
    function test_Constructor() public view {
        assertEq(tokenRegistry.authority(), address(accessManager));
        assertEq(address(tokenRegistry.chainRegistry()), address(chainRegistry));
        assertEq(tokenRegistry.TRANSFER_ACCUMULATOR_WINDOW(), 1 days);
    }

    // Token Management Tests
    function test_AddToken() public {
        vm.prank(admin);
        tokenRegistry.addToken(token1, TokenRegistry.BridgeTypeLocal.MintBurn, 1000e18);

        assertTrue(tokenRegistry.isTokenRegistered(token1));
        assertEq(uint256(tokenRegistry.getTokenBridgeType(token1)), uint256(TokenRegistry.BridgeTypeLocal.MintBurn));
        assertEq(tokenRegistry.getTokenTransferAccumulatorCap(token1), 1000e18);
        assertEq(tokenRegistry.getTokenCount(), 1);
        assertEq(tokenRegistry.getTokenAt(0), token1);
    }

    function test_AddTokenUnauthorized() public {
        vm.prank(unauthorizedUser);
        vm.expectRevert();
        tokenRegistry.addToken(token1, TokenRegistry.BridgeTypeLocal.MintBurn, 1000e18);
    }

    function test_AddMultipleTokens() public {
        vm.startPrank(admin);
        tokenRegistry.addToken(token1, TokenRegistry.BridgeTypeLocal.MintBurn, 1000e18);
        tokenRegistry.addToken(token2, TokenRegistry.BridgeTypeLocal.LockUnlock, 2000e18);
        tokenRegistry.addToken(token3, TokenRegistry.BridgeTypeLocal.MintBurn, 3000e18);
        vm.stopPrank();

        assertEq(tokenRegistry.getTokenCount(), 3);

        address[] memory allTokens = tokenRegistry.getAllTokens();
        assertEq(allTokens.length, 3);
        assertEq(allTokens[0], token1);
        assertEq(allTokens[1], token2);
        assertEq(allTokens[2], token3);
    }

    function test_GetTokensFrom() public {
        vm.startPrank(admin);
        tokenRegistry.addToken(token1, TokenRegistry.BridgeTypeLocal.MintBurn, 1000e18);
        tokenRegistry.addToken(token2, TokenRegistry.BridgeTypeLocal.LockUnlock, 2000e18);
        tokenRegistry.addToken(token3, TokenRegistry.BridgeTypeLocal.MintBurn, 3000e18);
        vm.stopPrank();

        address[] memory tokens = tokenRegistry.getTokensFrom(1, 2);
        assertEq(tokens.length, 2);
        assertEq(tokens[0], token2);
        assertEq(tokens[1], token3);

        // Test out of bounds
        tokens = tokenRegistry.getTokensFrom(5, 2);
        assertEq(tokens.length, 0);

        // Test partial range
        tokens = tokenRegistry.getTokensFrom(2, 5);
        assertEq(tokens.length, 1);
        assertEq(tokens[0], token3);
    }

    // Bridge Type Tests
    function test_SetTokenBridgeType() public {
        vm.startPrank(admin);
        tokenRegistry.addToken(token1, TokenRegistry.BridgeTypeLocal.MintBurn, 1000e18);
        tokenRegistry.setTokenBridgeType(token1, TokenRegistry.BridgeTypeLocal.LockUnlock);
        vm.stopPrank();

        assertEq(uint256(tokenRegistry.getTokenBridgeType(token1)), uint256(TokenRegistry.BridgeTypeLocal.LockUnlock));
    }

    function test_SetTokenBridgeTypeUnauthorized() public {
        vm.startPrank(admin);
        tokenRegistry.addToken(token1, TokenRegistry.BridgeTypeLocal.MintBurn, 1000e18);
        vm.stopPrank();

        vm.prank(unauthorizedUser);
        vm.expectRevert();
        tokenRegistry.setTokenBridgeType(token1, TokenRegistry.BridgeTypeLocal.LockUnlock);
    }

    // Transfer Accumulator Tests
    function test_SetTokenTransferAccumulatorCap() public {
        vm.startPrank(admin);
        tokenRegistry.addToken(token1, TokenRegistry.BridgeTypeLocal.MintBurn, 1000e18);
        tokenRegistry.setTokenTransferAccumulatorCap(token1, 2000e18);
        vm.stopPrank();

        assertEq(tokenRegistry.getTokenTransferAccumulatorCap(token1), 2000e18);
    }

    function test_UpdateTokenTransferAccumulator() public {
        vm.startPrank(admin);
        tokenRegistry.addToken(token1, TokenRegistry.BridgeTypeLocal.MintBurn, 1000e18);

        // Warp to a time that triggers window reset (beyond 1 day)
        vm.warp(block.timestamp + tokenRegistry.TRANSFER_ACCUMULATOR_WINDOW() + 1);
        uint256 expectedWindowStart = block.timestamp;

        tokenRegistry.updateTokenTransferAccumulator(token1, 500e18);
        vm.stopPrank();

        TokenRegistry.TransferAccumulator memory accumulator = tokenRegistry.getTokenTransferAccumulator(token1);
        assertEq(accumulator.amount, 500e18);
        assertEq(accumulator.windowStart, expectedWindowStart);
    }

    function test_UpdateTokenTransferAccumulatorExceedsCap() public {
        vm.startPrank(admin);
        tokenRegistry.addToken(token1, TokenRegistry.BridgeTypeLocal.MintBurn, 1000e18);

        vm.expectRevert(
            abi.encodeWithSelector(TokenRegistry.OverTransferAccumulatorCap.selector, token1, 1500e18, 1500e18, 1000e18)
        );
        tokenRegistry.updateTokenTransferAccumulator(token1, 1500e18);
        vm.stopPrank();
    }

    function test_UpdateTokenTransferAccumulatorWindowReset() public {
        vm.startPrank(admin);
        tokenRegistry.addToken(token1, TokenRegistry.BridgeTypeLocal.MintBurn, 1000e18);
        tokenRegistry.updateTokenTransferAccumulator(token1, 500e18);

        // Fast forward past the window
        vm.warp(block.timestamp + tokenRegistry.TRANSFER_ACCUMULATOR_WINDOW() + 1);

        tokenRegistry.updateTokenTransferAccumulator(token1, 300e18);
        vm.stopPrank();

        TokenRegistry.TransferAccumulator memory accumulator = tokenRegistry.getTokenTransferAccumulator(token1);
        assertEq(accumulator.amount, 300e18); // Should reset and only contain new amount
    }

    function test_RevertIfOverTransferAccumulatorCap() public {
        vm.startPrank(admin);
        tokenRegistry.addToken(token1, TokenRegistry.BridgeTypeLocal.MintBurn, 1000e18);
        tokenRegistry.updateTokenTransferAccumulator(token1, 600e18);
        vm.stopPrank();

        // Should revert when total would exceed cap
        vm.expectRevert(
            abi.encodeWithSelector(TokenRegistry.OverTransferAccumulatorCap.selector, token1, 500e18, 600e18, 1000e18)
        );
        tokenRegistry.revertIfOverTransferAccumulatorCap(token1, 500e18);

        // Should not revert when within cap
        tokenRegistry.revertIfOverTransferAccumulatorCap(token1, 300e18);
    }

    function test_RevertIfOverTransferAccumulatorCapAfterWindowReset() public {
        vm.startPrank(admin);
        tokenRegistry.addToken(token1, TokenRegistry.BridgeTypeLocal.MintBurn, 1000e18);
        tokenRegistry.updateTokenTransferAccumulator(token1, 900e18);
        vm.stopPrank();

        // Fast forward past the window
        vm.warp(block.timestamp + tokenRegistry.TRANSFER_ACCUMULATOR_WINDOW() + 1);

        // Should not revert as window has reset
        tokenRegistry.revertIfOverTransferAccumulatorCap(token1, 500e18);

        // Should still revert if new amount exceeds cap
        vm.expectRevert();
        tokenRegistry.revertIfOverTransferAccumulatorCap(token1, 1500e18);
    }

    // Destination Chain Key Tests
    function test_AddTokenDestChainKey() public {
        vm.startPrank(admin);
        tokenRegistry.addToken(token1, TokenRegistry.BridgeTypeLocal.MintBurn, 1000e18);
        tokenRegistry.addTokenDestChainKey(token1, chainKey1, destTokenAddr1, 18);
        vm.stopPrank();

        assertTrue(tokenRegistry.isTokenDestChainKeyRegistered(token1, chainKey1));
        assertEq(tokenRegistry.getTokenDestChainTokenAddress(token1, chainKey1), destTokenAddr1);
        assertEq(tokenRegistry.getTokenDestChainKeyCount(token1), 1);
        assertEq(tokenRegistry.getTokenDestChainKeyAt(token1, 0), chainKey1);
    }

    function test_AddTokenDestChainKeyInvalidChain() public {
        bytes32 invalidChainKey = keccak256("invalid");

        vm.startPrank(admin);
        tokenRegistry.addToken(token1, TokenRegistry.BridgeTypeLocal.MintBurn, 1000e18);

        vm.expectRevert(abi.encodeWithSelector(ChainRegistry.ChainKeyNotRegistered.selector, invalidChainKey));
        tokenRegistry.addTokenDestChainKey(token1, invalidChainKey, destTokenAddr1, 18);
        vm.stopPrank();
    }

    function test_RemoveTokenDestChainKey() public {
        vm.startPrank(admin);
        tokenRegistry.addToken(token1, TokenRegistry.BridgeTypeLocal.MintBurn, 1000e18);
        tokenRegistry.addTokenDestChainKey(token1, chainKey1, destTokenAddr1, 18);
        tokenRegistry.addTokenDestChainKey(token1, chainKey2, destTokenAddr2, 18);

        assertEq(tokenRegistry.getTokenDestChainKeyCount(token1), 2);

        tokenRegistry.removeTokenDestChainKey(token1, chainKey1);
        vm.stopPrank();

        assertFalse(tokenRegistry.isTokenDestChainKeyRegistered(token1, chainKey1));
        assertEq(tokenRegistry.getTokenDestChainKeyCount(token1), 1);
        assertEq(tokenRegistry.getTokenDestChainTokenAddress(token1, chainKey1), bytes32(0));
    }

    function test_SetTokenDestChainTokenAddress() public {
        bytes32 newDestTokenAddr = bytes32(uint256(0x3001));

        vm.startPrank(admin);
        tokenRegistry.addToken(token1, TokenRegistry.BridgeTypeLocal.MintBurn, 1000e18);
        tokenRegistry.addTokenDestChainKey(token1, chainKey1, destTokenAddr1, 18);
        tokenRegistry.setTokenDestChainTokenAddress(token1, chainKey1, newDestTokenAddr);
        vm.stopPrank();

        assertEq(tokenRegistry.getTokenDestChainTokenAddress(token1, chainKey1), newDestTokenAddr);
    }

    function test_SetTokenDestChainTokenAddressNotRegistered() public {
        bytes32 newDestTokenAddr = bytes32(uint256(0x3001));

        vm.startPrank(admin);
        tokenRegistry.addToken(token1, TokenRegistry.BridgeTypeLocal.MintBurn, 1000e18);

        vm.expectRevert(
            abi.encodeWithSelector(TokenRegistry.TokenDestChainKeyNotRegistered.selector, token1, chainKey1)
        );
        tokenRegistry.setTokenDestChainTokenAddress(token1, chainKey1, newDestTokenAddr);
        vm.stopPrank();
    }

    function test_GetTokenDestChainKeys() public {
        vm.startPrank(admin);
        tokenRegistry.addToken(token1, TokenRegistry.BridgeTypeLocal.MintBurn, 1000e18);
        tokenRegistry.addTokenDestChainKey(token1, chainKey1, destTokenAddr1, 18);
        tokenRegistry.addTokenDestChainKey(token1, chainKey2, destTokenAddr2, 18);
        vm.stopPrank();

        bytes32[] memory chainKeys = tokenRegistry.getTokenDestChainKeys(token1);
        assertEq(chainKeys.length, 2);
        assertTrue(chainKeys[0] == chainKey1 || chainKeys[0] == chainKey2);
        assertTrue(chainKeys[1] == chainKey1 || chainKeys[1] == chainKey2);
        assertTrue(chainKeys[0] != chainKeys[1]);
    }

    function test_GetTokenDestChainKeysFrom() public {
        vm.startPrank(admin);
        tokenRegistry.addToken(token1, TokenRegistry.BridgeTypeLocal.MintBurn, 1000e18);
        tokenRegistry.addTokenDestChainKey(token1, chainKey1, destTokenAddr1, 18);
        tokenRegistry.addTokenDestChainKey(token1, chainKey2, destTokenAddr2, 18);
        tokenRegistry.addTokenDestChainKey(token1, chainKey3, destTokenAddr1, 18);
        vm.stopPrank();

        bytes32[] memory chainKeys = tokenRegistry.getTokenDestChainKeysFrom(token1, 1, 2);
        assertEq(chainKeys.length, 2);

        // Test out of bounds
        chainKeys = tokenRegistry.getTokenDestChainKeysFrom(token1, 5, 2);
        assertEq(chainKeys.length, 0);

        // Test partial range - this covers the missing line where count gets adjusted
        // With 3 items total, requesting from index 2 with count 5 should return only 1 item
        // This triggers: count = totalLength - index = 3 - 2 = 1
        chainKeys = tokenRegistry.getTokenDestChainKeysFrom(token1, 2, 5);
        assertEq(chainKeys.length, 1);
        assertEq(chainKeys[0], tokenRegistry.getTokenDestChainKeyAt(token1, 2));
    }

    function test_GetTokenDestChainKeysAndTokenAddresses() public {
        vm.startPrank(admin);
        tokenRegistry.addToken(token1, TokenRegistry.BridgeTypeLocal.MintBurn, 1000e18);
        tokenRegistry.addTokenDestChainKey(token1, chainKey1, destTokenAddr1, 18);
        tokenRegistry.addTokenDestChainKey(token1, chainKey2, destTokenAddr2, 18);
        vm.stopPrank();

        (bytes32[] memory chainKeys, bytes32[] memory tokenAddresses) =
            tokenRegistry.getTokenDestChainKeysAndTokenAddresses(token1);

        assertEq(chainKeys.length, 2);
        assertEq(tokenAddresses.length, 2);

        // Find indices for verification
        uint256 idx1 = chainKeys[0] == chainKey1 ? 0 : 1;
        uint256 idx2 = 1 - idx1;

        assertEq(chainKeys[idx1], chainKey1);
        assertEq(tokenAddresses[idx1], destTokenAddr1);
        assertEq(chainKeys[idx2], chainKey2);
        assertEq(tokenAddresses[idx2], destTokenAddr2);
    }

    // Validation Function Tests
    function test_RevertIfTokenNotRegistered() public {
        vm.expectRevert(abi.encodeWithSelector(TokenRegistry.TokenNotRegistered.selector, token1));
        tokenRegistry.revertIfTokenNotRegistered(token1);

        vm.prank(admin);
        tokenRegistry.addToken(token1, TokenRegistry.BridgeTypeLocal.MintBurn, 1000e18);

        // Should not revert after registration
        tokenRegistry.revertIfTokenNotRegistered(token1);
    }

    function test_RevertIfTokenDestChainKeyNotRegistered() public {
        vm.startPrank(admin);
        tokenRegistry.addToken(token1, TokenRegistry.BridgeTypeLocal.MintBurn, 1000e18);
        vm.stopPrank();

        vm.expectRevert(
            abi.encodeWithSelector(TokenRegistry.TokenDestChainKeyNotRegistered.selector, token1, chainKey1)
        );
        tokenRegistry.revertIfTokenDestChainKeyNotRegistered(token1, chainKey1);

        vm.prank(admin);
        tokenRegistry.addTokenDestChainKey(token1, chainKey1, destTokenAddr1, 18);

        // Should not revert after registration
        tokenRegistry.revertIfTokenDestChainKeyNotRegistered(token1, chainKey1);
    }

    // Security Tests with Malicious Contracts
    function test_MaliciousAdminCannotBypassAccessControl() public {
        MaliciousTokenRegistryAdmin maliciousAdmin = new MaliciousTokenRegistryAdmin();

        // Malicious contract should not be able to call restricted functions
        vm.expectRevert();
        maliciousAdmin.attemptMaliciousTokenAdd(tokenRegistry, token1);
    }

    function test_MaliciousTransferAccumulatorManipulation() public {
        vm.startPrank(admin);
        tokenRegistry.addToken(token1, TokenRegistry.BridgeTypeLocal.MintBurn, 1000e18);
        vm.stopPrank();

        MaliciousTransferAccumulatorContract maliciousContract = new MaliciousTransferAccumulatorContract(tokenRegistry);

        // Malicious contract should not be able to manipulate accumulator directly
        vm.expectRevert();
        maliciousContract.attemptAccumulatorManipulation(token1);
    }

    // Edge Cases and Stress Tests
    function test_ZeroTransferAccumulatorCap() public {
        vm.startPrank(admin);
        tokenRegistry.addToken(token1, TokenRegistry.BridgeTypeLocal.MintBurn, 0);

        vm.expectRevert();
        tokenRegistry.updateTokenTransferAccumulator(token1, 1);
        vm.stopPrank();
    }

    function test_MaxTransferAccumulatorCap() public {
        uint256 maxCap = type(uint256).max;

        vm.startPrank(admin);
        tokenRegistry.addToken(token1, TokenRegistry.BridgeTypeLocal.MintBurn, maxCap);
        tokenRegistry.updateTokenTransferAccumulator(token1, maxCap - 1);

        // Should not overflow
        tokenRegistry.updateTokenTransferAccumulator(token1, 1);
        vm.stopPrank();

        TokenRegistry.TransferAccumulator memory accumulator = tokenRegistry.getTokenTransferAccumulator(token1);
        assertEq(accumulator.amount, maxCap);
    }

    function test_MultipleAccumulatorUpdatesInSameWindow() public {
        vm.startPrank(admin);
        tokenRegistry.addToken(token1, TokenRegistry.BridgeTypeLocal.MintBurn, 1000e18);

        tokenRegistry.updateTokenTransferAccumulator(token1, 300e18);
        tokenRegistry.updateTokenTransferAccumulator(token1, 200e18);
        tokenRegistry.updateTokenTransferAccumulator(token1, 400e18);
        vm.stopPrank();

        TokenRegistry.TransferAccumulator memory accumulator = tokenRegistry.getTokenTransferAccumulator(token1);
        assertEq(accumulator.amount, 900e18);
    }

    function test_AccumulatorWindowBoundary() public {
        vm.startPrank(admin);
        tokenRegistry.addToken(token1, TokenRegistry.BridgeTypeLocal.MintBurn, 1000e18);

        // Warp to a time that allows windowStart to be set properly
        vm.warp(block.timestamp + tokenRegistry.TRANSFER_ACCUMULATOR_WINDOW() + 1);
        tokenRegistry.updateTokenTransferAccumulator(token1, 800e18);

        uint256 windowStart = block.timestamp;

        // Just before window expires - should revert due to cap exceeded (800 + 300 > 1000)
        vm.warp(windowStart + tokenRegistry.TRANSFER_ACCUMULATOR_WINDOW() - 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                TokenRegistry.OverTransferAccumulatorCap.selector,
                token1,
                300e18,
                1100e18, // 800e18 + 300e18
                1000e18
            )
        );
        tokenRegistry.updateTokenTransferAccumulator(token1, 300e18);

        // Just after window expires - should succeed as window resets
        vm.warp(windowStart + tokenRegistry.TRANSFER_ACCUMULATOR_WINDOW());
        tokenRegistry.updateTokenTransferAccumulator(token1, 300e18); // Should succeed
        vm.stopPrank();

        TokenRegistry.TransferAccumulator memory accumulator = tokenRegistry.getTokenTransferAccumulator(token1);
        assertEq(accumulator.amount, 300e18);
    }

    // Gas Optimization Tests
    function test_GasUsageForLargeTokenSet() public {
        vm.startPrank(admin);

        // Add 100 tokens
        for (uint256 i = 0; i < 100; i++) {
            address token = address(uint160(0x1000 + i));
            tokenRegistry.addToken(token, TokenRegistry.BridgeTypeLocal.MintBurn, 1000e18);
        }

        // Gas usage should be reasonable for querying all tokens
        uint256 gasBefore = gasleft();
        tokenRegistry.getAllTokens();
        uint256 gasUsed = gasBefore - gasleft();

        // Should use less than 2M gas for 100 tokens
        assertTrue(gasUsed < 2_000_000);
        vm.stopPrank();
    }

    function test_FuzzTransferAccumulator(uint256 cap, uint256 amount1, uint256 amount2) public {
        cap = bound(cap, 1, type(uint128).max); // Reasonable cap range
        amount1 = bound(amount1, 0, cap);
        amount2 = bound(amount2, 0, cap - amount1);

        vm.startPrank(admin);
        tokenRegistry.addToken(token1, TokenRegistry.BridgeTypeLocal.MintBurn, cap);
        tokenRegistry.updateTokenTransferAccumulator(token1, amount1);
        tokenRegistry.updateTokenTransferAccumulator(token1, amount2);
        vm.stopPrank();

        TokenRegistry.TransferAccumulator memory accumulator = tokenRegistry.getTokenTransferAccumulator(token1);
        assertEq(accumulator.amount, amount1 + amount2);
        assertLe(accumulator.amount, cap);
    }
}
