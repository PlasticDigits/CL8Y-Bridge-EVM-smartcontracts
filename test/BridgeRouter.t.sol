// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";

import {Cl8YBridge} from "../src/CL8YBridge.sol";
import {BridgeRouter} from "../src/BridgeRouter.sol";
import {TokenRegistry} from "../src/TokenRegistry.sol";
import {ChainRegistry} from "../src/ChainRegistry.sol";
import {TokenCl8yBridged} from "../src/TokenCl8yBridged.sol";
import {FactoryTokenCl8yBridged} from "../src/FactoryTokenCl8yBridged.sol";
import {MintBurn} from "../src/MintBurn.sol";
import {LockUnlock} from "../src/LockUnlock.sol";
import {IWETH} from "../src/interfaces/IWETH.sol";
import {GuardBridge} from "../src/GuardBridge.sol";
import {DatastoreSetAddress} from "../src/DatastoreSetAddress.sol";

import {AccessManager} from "@openzeppelin/contracts/access/manager/AccessManager.sol";

import {MockWETH} from "./mocks/MockWETH.sol";

contract NonPayableRecipient {
    // No payable receive; any ETH transfer will revert
    function ping() external {}
}

contract RefundRejector {
    function callWithdraw(
        BridgeRouter router,
        bytes32 srcChainKey,
        address token,
        address to,
        uint256 amount,
        uint256 nonce
    ) external payable {
        router.withdraw{value: msg.value}(srcChainKey, token, to, amount, nonce);
    }

    receive() external payable {
        revert();
    }
}

contract BridgeRouterTest is Test {
    AccessManager public accessManager;
    ChainRegistry public chainRegistry;
    TokenRegistry public tokenRegistry;
    MintBurn public mintBurn;
    LockUnlock public lockUnlock;
    Cl8YBridge public bridge;
    BridgeRouter public router;
    IWETH public weth;
    GuardBridge public guard;
    DatastoreSetAddress public datastore;

    FactoryTokenCl8yBridged public factory;
    TokenCl8yBridged public tokenMintBurn;
    TokenCl8yBridged public tokenLockUnlock;

    address public owner = address(1);
    address public bridgeOperator = address(2);
    address public tokenAdmin = address(3);
    address public user = address(4);

    bytes32 public ethChainKey;
    bytes32 public polygonChainKey;

    event DepositRequest(
        bytes32 indexed destChainKey,
        bytes32 indexed destTokenAddress,
        bytes32 indexed destAccount,
        address token,
        uint256 amount,
        uint256 nonce
    );

    function setUp() public {
        vm.prank(owner);
        accessManager = new AccessManager(owner);

        chainRegistry = new ChainRegistry(address(accessManager));
        tokenRegistry = new TokenRegistry(address(accessManager), chainRegistry);
        mintBurn = new MintBurn(address(accessManager));
        lockUnlock = new LockUnlock(address(accessManager));
        bridge = new Cl8YBridge(address(accessManager), tokenRegistry, mintBurn, lockUnlock);
        weth = IWETH(address(new MockWETH()));
        datastore = new DatastoreSetAddress();
        guard = new GuardBridge(address(accessManager), datastore);
        router = new BridgeRouter(address(accessManager), bridge, tokenRegistry, mintBurn, lockUnlock, weth, guard);

        factory = new FactoryTokenCl8yBridged(address(accessManager));

        // Roles
        vm.startPrank(owner);
        accessManager.grantRole(1, bridgeOperator, 0); // BRIDGE_OPERATOR_ROLE
        accessManager.grantRole(1, address(bridge), 0);
        accessManager.grantRole(1, address(mintBurn), 0);
        accessManager.grantRole(1, address(lockUnlock), 0);
        accessManager.grantRole(1, address(router), 0);

        // Permit bridge restricted functions
        bytes4[] memory bridgeSelectors = new bytes4[](7);
        bridgeSelectors[0] = bridge.withdraw.selector;
        bridgeSelectors[1] = bridge.deposit.selector;
        bridgeSelectors[2] = bridge.pause.selector;
        bridgeSelectors[3] = bridge.unpause.selector;
        bridgeSelectors[4] = bridge.approveWithdraw.selector;
        bridgeSelectors[5] = bridge.cancelWithdrawApproval.selector;
        bridgeSelectors[6] = bridge.setWithdrawDelay.selector;
        accessManager.setTargetFunctionRole(address(bridge), bridgeSelectors, 1);

        // Permit factory createToken for role 1 (tokenAdmin)
        bytes4[] memory factorySelectors = new bytes4[](1);
        factorySelectors[0] = factory.createToken.selector;
        accessManager.setTargetFunctionRole(address(factory), factorySelectors, 1);

        // Permit only pause/unpause as restricted; withdraw functions are public
        bytes4[] memory routerSelectors = new bytes4[](2);
        routerSelectors[0] = router.pause.selector;
        routerSelectors[1] = router.unpause.selector;
        accessManager.setTargetFunctionRole(address(router), routerSelectors, 1);

        // Permit MintBurn and LockUnlock restricted functions for role 1
        bytes4[] memory mintBurnSelectors = new bytes4[](2);
        mintBurnSelectors[0] = mintBurn.mint.selector;
        mintBurnSelectors[1] = mintBurn.burn.selector;
        accessManager.setTargetFunctionRole(address(mintBurn), mintBurnSelectors, 1);

        bytes4[] memory lockSelectors = new bytes4[](2);
        lockSelectors[0] = lockUnlock.lock.selector;
        lockSelectors[1] = lockUnlock.unlock.selector;
        accessManager.setTargetFunctionRole(address(lockUnlock), lockSelectors, 1);

        // Allow admin to manage registries
        bytes4[] memory chainRegistrySelectors = new bytes4[](1);
        chainRegistrySelectors[0] = chainRegistry.addEVMChainKey.selector;
        accessManager.setTargetFunctionRole(address(chainRegistry), chainRegistrySelectors, 1);

        bytes4[] memory tokenRegistrySelectors = new bytes4[](3);
        tokenRegistrySelectors[0] = tokenRegistry.addToken.selector;
        tokenRegistrySelectors[1] = tokenRegistry.addTokenDestChainKey.selector;
        tokenRegistrySelectors[2] = tokenRegistry.setTokenBridgeType.selector;
        accessManager.setTargetFunctionRole(address(tokenRegistry), tokenRegistrySelectors, 1);
        vm.stopPrank();

        // Default: allow immediate withdraw after approval in tests
        vm.prank(bridgeOperator);
        bridge.setWithdrawDelay(0);

        // Chains
        ethChainKey = chainRegistry.getChainKeyEVM(1);
        polygonChainKey = chainRegistry.getChainKeyEVM(137);
        // tokenAdmin doesn't have role by default; grant and add chains
        vm.prank(owner);
        accessManager.grantRole(1, tokenAdmin, 0);
        vm.prank(tokenAdmin);
        chainRegistry.addEVMChainKey(1);
        vm.prank(tokenAdmin);
        chainRegistry.addEVMChainKey(137);

        // Tokens
        vm.prank(tokenAdmin);
        address t1 = factory.createToken("Mint", "MINT", "logo");
        tokenMintBurn = TokenCl8yBridged(t1);
        vm.prank(tokenAdmin);
        address t2 = factory.createToken("Lock", "LOCK", "logo");
        tokenLockUnlock = TokenCl8yBridged(t2);

        vm.startPrank(owner);
        bytes4[] memory tokenMintSelectors = new bytes4[](1);
        tokenMintSelectors[0] = tokenMintBurn.mint.selector;
        accessManager.setTargetFunctionRole(address(tokenMintBurn), tokenMintSelectors, 1);
        accessManager.setTargetFunctionRole(address(tokenLockUnlock), tokenMintSelectors, 1);
        accessManager.grantRole(1, address(mintBurn), 0);
        accessManager.grantRole(1, address(lockUnlock), 0);
        vm.stopPrank();

        // Registry config
        vm.prank(tokenAdmin);
        tokenRegistry.addToken(address(tokenMintBurn), TokenRegistry.BridgeTypeLocal.MintBurn);
        vm.prank(tokenAdmin);
        tokenRegistry.addToken(address(tokenLockUnlock), TokenRegistry.BridgeTypeLocal.LockUnlock);
        vm.prank(tokenAdmin);
        tokenRegistry.addTokenDestChainKey(
            address(tokenMintBurn), ethChainKey, bytes32(uint256(uint160(address(0x1111)))), 18
        );
        vm.prank(tokenAdmin);
        tokenRegistry.addTokenDestChainKey(
            address(tokenLockUnlock), polygonChainKey, bytes32(uint256(uint160(address(0x2222)))), 18
        );
        // Register WETH for native path
        vm.prank(tokenAdmin);
        tokenRegistry.addToken(address(weth), TokenRegistry.BridgeTypeLocal.LockUnlock);
        vm.prank(tokenAdmin);
        tokenRegistry.addTokenDestChainKey(address(weth), ethChainKey, bytes32(uint256(uint160(address(0x3333)))), 18);

        // Mint user balances using authorized role
        vm.prank(bridgeOperator);
        tokenMintBurn.mint(user, 10_000e18);
        vm.prank(bridgeOperator);
        tokenLockUnlock.mint(user, 10_000e18);
    }

    function testRouterDepositERC20_MintBurn() public {
        // User approvals to downstream module
        vm.startPrank(user);
        tokenMintBurn.approve(address(mintBurn), 1_000e18);
        vm.stopPrank();

        vm.expectEmit(true, true, true, true);
        emit DepositRequest(
            ethChainKey,
            tokenRegistry.getTokenDestChainTokenAddress(address(tokenMintBurn), ethChainKey),
            bytes32(uint256(uint160(user))),
            address(tokenMintBurn),
            1_000e18,
            0
        );
        vm.prank(user);
        router.deposit(address(tokenMintBurn), 1_000e18, ethChainKey, bytes32(uint256(uint160(user))));
        assertEq(bridge.depositNonce(), 1);
    }

    function testRouterDepositERC20_LockUnlock() public {
        // Switch type already set to LockUnlock and approve downstream
        vm.startPrank(user);
        tokenLockUnlock.approve(address(lockUnlock), 500e18);
        vm.stopPrank();

        vm.expectEmit(true, true, true, true);
        emit DepositRequest(
            polygonChainKey,
            tokenRegistry.getTokenDestChainTokenAddress(address(tokenLockUnlock), polygonChainKey),
            bytes32(uint256(uint160(user))),
            address(tokenLockUnlock),
            500e18,
            0
        );
        vm.prank(user);
        router.deposit(address(tokenLockUnlock), 500e18, polygonChainKey, bytes32(uint256(uint160(user))));
        assertEq(bridge.depositNonce(), 1);
    }

    function testRouterDepositNative() public {
        vm.deal(user, 1 ether);
        vm.prank(user);
        router.depositNative{value: 0.25 ether}(ethChainKey, bytes32(uint256(uint160(user))));
        assertEq(bridge.depositNonce(), 1);
    }

    function testRouterPauseUnpause() public {
        // Pause router via authorized operator
        vm.prank(bridgeOperator);
        router.pause();

        // ERC20 deposit should revert when paused
        vm.prank(user);
        vm.expectRevert();
        router.deposit(address(tokenMintBurn), 1, ethChainKey, bytes32(uint256(uint160(user))));

        // Native deposit should revert when paused
        vm.deal(user, 1);
        vm.prank(user);
        vm.expectRevert();
        router.depositNative{value: 1}(ethChainKey, bytes32(uint256(uint160(user))));

        // Unpause and perform a minimal deposit
        vm.prank(bridgeOperator);
        router.unpause();

        vm.startPrank(user);
        tokenMintBurn.approve(address(mintBurn), 1);
        vm.stopPrank();
        vm.prank(user);
        router.deposit(address(tokenMintBurn), 1, ethChainKey, bytes32(uint256(uint160(user))));
    }

    function testRouterWithdrawERC20() public {
        // Perform a deposit first to increment accumulator
        vm.startPrank(user);
        tokenMintBurn.approve(address(mintBurn), 100e18);
        vm.stopPrank();
        vm.prank(user);
        router.deposit(address(tokenMintBurn), 100e18, ethChainKey, bytes32(uint256(uint160(user))));

        // Approve withdraw and then withdraw via router to user (fee = 0)
        vm.prank(bridgeOperator);
        bridge.approveWithdraw(ethChainKey, address(tokenMintBurn), user, 50e18, 123, 0, address(0), false);
        vm.prank(user);
        router.withdraw(ethChainKey, address(tokenMintBurn), user, 50e18, 123);
    }

    function testRouterWithdrawNative() public {
        // Ensure weth balance at router then withdraw native to user
        vm.deal(user, 1 ether);
        vm.prank(user);
        router.depositNative{value: 0.1 ether}(ethChainKey, bytes32(uint256(uint160(user))));

        uint256 balBefore = user.balance;
        // Approve native withdraw on wrapped token to router with deductFromAmount
        vm.prank(bridgeOperator);
        bridge.approveWithdraw(ethChainKey, address(weth), address(router), 0.05 ether, 321, 0, address(0), true);
        vm.prank(user);
        router.withdrawNative(ethChainKey, 0.05 ether, 321, payable(user));
        assertEq(user.balance, balBefore + 0.05 ether);
    }

    function testRouterDepositNative_RevertOnZeroValue() public {
        vm.prank(user);
        vm.expectRevert();
        router.depositNative{value: 0}(ethChainKey, bytes32(uint256(uint160(user))));
    }

    function testRouterDepositNative_NoApproveNeededOnSecondCall() public {
        vm.deal(user, 2 ether);
        // First call triggers approval
        vm.prank(user);
        router.depositNative{value: 1 ether}(ethChainKey, bytes32(uint256(uint160(user))));
        // Second call should skip approval branch (allowance already max)
        vm.prank(user);
        router.depositNative{value: 0.5 ether}(ethChainKey, bytes32(uint256(uint160(user))));
    }

    function testRouterWithdrawNative_RevertOnNativeTransferFailure() public {
        // Prepare wrapped balance at router via depositNative
        vm.deal(user, 1 ether);
        vm.prank(user);
        router.depositNative{value: 0.2 ether}(ethChainKey, bytes32(uint256(uint160(user))));

        // Use a non-payable recipient so ETH transfer fails
        NonPayableRecipient npc = new NonPayableRecipient();
        vm.prank(bridgeOperator);
        bridge.approveWithdraw(ethChainKey, address(weth), address(router), 0.1 ether, 999, 0, address(0), true);
        vm.prank(user);
        vm.expectRevert();
        router.withdrawNative(ethChainKey, 0.1 ether, 999, payable(address(npc)));
    }

    function testRouterWithdrawERC20_FeeUnderpayReverts() public {
        // Prepare deposit to increment accumulator
        vm.startPrank(user);
        tokenMintBurn.approve(address(mintBurn), 1e18);
        vm.stopPrank();
        vm.prank(user);
        router.deposit(address(tokenMintBurn), 1e18, ethChainKey, bytes32(uint256(uint160(user))));

        // Approve withdraw with non-zero fee
        vm.prank(bridgeOperator);
        bridge.approveWithdraw(
            ethChainKey, address(tokenMintBurn), user, 1e18, 1000, 0.01 ether, address(0x7777), false
        );

        // Underpay should revert
        vm.deal(user, 1 ether);
        vm.prank(user);
        vm.expectRevert();
        router.withdraw{value: 0.009 ether}(ethChainKey, address(tokenMintBurn), user, 1e18, 1000);
    }

    function testRouterWithdrawERC20_ExactFeeNoRefund() public {
        // Approve withdraw with a fee and recipient
        address feeRecipient = address(0xAAAA);
        vm.prank(bridgeOperator);
        bridge.approveWithdraw(ethChainKey, address(tokenMintBurn), user, 2e18, 2001, 0.02 ether, feeRecipient, false);

        // Exact fee, no refund branch
        vm.deal(user, 1 ether);
        uint256 userBalBefore = user.balance;
        uint256 feeBalBefore = feeRecipient.balance;

        vm.prank(user);
        router.withdraw{value: 0.02 ether}(ethChainKey, address(tokenMintBurn), user, 2e18, 2001);

        assertEq(user.balance, userBalBefore - 0.02 ether);
        assertEq(feeRecipient.balance, feeBalBefore + 0.02 ether);
    }

    function testRouterWithdrawERC20_OverpayAllowedForwardedToRecipient() public {
        // Approve withdraw with a fee
        address feeRecipient = address(0xBBBB);
        vm.prank(bridgeOperator);
        bridge.approveWithdraw(ethChainKey, address(tokenMintBurn), user, 1e18, 2002, 0.01 ether, feeRecipient, false);

        // Overpay forwards entire msg.value to feeRecipient
        vm.deal(user, 1 ether);
        uint256 beforeFee = feeRecipient.balance;
        vm.prank(user);
        router.withdraw{value: 0.02 ether}(ethChainKey, address(tokenMintBurn), user, 1e18, 2002);
        assertEq(feeRecipient.balance, beforeFee + 0.02 ether);
    }

    function testRouterWithdrawERC20_FeeZeroButMsgValueNonZeroReverts() public {
        // Approve withdraw with zero fee
        vm.prank(bridgeOperator);
        bridge.approveWithdraw(ethChainKey, address(tokenMintBurn), user, 1e18, 2003, 0, address(0), false);

        vm.deal(user, 1 ether);
        vm.prank(user);
        vm.expectRevert();
        router.withdraw{value: 1}(ethChainKey, address(tokenMintBurn), user, 1e18, 2003);
    }

    function testRouterWithdrawNative_RevertWhenApprovalNotNativePath() public {
        // Prepare wrapped balance at router via depositNative
        vm.deal(user, 0.2 ether);
        vm.prank(user);
        router.depositNative{value: 0.2 ether}(ethChainKey, bytes32(uint256(uint160(user))));

        // Approve with deductFromAmount = false to trigger router check
        vm.prank(bridgeOperator);
        bridge.approveWithdraw(ethChainKey, address(weth), address(router), 0.05 ether, 5001, 0, address(0), false);

        vm.prank(user);
        vm.expectRevert();
        router.withdrawNative(ethChainKey, 0.05 ether, 5001, payable(user));
    }

    function testRouterWithdrawNative_FeeExceedsAmountReverts() public {
        // Prepare wrapped balance at router via depositNative
        vm.deal(user, 0.2 ether);
        vm.prank(user);
        router.depositNative{value: 0.2 ether}(ethChainKey, bytes32(uint256(uint160(user))));

        // Approve with fee > amount
        vm.prank(bridgeOperator);
        bridge.approveWithdraw(
            ethChainKey, address(weth), address(router), 0.05 ether, 5002, 0.06 ether, address(0xD00D), true
        );

        vm.prank(user);
        vm.expectRevert();
        router.withdrawNative(ethChainKey, 0.05 ether, 5002, payable(user));
    }

    function testRouterWithdrawNative_FeeRecipientTransferFails() public {
        // Prepare wrapped balance at router via depositNative
        vm.deal(user, 0.2 ether);
        vm.prank(user);
        router.depositNative{value: 0.2 ether}(ethChainKey, bytes32(uint256(uint160(user))));

        // Use non-payable recipient for fee
        NonPayableRecipient npc = new NonPayableRecipient();
        vm.prank(bridgeOperator);
        bridge.approveWithdraw(
            ethChainKey, address(weth), address(router), 0.05 ether, 5003, 0.03 ether, address(npc), true
        );

        vm.prank(user);
        vm.expectRevert();
        router.withdrawNative(ethChainKey, 0.05 ether, 5003, payable(user));
    }

    function testRouterWithdrawERC20_OverpayGoesToFeeRecipient() public {
        // Approve with a fee
        address feeRecipient = address(0x7777);
        vm.prank(bridgeOperator);
        bridge.approveWithdraw(ethChainKey, address(tokenMintBurn), user, 1e18, 6000, 0.01 ether, feeRecipient, false);

        vm.deal(user, 1 ether);
        uint256 beforeFee = feeRecipient.balance;
        vm.prank(user);
        router.withdraw{value: 0.010000000000000001 ether}(ethChainKey, address(tokenMintBurn), user, 1e18, 6000);
        assertEq(feeRecipient.balance, beforeFee + 0.010000000000000001 ether);
    }

    function testRouterWithdrawERC20_OverpayAllToRecipient() public {
        // Approve withdraw with a fee and recipient
        address feeRecipient = address(0x8888);
        vm.prank(bridgeOperator);
        bridge.approveWithdraw(ethChainKey, address(tokenMintBurn), user, 1e18, 2000, 0.01 ether, feeRecipient, false);

        vm.deal(user, 1 ether);
        uint256 feeBalBefore = feeRecipient.balance;
        vm.prank(user);
        router.withdraw{value: 0.010000000000000001 ether}(ethChainKey, address(tokenMintBurn), user, 1e18, 2000);
        assertEq(feeRecipient.balance, feeBalBefore + 0.010000000000000001 ether);
    }

    function testRouterWithdrawERC20_RevertWhenApprovalRequiresNativePath() public {
        // Approve ERC20 withdraw with deductFromAmount = true
        vm.prank(bridgeOperator);
        bridge.approveWithdraw(ethChainKey, address(tokenMintBurn), user, 1e18, 3000, 0, address(0), true);
        vm.prank(user);
        vm.expectRevert();
        router.withdraw(ethChainKey, address(tokenMintBurn), user, 1e18, 3000);
    }

    function testRouterWithdrawNative_FeeSplitToRecipient() public {
        // Ensure wrapped balance at router via depositNative
        vm.deal(user, 1 ether);
        vm.prank(user);
        router.depositNative{value: 0.2 ether}(ethChainKey, bytes32(uint256(uint160(user))));

        // Approve native withdraw with fee > 0
        address feeRecipient = address(0x9999);
        vm.prank(bridgeOperator);
        bridge.approveWithdraw(
            ethChainKey, address(weth), address(router), 0.1 ether, 4000, 0.03 ether, feeRecipient, true
        );

        uint256 toBalBefore = user.balance;
        uint256 feeBalBefore = feeRecipient.balance;
        vm.prank(user);
        router.withdrawNative(ethChainKey, 0.1 ether, 4000, payable(user));
        assertEq(user.balance, toBalBefore + 0.07 ether);
        assertEq(feeRecipient.balance, feeBalBefore + 0.03 ether);
    }
}
