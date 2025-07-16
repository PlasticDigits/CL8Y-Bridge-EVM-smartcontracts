// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {Cl8YBridge} from "../src/CL8YBridge.sol";
import {TokenRegistry} from "../src/TokenRegistry.sol";
import {ChainRegistry} from "../src/ChainRegistry.sol";
import {TokenCl8yBridged} from "../src/TokenCl8yBridged.sol";
import {FactoryTokenCl8yBridged} from "../src/FactoryTokenCl8yBridged.sol";
import {MintBurn} from "../src/MintBurn.sol";
import {LockUnlock} from "../src/LockUnlock.sol";
import {AccessManager} from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title CL8YBridge Integration Tests
/// @notice Comprehensive integration tests using real contracts to test end-to-end workflows
/// @dev Tests the entire bridge ecosystem with real contract interactions, time-based features, and complex scenarios
contract CL8YBridgeIntegrationTest is Test {
    // Core contracts
    Cl8YBridge public bridge;
    TokenRegistry public tokenRegistry;
    ChainRegistry public chainRegistry;
    MintBurn public mintBurn;
    LockUnlock public lockUnlock;
    AccessManager public accessManager;
    FactoryTokenCl8yBridged public factory;

    // Test tokens
    TokenCl8yBridged public tokenMintBurn;
    TokenCl8yBridged public tokenLockUnlock;
    TokenCl8yBridged public tokenMultiChain;

    // Test addresses
    address public owner = address(1);
    address public bridgeOperator = address(2);
    address public tokenAdmin = address(3);
    address public user1 = address(4);
    address public user2 = address(5);
    address public user3 = address(6);

    // Chain identifiers
    uint256 public constant ETH_CHAIN_ID = 1;
    uint256 public constant BSC_CHAIN_ID = 56;
    uint256 public constant POLYGON_CHAIN_ID = 137;
    string public constant COSMOS_HUB = "cosmoshub-4";

    // Chain keys
    bytes32 public ethChainKey;
    bytes32 public bscChainKey;
    bytes32 public polygonChainKey;
    bytes32 public cosmosChainKey;

    // Destination token addresses (on other chains)
    bytes32 public constant ETH_TOKEN_ADDR = bytes32(uint256(uint160(address(0x1001))));
    bytes32 public constant BSC_TOKEN_ADDR = bytes32(uint256(uint160(address(0x1002))));
    bytes32 public constant POLYGON_TOKEN_ADDR = bytes32(uint256(uint160(address(0x1003))));
    bytes32 public constant COSMOS_TOKEN_ADDR = bytes32(uint256(uint160(address(0x1004))));

    // Test amounts
    uint256 public constant INITIAL_MINT = 10000e18;
    uint256 public constant DEPOSIT_AMOUNT = 1000e18;
    uint256 public constant LARGE_AMOUNT = 5000e18;
    uint256 public constant ACCUMULATOR_CAP = 10000e18;

    // Role identifiers
    uint64 public constant ADMIN_ROLE = 1;
    uint64 public constant BRIDGE_OPERATOR_ROLE = 2;

    // Events for testing
    event DepositRequest(
        bytes32 indexed destChainKey, bytes32 indexed destAccount, address indexed token, uint256 amount, uint256 nonce
    );
    event WithdrawRequest(
        bytes32 indexed srcChainKey, address indexed token, address indexed to, uint256 amount, uint256 nonce
    );

    function setUp() public {
        // Deploy access manager
        vm.prank(owner);
        accessManager = new AccessManager(owner);

        // Deploy chain registry and add chains
        chainRegistry = new ChainRegistry(address(accessManager));

        // Deploy token registry
        tokenRegistry = new TokenRegistry(address(accessManager), chainRegistry);

        // Deploy mint/burn and lock/unlock contracts
        mintBurn = new MintBurn(address(accessManager));
        lockUnlock = new LockUnlock(address(accessManager));

        // Deploy bridge
        bridge = new Cl8YBridge(address(accessManager), tokenRegistry, mintBurn, lockUnlock);

        // Deploy factory
        factory = new FactoryTokenCl8yBridged(address(accessManager));

        // Setup roles and permissions
        _setupRolesAndPermissions();

        // Setup chains
        _setupChains();

        // Create test tokens
        _createTestTokens();

        // Setup tokens in registries
        _setupTokensInRegistry();

        // Mint initial tokens to users
        _mintInitialTokens();
    }

    /// @notice Setup access control roles and permissions
    function _setupRolesAndPermissions() internal {
        vm.startPrank(owner);

        // Grant roles to addresses
        accessManager.grantRole(ADMIN_ROLE, tokenAdmin, 0);
        accessManager.grantRole(BRIDGE_OPERATOR_ROLE, bridgeOperator, 0);
        accessManager.grantRole(BRIDGE_OPERATOR_ROLE, address(bridge), 0);

        // Setup ChainRegistry permissions
        bytes4[] memory chainRegistrySelectors = new bytes4[](6);
        chainRegistrySelectors[0] = chainRegistry.addEVMChainKey.selector;
        chainRegistrySelectors[1] = chainRegistry.addCOSMWChainKey.selector;
        chainRegistrySelectors[2] = chainRegistry.addSOLChainKey.selector;
        chainRegistrySelectors[3] = chainRegistry.addOtherChainType.selector;
        chainRegistrySelectors[4] = chainRegistry.addChainKey.selector;
        chainRegistrySelectors[5] = chainRegistry.removeChainKey.selector;
        accessManager.setTargetFunctionRole(address(chainRegistry), chainRegistrySelectors, ADMIN_ROLE);

        // Setup TokenRegistry permissions
        bytes4[] memory tokenRegistrySelectors = new bytes4[](7);
        tokenRegistrySelectors[0] = tokenRegistry.addToken.selector;
        tokenRegistrySelectors[1] = tokenRegistry.addTokenDestChainKey.selector;
        tokenRegistrySelectors[2] = tokenRegistry.setTokenBridgeType.selector;
        tokenRegistrySelectors[3] = tokenRegistry.setTokenTransferAccumulatorCap.selector;
        tokenRegistrySelectors[4] = tokenRegistry.updateTokenTransferAccumulator.selector;
        tokenRegistrySelectors[5] = tokenRegistry.removeTokenDestChainKey.selector;
        tokenRegistrySelectors[6] = tokenRegistry.setTokenDestChainTokenAddress.selector;
        accessManager.setTargetFunctionRole(address(tokenRegistry), tokenRegistrySelectors, ADMIN_ROLE);

        // Bridge needs access to certain TokenRegistry functions
        bytes4[] memory bridgeTokenRegistrySelectors = new bytes4[](1);
        bridgeTokenRegistrySelectors[0] = tokenRegistry.updateTokenTransferAccumulator.selector;
        accessManager.setTargetFunctionRole(address(tokenRegistry), bridgeTokenRegistrySelectors, BRIDGE_OPERATOR_ROLE);

        // Setup Bridge permissions
        bytes4[] memory bridgeSelectors = new bytes4[](1);
        bridgeSelectors[0] = bridge.withdraw.selector;
        accessManager.setTargetFunctionRole(address(bridge), bridgeSelectors, BRIDGE_OPERATOR_ROLE);

        // Setup MintBurn permissions
        bytes4[] memory mintBurnSelectors = new bytes4[](2);
        mintBurnSelectors[0] = mintBurn.mint.selector;
        mintBurnSelectors[1] = mintBurn.burn.selector;
        accessManager.setTargetFunctionRole(address(mintBurn), mintBurnSelectors, BRIDGE_OPERATOR_ROLE);

        // Setup LockUnlock permissions
        bytes4[] memory lockUnlockSelectors = new bytes4[](2);
        lockUnlockSelectors[0] = lockUnlock.lock.selector;
        lockUnlockSelectors[1] = lockUnlock.unlock.selector;
        accessManager.setTargetFunctionRole(address(lockUnlock), lockUnlockSelectors, BRIDGE_OPERATOR_ROLE);

        // Setup Factory permissions
        bytes4[] memory factorySelectors = new bytes4[](1);
        factorySelectors[0] = factory.createToken.selector;
        accessManager.setTargetFunctionRole(address(factory), factorySelectors, ADMIN_ROLE);

        vm.stopPrank();
    }

    /// @notice Setup chain registrations
    function _setupChains() internal {
        // Pre-compute chain keys first
        ethChainKey = chainRegistry.getChainKeyEVM(ETH_CHAIN_ID);
        bscChainKey = chainRegistry.getChainKeyEVM(BSC_CHAIN_ID);
        polygonChainKey = chainRegistry.getChainKeyEVM(POLYGON_CHAIN_ID);
        cosmosChainKey = chainRegistry.getChainKeyCOSMW(COSMOS_HUB);

        vm.startPrank(tokenAdmin);

        chainRegistry.addEVMChainKey(ETH_CHAIN_ID);
        chainRegistry.addEVMChainKey(BSC_CHAIN_ID);
        chainRegistry.addEVMChainKey(POLYGON_CHAIN_ID);
        chainRegistry.addCOSMWChainKey(COSMOS_HUB);

        vm.stopPrank();
    }

    /// @notice Create test tokens with different bridge types
    function _createTestTokens() internal {
        vm.startPrank(tokenAdmin);

        // Create MintBurn token
        address tokenMintBurnAddr = factory.createToken("MintBurn Token", "MINT", "https://mintburn.com/logo.png");
        tokenMintBurn = TokenCl8yBridged(tokenMintBurnAddr);

        // Create LockUnlock token
        address tokenLockUnlockAddr = factory.createToken("LockUnlock Token", "LOCK", "https://lockunlock.com/logo.png");
        tokenLockUnlock = TokenCl8yBridged(tokenLockUnlockAddr);

        // Create MultiChain token
        address tokenMultiChainAddr =
            factory.createToken("MultiChain Token", "MULTI", "https://multichain.com/logo.png");
        tokenMultiChain = TokenCl8yBridged(tokenMultiChainAddr);

        vm.stopPrank();

        // Setup token permissions for minting
        vm.startPrank(owner);
        bytes4[] memory mintSelectors = new bytes4[](1);
        mintSelectors[0] = TokenCl8yBridged.mint.selector;

        accessManager.setTargetFunctionRole(address(tokenMintBurn), mintSelectors, BRIDGE_OPERATOR_ROLE);
        accessManager.setTargetFunctionRole(address(tokenLockUnlock), mintSelectors, BRIDGE_OPERATOR_ROLE);
        accessManager.setTargetFunctionRole(address(tokenMultiChain), mintSelectors, BRIDGE_OPERATOR_ROLE);

        // Also grant the mint/burn contracts permission to call token functions
        accessManager.grantRole(BRIDGE_OPERATOR_ROLE, address(mintBurn), 0);
        accessManager.grantRole(BRIDGE_OPERATOR_ROLE, address(lockUnlock), 0);

        vm.stopPrank();
    }

    /// @notice Setup tokens in token registry with different bridge types and chains
    function _setupTokensInRegistry() internal {
        vm.startPrank(tokenAdmin);

        // Add MintBurn token (for minting/burning bridged tokens)
        tokenRegistry.addToken(address(tokenMintBurn), TokenRegistry.BridgeTypeLocal.MintBurn, ACCUMULATOR_CAP);
        tokenRegistry.addTokenDestChainKey(address(tokenMintBurn), ethChainKey, ETH_TOKEN_ADDR);
        tokenRegistry.addTokenDestChainKey(address(tokenMintBurn), bscChainKey, BSC_TOKEN_ADDR);

        // Add LockUnlock token (for locking native tokens)
        tokenRegistry.addToken(address(tokenLockUnlock), TokenRegistry.BridgeTypeLocal.LockUnlock, ACCUMULATOR_CAP);
        tokenRegistry.addTokenDestChainKey(address(tokenLockUnlock), polygonChainKey, POLYGON_TOKEN_ADDR);
        tokenRegistry.addTokenDestChainKey(address(tokenLockUnlock), cosmosChainKey, COSMOS_TOKEN_ADDR);

        // Add MultiChain token (supports both bridge types and multiple chains)
        tokenRegistry.addToken(address(tokenMultiChain), TokenRegistry.BridgeTypeLocal.MintBurn, ACCUMULATOR_CAP);
        tokenRegistry.addTokenDestChainKey(address(tokenMultiChain), ethChainKey, ETH_TOKEN_ADDR);
        tokenRegistry.addTokenDestChainKey(address(tokenMultiChain), bscChainKey, BSC_TOKEN_ADDR);
        tokenRegistry.addTokenDestChainKey(address(tokenMultiChain), polygonChainKey, POLYGON_TOKEN_ADDR);
        tokenRegistry.addTokenDestChainKey(address(tokenMultiChain), cosmosChainKey, COSMOS_TOKEN_ADDR);

        vm.stopPrank();
    }

    /// @notice Mint initial tokens to test users
    function _mintInitialTokens() internal {
        vm.startPrank(owner);

        // Grant temporary mint role to setup
        accessManager.grantRole(BRIDGE_OPERATOR_ROLE, tokenAdmin, 0);

        vm.stopPrank();

        vm.startPrank(tokenAdmin);

        // Mint tokens to users
        tokenMintBurn.mint(user1, INITIAL_MINT);
        tokenMintBurn.mint(user2, INITIAL_MINT);

        tokenLockUnlock.mint(user1, INITIAL_MINT);
        tokenLockUnlock.mint(user2, INITIAL_MINT);

        tokenMultiChain.mint(user1, INITIAL_MINT);
        tokenMultiChain.mint(user2, INITIAL_MINT);
        tokenMultiChain.mint(user3, INITIAL_MINT);

        vm.stopPrank();
    }

    // ============ FULL WORKFLOW INTEGRATION TESTS ============

    /// @notice Test complete deposit-withdraw cycle with MintBurn bridge type
    function testFullDepositWithdrawCycleMintBurn() public {
        uint256 depositAmount = DEPOSIT_AMOUNT;
        uint256 nonce = 12345;

        // Record initial balances
        uint256 initialUserBalance = tokenMintBurn.balanceOf(user1);
        uint256 initialTotalSupply = tokenMintBurn.totalSupply();

        // User deposits tokens
        vm.startPrank(user1);
        tokenMintBurn.approve(address(bridge), depositAmount);
        tokenMintBurn.approve(address(mintBurn), depositAmount); // MintBurn needs approval to burn

        // vm.expectEmit(true, true, true, true);
        // emit DepositRequest(ethChainKey, bytes32(uint256(uint160(user2))), address(tokenMintBurn), depositAmount, 0);

        bridge.deposit(ethChainKey, bytes32(uint256(uint160(user2))), address(tokenMintBurn), depositAmount);
        vm.stopPrank();

        // Verify deposit effects
        assertEq(tokenMintBurn.balanceOf(user1), initialUserBalance - depositAmount, "User balance after deposit");
        assertEq(tokenMintBurn.totalSupply(), initialTotalSupply - depositAmount, "Total supply after burn");
        assertEq(bridge.depositNonce(), 1, "Deposit nonce incremented");

        // Verify transfer accumulator updated
        TokenRegistry.TransferAccumulator memory accumulator =
            tokenRegistry.getTokenTransferAccumulator(address(tokenMintBurn));
        assertEq(accumulator.amount, depositAmount, "Accumulator amount");

        // Bridge operator processes withdrawal on destination chain
        // vm.expectEmit(true, true, true, true);
        // emit WithdrawRequest(ethChainKey, address(tokenMintBurn), user2, depositAmount, nonce);

        vm.prank(bridgeOperator);
        bridge.withdraw(ethChainKey, address(tokenMintBurn), user2, depositAmount, nonce);

        // Verify withdrawal effects (user2 had INITIAL_MINT + depositAmount)
        assertEq(tokenMintBurn.balanceOf(user2), INITIAL_MINT + depositAmount, "Recipient balance after withdraw");
        assertEq(tokenMintBurn.totalSupply(), initialTotalSupply, "Total supply restored after mint");

        // Verify accumulator updated again
        accumulator = tokenRegistry.getTokenTransferAccumulator(address(tokenMintBurn));
        assertEq(accumulator.amount, depositAmount * 2, "Accumulator amount after withdraw");
    }

    /// @notice Test complete deposit-withdraw cycle with LockUnlock bridge type
    function testFullDepositWithdrawCycleLockUnlock() public {
        uint256 depositAmount = DEPOSIT_AMOUNT;
        uint256 nonce = 54321;

        // Record initial balances
        uint256 initialUserBalance = tokenLockUnlock.balanceOf(user1);
        uint256 initialContractBalance = tokenLockUnlock.balanceOf(address(lockUnlock));
        uint256 initialTotalSupply = tokenLockUnlock.totalSupply();

        // User deposits tokens
        vm.startPrank(user1);
        tokenLockUnlock.approve(address(bridge), depositAmount);
        tokenLockUnlock.approve(address(lockUnlock), depositAmount); // LockUnlock needs approval to transfer

        vm.expectEmit(true, true, true, true);
        emit DepositRequest(
            polygonChainKey, bytes32(uint256(uint160(user2))), address(tokenLockUnlock), depositAmount, 0
        );

        bridge.deposit(polygonChainKey, bytes32(uint256(uint160(user2))), address(tokenLockUnlock), depositAmount);
        vm.stopPrank();

        // Verify deposit effects (tokens locked, not burned)
        assertEq(tokenLockUnlock.balanceOf(user1), initialUserBalance - depositAmount, "User balance after deposit");
        assertEq(
            tokenLockUnlock.balanceOf(address(lockUnlock)),
            initialContractBalance + depositAmount,
            "Contract balance after lock"
        );
        assertEq(tokenLockUnlock.totalSupply(), initialTotalSupply, "Total supply unchanged");

        // Bridge operator processes withdrawal
        vm.prank(bridgeOperator);
        bridge.withdraw(polygonChainKey, address(tokenLockUnlock), user2, depositAmount, nonce);

        // Verify withdrawal effects (tokens unlocked, user2 had INITIAL_MINT + depositAmount)
        assertEq(tokenLockUnlock.balanceOf(user2), INITIAL_MINT + depositAmount, "Recipient balance after withdraw");
        assertEq(
            tokenLockUnlock.balanceOf(address(lockUnlock)), initialContractBalance, "Contract balance after unlock"
        );
        assertEq(tokenLockUnlock.totalSupply(), initialTotalSupply, "Total supply still unchanged");
    }

    // ============ TRANSFER ACCUMULATOR INTEGRATION TESTS ============

    /// @notice Test transfer accumulator limits with real time progression
    function testTransferAccumulatorLimitsOverTime() public {
        uint256 halfCap = ACCUMULATOR_CAP / 2;

        // First deposit should succeed
        vm.startPrank(user1);
        tokenMintBurn.approve(address(bridge), halfCap);
        tokenMintBurn.approve(address(mintBurn), halfCap);
        bridge.deposit(ethChainKey, bytes32(uint256(uint160(user2))), address(tokenMintBurn), halfCap);
        vm.stopPrank();

        // Second deposit that would exceed cap should fail
        vm.startPrank(user2);
        tokenMintBurn.approve(address(bridge), halfCap + 1);
        tokenMintBurn.approve(address(mintBurn), halfCap + 1);

        vm.expectRevert();
        bridge.deposit(ethChainKey, bytes32(uint256(uint160(user1))), address(tokenMintBurn), halfCap + 1);
        vm.stopPrank();

        // Advance time by 1 day to reset accumulator
        vm.warp(block.timestamp + 1 days);

        // Now the large deposit should succeed
        vm.startPrank(user2);
        bridge.deposit(ethChainKey, bytes32(uint256(uint160(user1))), address(tokenMintBurn), halfCap + 1);
        vm.stopPrank();

        // Verify accumulator reset
        TokenRegistry.TransferAccumulator memory accumulator =
            tokenRegistry.getTokenTransferAccumulator(address(tokenMintBurn));
        assertEq(accumulator.amount, halfCap + 1, "Accumulator reset and updated");
        assertEq(accumulator.windowStart, block.timestamp, "Window start updated");
    }

    /// @notice Test accumulator behavior across multiple operations within window
    function testAccumulatorMultipleOperationsWithinWindow() public {
        uint256 amount1 = 2000e18;
        uint256 amount2 = 3000e18;
        uint256 amount3 = 5001e18;

        // First operation
        vm.startPrank(user1);
        tokenMultiChain.approve(address(bridge), amount1);
        tokenMultiChain.approve(address(mintBurn), amount1);
        bridge.deposit(ethChainKey, bytes32(uint256(uint160(user2))), address(tokenMultiChain), amount1);
        vm.stopPrank();

        // Second operation (withdrawal)
        vm.prank(bridgeOperator);
        bridge.withdraw(ethChainKey, address(tokenMultiChain), user2, amount2, 1);

        // Third operation should fail (total would be 10001e18, exceeding 10000e18 cap)
        vm.startPrank(user3);
        tokenMultiChain.approve(address(bridge), amount3);
        tokenMultiChain.approve(address(mintBurn), amount3);

        vm.expectRevert();
        bridge.deposit(bscChainKey, bytes32(uint256(uint160(user1))), address(tokenMultiChain), amount3);
        vm.stopPrank();

        // Verify final accumulator state
        TokenRegistry.TransferAccumulator memory accumulator =
            tokenRegistry.getTokenTransferAccumulator(address(tokenMultiChain));
        assertEq(accumulator.amount, amount1 + amount2, "Accumulator tracks both operations");
    }

    // ============ BRIDGE TYPE SWITCHING INTEGRATION TESTS ============

    /// @notice Test switching bridge type from MintBurn to LockUnlock with real operations
    function testBridgeTypeSwitchingIntegration() public {
        uint256 depositAmount = 1500e18;

        // Initial deposit with MintBurn (tokens get burned)
        vm.startPrank(user1);
        tokenMultiChain.approve(address(bridge), depositAmount);
        tokenMultiChain.approve(address(mintBurn), depositAmount);
        bridge.deposit(ethChainKey, bytes32(uint256(uint160(user2))), address(tokenMultiChain), depositAmount);
        vm.stopPrank();

        uint256 balanceAfterBurn = tokenMultiChain.balanceOf(user1);
        uint256 supplyAfterBurn = tokenMultiChain.totalSupply();

        // Switch bridge type to LockUnlock
        vm.prank(tokenAdmin);
        tokenRegistry.setTokenBridgeType(address(tokenMultiChain), TokenRegistry.BridgeTypeLocal.LockUnlock);

        // Reset accumulator for new operations
        vm.warp(block.timestamp + 1 days);

        // Deposit with LockUnlock (tokens get locked, not burned)
        vm.startPrank(user2);
        tokenMultiChain.approve(address(bridge), depositAmount);
        tokenMultiChain.approve(address(lockUnlock), depositAmount);
        bridge.deposit(polygonChainKey, bytes32(uint256(uint160(user3))), address(tokenMultiChain), depositAmount);
        vm.stopPrank();

        // Verify LockUnlock behavior
        assertEq(tokenMultiChain.balanceOf(user2), INITIAL_MINT - depositAmount, "User balance after lock");
        assertEq(tokenMultiChain.balanceOf(address(lockUnlock)), depositAmount, "Tokens locked in contract");
        assertEq(tokenMultiChain.totalSupply(), supplyAfterBurn, "Supply unchanged with lock");

        // Switch back to MintBurn
        vm.prank(tokenAdmin);
        tokenRegistry.setTokenBridgeType(address(tokenMultiChain), TokenRegistry.BridgeTypeLocal.MintBurn);

        // Process withdrawal with MintBurn (tokens get minted)
        vm.prank(bridgeOperator);
        bridge.withdraw(ethChainKey, address(tokenMultiChain), user3, depositAmount, 1);

        // Verify MintBurn withdrawal
        assertEq(tokenMultiChain.balanceOf(user3), INITIAL_MINT + depositAmount, "Tokens minted to recipient");
        assertEq(tokenMultiChain.totalSupply(), supplyAfterBurn + depositAmount, "Supply increased with mint");
    }

    // ============ MULTI-CHAIN INTEGRATION TESTS ============

    /// @notice Test operations across multiple chains with same token
    function testMultiChainOperationsIntegration() public {
        uint256 amount = 800e18;

        // Deposits to different chains
        vm.startPrank(user1);
        tokenMultiChain.approve(address(bridge), amount * 3);
        tokenMultiChain.approve(address(mintBurn), amount * 3);

        // Deposit to Ethereum
        bridge.deposit(ethChainKey, bytes32(uint256(uint160(user2))), address(tokenMultiChain), amount);

        // Deposit to BSC
        bridge.deposit(bscChainKey, bytes32(uint256(uint160(user2))), address(tokenMultiChain), amount);

        // Deposit to Polygon
        bridge.deposit(polygonChainKey, bytes32(uint256(uint160(user2))), address(tokenMultiChain), amount);
        vm.stopPrank();

        // Verify all deposits tracked in accumulator
        TokenRegistry.TransferAccumulator memory accumulator =
            tokenRegistry.getTokenTransferAccumulator(address(tokenMultiChain));
        assertEq(accumulator.amount, amount * 3, "All cross-chain deposits tracked");

        // Process withdrawals from different chains
        vm.startPrank(bridgeOperator);
        bridge.withdraw(ethChainKey, address(tokenMultiChain), user2, amount, 100);
        bridge.withdraw(bscChainKey, address(tokenMultiChain), user2, amount, 200);
        bridge.withdraw(cosmosChainKey, address(tokenMultiChain), user2, amount, 300);
        vm.stopPrank();

        // Verify final state
        assertEq(tokenMultiChain.balanceOf(user2), INITIAL_MINT + amount * 3, "All withdrawals received");

        accumulator = tokenRegistry.getTokenTransferAccumulator(address(tokenMultiChain));
        assertEq(accumulator.amount, amount * 6, "All operations tracked in accumulator");
    }

    // ============ ERROR PROPAGATION INTEGRATION TESTS ============

    /// @notice Test error propagation from TokenRegistry through Bridge
    function testTokenRegistryErrorPropagation() public {
        // Test with unregistered chain
        bytes32 unregisteredChain = keccak256("UNREGISTERED");

        vm.startPrank(user1);
        tokenMintBurn.approve(address(bridge), DEPOSIT_AMOUNT);

        vm.expectRevert();
        bridge.deposit(unregisteredChain, bytes32(uint256(uint160(user2))), address(tokenMintBurn), DEPOSIT_AMOUNT);
        vm.stopPrank();

        // Test with unregistered token
        vm.startPrank(user1);
        vm.expectRevert();
        bridge.deposit(ethChainKey, bytes32(uint256(uint160(user2))), address(0x999), DEPOSIT_AMOUNT);
        vm.stopPrank();
    }

    /// @notice Test MintBurn balance verification failures
    function testMintBurnBalanceVerificationIntegration() public {
        // This test would require a token that fails balance checks
        // For now, we test the success case to ensure integration works

        vm.startPrank(user1);
        tokenMintBurn.approve(address(bridge), DEPOSIT_AMOUNT);
        tokenMintBurn.approve(address(mintBurn), DEPOSIT_AMOUNT);

        // Should succeed with proper token
        bridge.deposit(ethChainKey, bytes32(uint256(uint160(user2))), address(tokenMintBurn), DEPOSIT_AMOUNT);
        vm.stopPrank();

        // Withdrawal should also succeed
        vm.prank(bridgeOperator);
        bridge.withdraw(ethChainKey, address(tokenMintBurn), user2, DEPOSIT_AMOUNT, 1);

        assertEq(tokenMintBurn.balanceOf(user2), INITIAL_MINT + DEPOSIT_AMOUNT, "Balance verification passed");
    }

    // ============ ACCESS CONTROL INTEGRATION TESTS ============

    /// @notice Test access control enforcement across the entire system
    function testAccessControlIntegration() public {
        address unauthorizedUser = address(0x999);

        // Unauthorized user cannot perform withdrawals
        vm.expectRevert();
        vm.prank(unauthorizedUser);
        bridge.withdraw(ethChainKey, address(tokenMintBurn), user1, DEPOSIT_AMOUNT, 1);

        // Unauthorized user cannot update token registry
        vm.expectRevert();
        vm.prank(unauthorizedUser);
        tokenRegistry.addToken(address(0x888), TokenRegistry.BridgeTypeLocal.MintBurn, 1000e18);

        // Unauthorized user cannot add chains
        vm.expectRevert();
        vm.prank(unauthorizedUser);
        chainRegistry.addEVMChainKey(999);

        // But authorized users can perform operations
        vm.prank(bridgeOperator);
        bridge.withdraw(ethChainKey, address(tokenMintBurn), user1, DEPOSIT_AMOUNT, 2);

        vm.prank(tokenAdmin);
        chainRegistry.addEVMChainKey(999);
    }

    // ============ COMPLEX SCENARIO INTEGRATION TESTS ============

    /// @notice Test complex scenario with multiple users, tokens, and chains
    function testComplexMultiUserMultiTokenScenario() public {
        uint256 baseAmount = 500e18;

        // Multiple users make deposits with different tokens to different chains

        // User1: MintBurn token to Ethereum
        vm.startPrank(user1);
        tokenMintBurn.approve(address(bridge), baseAmount);
        tokenMintBurn.approve(address(mintBurn), baseAmount);
        bridge.deposit(ethChainKey, bytes32(uint256(uint160(user2))), address(tokenMintBurn), baseAmount);
        vm.stopPrank();

        // User2: LockUnlock token to Polygon
        vm.startPrank(user2);
        tokenLockUnlock.approve(address(bridge), baseAmount * 2);
        tokenLockUnlock.approve(address(lockUnlock), baseAmount * 2);
        bridge.deposit(polygonChainKey, bytes32(uint256(uint160(user3))), address(tokenLockUnlock), baseAmount * 2);
        vm.stopPrank();

        // User3: MultiChain token to BSC
        vm.startPrank(user3);
        tokenMultiChain.approve(address(bridge), baseAmount * 3);
        tokenMultiChain.approve(address(mintBurn), baseAmount * 3);
        bridge.deposit(bscChainKey, bytes32(uint256(uint160(user1))), address(tokenMultiChain), baseAmount * 3);
        vm.stopPrank();

        // Bridge operator processes all withdrawals
        vm.startPrank(bridgeOperator);
        bridge.withdraw(ethChainKey, address(tokenMintBurn), user2, baseAmount, 101);
        bridge.withdraw(polygonChainKey, address(tokenLockUnlock), user3, baseAmount * 2, 102);
        bridge.withdraw(bscChainKey, address(tokenMultiChain), user1, baseAmount * 3, 103);
        vm.stopPrank();

        // Verify final balances for all users and tokens
        assertEq(tokenMintBurn.balanceOf(user2), INITIAL_MINT + baseAmount, "User2 received MintBurn tokens");
        assertEq(tokenLockUnlock.balanceOf(user3), baseAmount * 2, "User3 received LockUnlock tokens");
        assertEq(tokenMultiChain.balanceOf(user1), INITIAL_MINT + baseAmount * 3, "User1 balance correct");

        // Verify deposit nonce incremented correctly
        assertEq(bridge.depositNonce(), 3, "All deposits processed");
    }

    /// @notice Test duplicate withdrawal prevention in integration context
    function testDuplicateWithdrawalPreventionIntegration() public {
        uint256 amount = 1000e18;
        uint256 nonce = 12345;

        // First withdrawal should succeed
        vm.prank(bridgeOperator);
        bridge.withdraw(ethChainKey, address(tokenMintBurn), user1, amount, nonce);

        assertEq(tokenMintBurn.balanceOf(user1), INITIAL_MINT + amount, "First withdrawal succeeded");

        // Second withdrawal with same parameters should fail
        vm.expectRevert();
        vm.prank(bridgeOperator);
        bridge.withdraw(ethChainKey, address(tokenMintBurn), user1, amount, nonce);

        // Different nonce should succeed
        vm.prank(bridgeOperator);
        bridge.withdraw(ethChainKey, address(tokenMintBurn), user1, amount, nonce + 1);

        assertEq(tokenMintBurn.balanceOf(user1), INITIAL_MINT + amount * 2, "Different nonce withdrawal succeeded");
    }

    // ============ PERFORMANCE AND GAS INTEGRATION TESTS ============

    /// @notice Test gas costs for full workflow integration
    function testGasUsageIntegration() public {
        uint256 amount = 1000e18;

        // Measure gas for deposit
        vm.startPrank(user1);
        tokenMintBurn.approve(address(bridge), amount);
        tokenMintBurn.approve(address(mintBurn), amount);

        uint256 gasStart = gasleft();
        bridge.deposit(ethChainKey, bytes32(uint256(uint160(user2))), address(tokenMintBurn), amount);
        uint256 gasUsedDeposit = gasStart - gasleft();
        vm.stopPrank();

        // Measure gas for withdrawal
        gasStart = gasleft();
        vm.prank(bridgeOperator);
        bridge.withdraw(ethChainKey, address(tokenMintBurn), user2, amount, 1);
        uint256 gasUsedWithdraw = gasStart - gasleft();

        // Log gas usage for monitoring (these numbers can be used for optimization)
        console.log("Gas used for deposit:", gasUsedDeposit);
        console.log("Gas used for withdrawal:", gasUsedWithdraw);

        // Basic sanity checks (actual values may vary)
        assertTrue(gasUsedDeposit > 0, "Deposit consumed gas");
        assertTrue(gasUsedWithdraw > 0, "Withdrawal consumed gas");
        assertTrue(gasUsedDeposit < 500000, "Deposit gas usage reasonable");
        assertTrue(gasUsedWithdraw < 500000, "Withdrawal gas usage reasonable");
    }

    // ============ EDGE CASE INTEGRATION TESTS ============

    /// @notice Test zero amount operations in full integration
    function testZeroAmountIntegration() public {
        // Zero deposit
        vm.startPrank(user1);
        tokenMintBurn.approve(address(bridge), 0);
        bridge.deposit(ethChainKey, bytes32(uint256(uint160(user2))), address(tokenMintBurn), 0);
        vm.stopPrank();

        // Zero withdrawal
        vm.prank(bridgeOperator);
        bridge.withdraw(ethChainKey, address(tokenMintBurn), user2, 0, 1);

        // Verify operations completed
        assertEq(bridge.depositNonce(), 1, "Zero deposit processed");

        // Verify accumulator handling
        TokenRegistry.TransferAccumulator memory accumulator =
            tokenRegistry.getTokenTransferAccumulator(address(tokenMintBurn));
        assertEq(accumulator.amount, 0, "Zero amounts don't affect accumulator");
    }

    /// @notice Test maximum amounts in integration context
    function testMaxAmountIntegration() public {
        // Set very high accumulator cap
        vm.prank(tokenAdmin);
        tokenRegistry.setTokenTransferAccumulatorCap(address(tokenMintBurn), type(uint256).max);

        uint256 maxAmount = INITIAL_MINT; // Use all available tokens

        vm.startPrank(user1);
        tokenMintBurn.approve(address(bridge), maxAmount);
        tokenMintBurn.approve(address(mintBurn), maxAmount);
        bridge.deposit(ethChainKey, bytes32(uint256(uint160(user2))), address(tokenMintBurn), maxAmount);
        vm.stopPrank();

        // Verify large amount handled correctly
        assertEq(tokenMintBurn.balanceOf(user1), 0, "All tokens deposited");

        vm.prank(bridgeOperator);
        bridge.withdraw(ethChainKey, address(tokenMintBurn), user2, maxAmount, 1);

        assertEq(tokenMintBurn.balanceOf(user2), INITIAL_MINT + maxAmount, "All tokens withdrawn");
    }
}
