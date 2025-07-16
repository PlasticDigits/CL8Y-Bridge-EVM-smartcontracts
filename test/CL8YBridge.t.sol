// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {Cl8YBridge} from "../src/CL8YBridge.sol";
import {TokenRegistry} from "../src/TokenRegistry.sol";
import {TokenCl8yBridged} from "../src/TokenCl8yBridged.sol";
import {FactoryTokenCl8yBridged} from "../src/FactoryTokenCl8yBridged.sol";
import {MintBurn} from "../src/MintBurn.sol";
import {LockUnlock} from "../src/LockUnlock.sol";
import {AccessManager} from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import {IAccessManager} from "@openzeppelin/contracts/access/manager/IAccessManager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Mock contracts
import {MockTokenRegistry} from "./mocks/MockTokenRegistry.sol";
import {MockMintBurn} from "./mocks/MockMintBurn.sol";
import {MockLockUnlock} from "./mocks/MockLockUnlock.sol";
import {MockReentrantToken} from "./mocks/MockReentrantToken.sol";

// Malicious contracts
import {MaliciousBridgeContract} from "./malicious/MaliciousBridgeContract.sol";

contract CL8YBridgeTest is Test {
    Cl8YBridge public bridge;
    MockTokenRegistry public mockTokenRegistry;
    MockMintBurn public mockMintBurn;
    MockLockUnlock public mockLockUnlock;

    AccessManager public accessManager;
    FactoryTokenCl8yBridged public factory;
    TokenCl8yBridged public token;
    MockReentrantToken public reentrantToken;
    MaliciousBridgeContract public maliciousContract;

    address public owner = address(1);
    address public bridgeOperator = address(2);
    address public tokenCreator = address(3);
    address public user = address(4);
    address public recipient = address(5);
    address public unauthorizedUser = address(6);

    // Constants for testing
    bytes32 public constant DEST_CHAIN_KEY = keccak256("ETH");
    bytes32 public constant SRC_CHAIN_KEY = keccak256("BSC");
    bytes32 public constant DEST_ACCOUNT = bytes32(uint256(uint160(address(0x123))));
    bytes32 public constant DEST_TOKEN_ADDRESS = bytes32(uint256(uint160(address(0x456))));

    string constant TOKEN_NAME = "Test Token";
    string constant TOKEN_SYMBOL = "TEST";
    string constant LOGO_LINK = "https://example.com/logo.png";

    uint256 public constant DEPOSIT_AMOUNT = 1000e18;
    uint256 public constant WITHDRAW_AMOUNT = 500e18;
    uint256 public constant NONCE = 12345;

    uint64 constant BRIDGE_OPERATOR_ROLE = 1;
    uint64 constant TOKEN_CREATOR_ROLE = 2;

    // Events to test
    event DepositRequest(
        bytes32 indexed destChainKey, bytes32 indexed destAccount, address indexed token, uint256 amount, uint256 nonce
    );
    event WithdrawRequest(
        bytes32 indexed srcChainKey, address indexed token, address indexed to, uint256 amount, uint256 nonce
    );

    function setUp() public {
        // Deploy access manager with owner
        vm.prank(owner);
        accessManager = new AccessManager(owner);

        // Deploy mock contracts
        mockTokenRegistry = new MockTokenRegistry();
        mockMintBurn = new MockMintBurn(address(accessManager));
        mockLockUnlock = new MockLockUnlock(address(accessManager));

        // Deploy the CL8Y Bridge
        bridge = new Cl8YBridge(
            address(accessManager),
            TokenRegistry(address(mockTokenRegistry)),
            MintBurn(address(mockMintBurn)),
            LockUnlock(address(mockLockUnlock))
        );

        // Set up roles and permissions
        vm.startPrank(owner);

        // Grant roles to addresses
        accessManager.grantRole(BRIDGE_OPERATOR_ROLE, bridgeOperator, 0);
        accessManager.grantRole(TOKEN_CREATOR_ROLE, tokenCreator, 0);
        accessManager.grantRole(BRIDGE_OPERATOR_ROLE, address(this), 0);

        // Grant roles to mock contracts so they can be called by the bridge
        accessManager.grantRole(BRIDGE_OPERATOR_ROLE, address(mockMintBurn), 0);
        accessManager.grantRole(BRIDGE_OPERATOR_ROLE, address(mockLockUnlock), 0);
        accessManager.grantRole(BRIDGE_OPERATOR_ROLE, address(bridge), 0);

        // Deploy factory and set up factory permissions
        factory = new FactoryTokenCl8yBridged(address(accessManager));
        bytes4[] memory createTokenSelectors = new bytes4[](1);
        createTokenSelectors[0] = factory.createToken.selector;
        accessManager.setTargetFunctionRole(address(factory), createTokenSelectors, TOKEN_CREATOR_ROLE);

        // Set up bridge permissions - only withdraw requires restricted access
        bytes4[] memory withdrawSelectors = new bytes4[](1);
        withdrawSelectors[0] = bridge.withdraw.selector;
        accessManager.setTargetFunctionRole(address(bridge), withdrawSelectors, BRIDGE_OPERATOR_ROLE);

        // Set up mock contract permissions
        bytes4[] memory mintBurnSelectors = new bytes4[](2);
        mintBurnSelectors[0] = mockMintBurn.mint.selector;
        mintBurnSelectors[1] = mockMintBurn.burn.selector;
        accessManager.setTargetFunctionRole(address(mockMintBurn), mintBurnSelectors, BRIDGE_OPERATOR_ROLE);

        bytes4[] memory lockUnlockSelectors = new bytes4[](2);
        lockUnlockSelectors[0] = mockLockUnlock.lock.selector;
        lockUnlockSelectors[1] = mockLockUnlock.unlock.selector;
        accessManager.setTargetFunctionRole(address(mockLockUnlock), lockUnlockSelectors, BRIDGE_OPERATOR_ROLE);

        vm.stopPrank();

        vm.prank(tokenCreator);
        address tokenAddress = factory.createToken(TOKEN_NAME, TOKEN_SYMBOL, LOGO_LINK);
        token = TokenCl8yBridged(tokenAddress);

        // Set up token permissions so test contract and mock contracts can mint/burn
        vm.startPrank(owner);
        bytes4[] memory tokenMintSelectors = new bytes4[](1);
        tokenMintSelectors[0] = token.mint.selector;
        accessManager.setTargetFunctionRole(address(token), tokenMintSelectors, BRIDGE_OPERATOR_ROLE);
        vm.stopPrank();

        // Deploy reentrancy test token
        reentrantToken = new MockReentrantToken(address(mockLockUnlock));

        // Deploy malicious contract
        maliciousContract = new MaliciousBridgeContract(address(bridge), address(token));

        // Configure mock token registry for testing
        mockTokenRegistry.setTokenDestChainKeyRegistered(address(token), DEST_CHAIN_KEY, true);
        mockTokenRegistry.setTokenDestChainKeyRegistered(address(token), SRC_CHAIN_KEY, true);
        mockTokenRegistry.setTokenDestChainTokenAddress(address(token), DEST_CHAIN_KEY, DEST_TOKEN_ADDRESS);
        mockTokenRegistry.setTokenBridgeType(address(token), TokenRegistry.BridgeTypeLocal.MintBurn);
        mockTokenRegistry.setTransferAccumulatorCap(address(token), type(uint256).max);

        // Mint some tokens to user for testing
        token.mint(user, DEPOSIT_AMOUNT * 10);

        // Mint tokens to malicious contract for testing
        token.mint(address(maliciousContract), DEPOSIT_AMOUNT * 10);
    }

    // Test successful deposit with MintBurn bridge type
    function testDepositMintBurn() public {
        // Approve bridge to spend tokens
        vm.prank(user);
        token.approve(address(bridge), DEPOSIT_AMOUNT);

        // Expect the DepositRequest event
        vm.expectEmit(true, true, true, true);
        emit DepositRequest(DEST_CHAIN_KEY, DEST_ACCOUNT, address(token), DEPOSIT_AMOUNT, 0);

        // Perform deposit
        vm.prank(user);
        bridge.deposit(DEST_CHAIN_KEY, DEST_ACCOUNT, address(token), DEPOSIT_AMOUNT);

        // Verify nonce increment
        assertEq(bridge.depositNonce(), 1);

        // Verify mock mint/burn was called
        assertEq(mockMintBurn.burnCalls(user, address(token)), DEPOSIT_AMOUNT);
        assertEq(mockMintBurn.burnCallCount(), 1);
    }

    // Test successful deposit with LockUnlock bridge type
    function testDepositLockUnlock() public {
        // Configure token for LockUnlock bridge type
        mockTokenRegistry.setTokenBridgeType(address(token), TokenRegistry.BridgeTypeLocal.LockUnlock);

        // Approve bridge to spend tokens
        vm.prank(user);
        token.approve(address(bridge), DEPOSIT_AMOUNT);

        // Expect the DepositRequest event
        vm.expectEmit(true, true, true, true);
        emit DepositRequest(DEST_CHAIN_KEY, DEST_ACCOUNT, address(token), DEPOSIT_AMOUNT, 0);

        // Perform deposit
        vm.prank(user);
        bridge.deposit(DEST_CHAIN_KEY, DEST_ACCOUNT, address(token), DEPOSIT_AMOUNT);

        // Verify nonce increment
        assertEq(bridge.depositNonce(), 1);

        // Verify mock lock/unlock was called
        assertEq(mockLockUnlock.lockCalls(user, address(token)), DEPOSIT_AMOUNT);
        assertEq(mockLockUnlock.lockCallCount(), 1);
    }

    // Test deposit fails when token is not registered for destination chain
    function testDepositFailsWhenTokenNotRegistered() public {
        // Set token as not registered for destination chain
        mockTokenRegistry.setTokenDestChainKeyRegistered(address(token), DEST_CHAIN_KEY, false);

        vm.prank(user);
        token.approve(address(bridge), DEPOSIT_AMOUNT);

        vm.expectRevert("Token dest chain key not registered");
        vm.prank(user);
        bridge.deposit(DEST_CHAIN_KEY, DEST_ACCOUNT, address(token), DEPOSIT_AMOUNT);
    }

    // Test deposit fails when over transfer accumulator cap
    function testDepositFailsWhenOverCap() public {
        // Set low cap to trigger failure
        mockTokenRegistry.setTransferAccumulatorCap(address(token), DEPOSIT_AMOUNT - 1);

        vm.prank(user);
        token.approve(address(bridge), DEPOSIT_AMOUNT);

        vm.expectRevert("Over transfer accumulator cap");
        vm.prank(user);
        bridge.deposit(DEST_CHAIN_KEY, DEST_ACCOUNT, address(token), DEPOSIT_AMOUNT);
    }

    // Test successful withdraw with MintBurn bridge type
    function testWithdrawMintBurn() public {
        // Expect the WithdrawRequest event
        vm.expectEmit(true, true, true, true);
        emit WithdrawRequest(SRC_CHAIN_KEY, address(token), recipient, WITHDRAW_AMOUNT, NONCE);

        // Perform withdraw
        vm.prank(bridgeOperator);
        bridge.withdraw(SRC_CHAIN_KEY, address(token), recipient, WITHDRAW_AMOUNT, NONCE);

        // Verify mock mint/burn was called
        assertEq(mockMintBurn.mintCalls(recipient, address(token)), WITHDRAW_AMOUNT);
        assertEq(mockMintBurn.mintCallCount(), 1);
    }

    // Test successful withdraw with LockUnlock bridge type
    function testWithdrawLockUnlock() public {
        // Configure token for LockUnlock bridge type
        mockTokenRegistry.setTokenBridgeType(address(token), TokenRegistry.BridgeTypeLocal.LockUnlock);

        // Expect the WithdrawRequest event
        vm.expectEmit(true, true, true, true);
        emit WithdrawRequest(SRC_CHAIN_KEY, address(token), recipient, WITHDRAW_AMOUNT, NONCE);

        // Perform withdraw
        vm.prank(bridgeOperator);
        bridge.withdraw(SRC_CHAIN_KEY, address(token), recipient, WITHDRAW_AMOUNT, NONCE);

        // Verify mock lock/unlock was called
        assertEq(mockLockUnlock.unlockCalls(recipient, address(token)), WITHDRAW_AMOUNT);
        assertEq(mockLockUnlock.unlockCallCount(), 1);
    }

    // Test withdraw fails when called by unauthorized user
    function testWithdrawFailsWhenUnauthorized() public {
        vm.expectRevert();
        vm.prank(unauthorizedUser);
        bridge.withdraw(SRC_CHAIN_KEY, address(token), recipient, WITHDRAW_AMOUNT, NONCE);
    }

    // Test withdraw fails when token is not registered for source chain
    function testWithdrawFailsWhenTokenNotRegistered() public {
        // Set token as not registered for source chain
        mockTokenRegistry.setTokenDestChainKeyRegistered(address(token), SRC_CHAIN_KEY, false);

        vm.expectRevert("Token dest chain key not registered");
        vm.prank(bridgeOperator);
        bridge.withdraw(SRC_CHAIN_KEY, address(token), recipient, WITHDRAW_AMOUNT, NONCE);
    }

    // Test withdraw fails when over transfer accumulator cap
    function testWithdrawFailsWhenOverCap() public {
        // Set low cap to trigger failure
        mockTokenRegistry.setTransferAccumulatorCap(address(token), WITHDRAW_AMOUNT - 1);

        vm.expectRevert("Over transfer accumulator cap");
        vm.prank(bridgeOperator);
        bridge.withdraw(SRC_CHAIN_KEY, address(token), recipient, WITHDRAW_AMOUNT, NONCE);
    }

    // Test duplicate withdrawal prevention
    function testPreventDuplicateWithdraw() public {
        // First withdrawal should succeed
        vm.prank(bridgeOperator);
        bridge.withdraw(SRC_CHAIN_KEY, address(token), recipient, WITHDRAW_AMOUNT, NONCE);

        // Second withdrawal with same parameters should fail
        vm.expectRevert();
        vm.prank(bridgeOperator);
        bridge.withdraw(SRC_CHAIN_KEY, address(token), recipient, WITHDRAW_AMOUNT, NONCE);
    }

    // Test that deposits with same parameters but different nonces are allowed
    function testMultipleDepositsWithDifferentNonces() public {
        vm.startPrank(user);
        token.approve(address(bridge), DEPOSIT_AMOUNT * 2);

        // First deposit
        bridge.deposit(DEST_CHAIN_KEY, DEST_ACCOUNT, address(token), DEPOSIT_AMOUNT);
        assertEq(bridge.depositNonce(), 1);

        // Second deposit with same parameters should succeed (different nonce)
        bridge.deposit(DEST_CHAIN_KEY, DEST_ACCOUNT, address(token), DEPOSIT_AMOUNT);
        assertEq(bridge.depositNonce(), 2);

        vm.stopPrank();

        // Verify both calls were made
        assertEq(mockMintBurn.burnCallCount(), 2);
    }

    // Test hash generation functions
    function testHashGeneration() public {
        Cl8YBridge.Withdraw memory withdrawRequest = Cl8YBridge.Withdraw({
            srcChainKey: SRC_CHAIN_KEY,
            token: address(token),
            to: recipient,
            amount: WITHDRAW_AMOUNT,
            nonce: NONCE
        });

        Cl8YBridge.Deposit memory depositRequest = Cl8YBridge.Deposit({
            destChainKey: DEST_CHAIN_KEY,
            destTokenAddress: DEST_TOKEN_ADDRESS,
            from: user,
            amount: DEPOSIT_AMOUNT,
            nonce: 0
        });

        bytes32 withdrawHash = bridge.getWithdrawHash(withdrawRequest);
        bytes32 depositHash = bridge.getDepositHash(depositRequest);

        // Hashes should be deterministic
        assertEq(withdrawHash, bridge.getWithdrawHash(withdrawRequest));
        assertEq(depositHash, bridge.getDepositHash(depositRequest));

        // Different requests should have different hashes
        withdrawRequest.nonce = NONCE + 1;
        assertNotEq(withdrawHash, bridge.getWithdrawHash(withdrawRequest));
    }

    // Test access control for deposit function (should be public)
    function testDepositAccessControl() public {
        vm.prank(user);
        token.approve(address(bridge), DEPOSIT_AMOUNT);

        // Any user should be able to call deposit
        vm.prank(unauthorizedUser);
        bridge.deposit(DEST_CHAIN_KEY, DEST_ACCOUNT, address(token), DEPOSIT_AMOUNT);

        assertEq(bridge.depositNonce(), 1);
    }

    // Test that malicious contract cannot exploit the bridge
    function testMaliciousContractCannotExploit() public {
        // Configure token registry for malicious contract's token
        mockTokenRegistry.setTokenDestChainKeyRegistered(address(token), DEST_CHAIN_KEY, true);
        mockTokenRegistry.setTokenBridgeType(address(token), TokenRegistry.BridgeTypeLocal.MintBurn);

        // Try to perform multiple deposits (should not cause issues due to nonce)
        maliciousContract.attemptDuplicateDeposits();

        // Verify that both deposits went through with different nonces
        assertEq(bridge.depositNonce(), 2);
        assertEq(mockMintBurn.burnCallCount(), 2);
    }

    // Test error conditions in mock contracts
    function testMockContractErrors() public {
        // Set mock mint/burn to revert
        mockMintBurn.setShouldRevertOnBurn(true);

        vm.prank(user);
        token.approve(address(bridge), DEPOSIT_AMOUNT);

        vm.expectRevert("Mock burn failed");
        vm.prank(user);
        bridge.deposit(DEST_CHAIN_KEY, DEST_ACCOUNT, address(token), DEPOSIT_AMOUNT);

        // Reset and test mint failure on withdraw
        mockMintBurn.setShouldRevertOnBurn(false);
        mockMintBurn.setShouldRevertOnMint(true);

        vm.expectRevert("Mock mint failed");
        vm.prank(bridgeOperator);
        bridge.withdraw(SRC_CHAIN_KEY, address(token), recipient, WITHDRAW_AMOUNT, NONCE);
    }

    // Test lock/unlock failures
    function testLockUnlockErrors() public {
        // Configure for lock/unlock
        mockTokenRegistry.setTokenBridgeType(address(token), TokenRegistry.BridgeTypeLocal.LockUnlock);

        // Test lock failure
        mockLockUnlock.setShouldRevertOnLock(true);

        vm.prank(user);
        token.approve(address(bridge), DEPOSIT_AMOUNT);

        vm.expectRevert("Mock lock failed");
        vm.prank(user);
        bridge.deposit(DEST_CHAIN_KEY, DEST_ACCOUNT, address(token), DEPOSIT_AMOUNT);

        // Test unlock failure
        mockLockUnlock.setShouldRevertOnLock(false);
        mockLockUnlock.setShouldRevertOnUnlock(true);

        vm.expectRevert("Mock unlock failed");
        vm.prank(bridgeOperator);
        bridge.withdraw(SRC_CHAIN_KEY, address(token), recipient, WITHDRAW_AMOUNT, NONCE);
    }

    // Test edge case: zero amount deposit/withdraw
    function testZeroAmountOperations() public {
        vm.prank(user);
        token.approve(address(bridge), 0);

        // Zero amount deposit should still work
        vm.prank(user);
        bridge.deposit(DEST_CHAIN_KEY, DEST_ACCOUNT, address(token), 0);

        // Zero amount withdraw should still work
        vm.prank(bridgeOperator);
        bridge.withdraw(SRC_CHAIN_KEY, address(token), recipient, 0, NONCE);

        assertEq(bridge.depositNonce(), 1);
    }

    // Test large amount operations
    function testLargeAmountOperations() public {
        uint256 largeAmount = type(uint256).max / 2;

        // Mint large amount to user (test contract has BRIDGE_OPERATOR_ROLE)
        token.mint(user, largeAmount);

        vm.prank(user);
        token.approve(address(bridge), largeAmount);

        // Large amount operations should work
        vm.prank(user);
        bridge.deposit(DEST_CHAIN_KEY, DEST_ACCOUNT, address(token), largeAmount);

        vm.prank(bridgeOperator);
        bridge.withdraw(SRC_CHAIN_KEY, address(token), recipient, largeAmount, NONCE);

        assertEq(mockMintBurn.burnCalls(user, address(token)), largeAmount);
        assertEq(mockMintBurn.mintCalls(recipient, address(token)), largeAmount);
    }

    // Test multiple withdrawals with different nonces
    function testMultipleWithdrawalsWithDifferentNonces() public {
        // First withdrawal
        vm.prank(bridgeOperator);
        bridge.withdraw(SRC_CHAIN_KEY, address(token), recipient, WITHDRAW_AMOUNT, NONCE);

        // Second withdrawal with different nonce should succeed
        vm.prank(bridgeOperator);
        bridge.withdraw(SRC_CHAIN_KEY, address(token), recipient, WITHDRAW_AMOUNT, NONCE + 1);

        assertEq(mockMintBurn.mintCallCount(), 2);
    }

    // Test that transfer accumulator is updated correctly
    function testTransferAccumulatorUpdate() public {
        uint256 initialAccumulator = mockTokenRegistry.transferAccumulator(address(token));

        vm.prank(user);
        token.approve(address(bridge), DEPOSIT_AMOUNT);

        vm.prank(user);
        bridge.deposit(DEST_CHAIN_KEY, DEST_ACCOUNT, address(token), DEPOSIT_AMOUNT);

        // Verify accumulator was updated
        assertEq(mockTokenRegistry.transferAccumulator(address(token)), initialAccumulator + DEPOSIT_AMOUNT);

        // Test withdraw also updates accumulator
        vm.prank(bridgeOperator);
        bridge.withdraw(SRC_CHAIN_KEY, address(token), recipient, WITHDRAW_AMOUNT, NONCE);

        assertEq(
            mockTokenRegistry.transferAccumulator(address(token)), initialAccumulator + DEPOSIT_AMOUNT + WITHDRAW_AMOUNT
        );
    }
}
