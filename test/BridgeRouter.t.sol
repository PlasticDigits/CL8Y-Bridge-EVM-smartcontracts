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

import {AccessManager} from "@openzeppelin/contracts/access/manager/AccessManager.sol";

import {MockWETH} from "./mocks/MockWETH.sol";

contract NonPayableRecipient {
    // No payable receive; any ETH transfer will revert
    function ping() external {}
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
        bytes32 indexed destChainKey, bytes32 indexed destAccount, address indexed token, uint256 amount, uint256 nonce
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
        router = new BridgeRouter(address(accessManager), bridge, tokenRegistry, mintBurn, lockUnlock, weth);

        factory = new FactoryTokenCl8yBridged(address(accessManager));

        // Roles
        vm.startPrank(owner);
        accessManager.grantRole(1, bridgeOperator, 0); // BRIDGE_OPERATOR_ROLE
        accessManager.grantRole(1, address(bridge), 0);
        accessManager.grantRole(1, address(mintBurn), 0);
        accessManager.grantRole(1, address(lockUnlock), 0);
        accessManager.grantRole(1, address(router), 0);

        // Permit bridge restricted functions
        bytes4[] memory bridgeSelectors = new bytes4[](4);
        bridgeSelectors[0] = bridge.withdraw.selector;
        bridgeSelectors[1] = bridge.deposit.selector;
        bridgeSelectors[2] = bridge.pause.selector;
        bridgeSelectors[3] = bridge.unpause.selector;
        accessManager.setTargetFunctionRole(address(bridge), bridgeSelectors, 1);

        // Permit factory createToken for role 1 (tokenAdmin)
        bytes4[] memory factorySelectors = new bytes4[](1);
        factorySelectors[0] = factory.createToken.selector;
        accessManager.setTargetFunctionRole(address(factory), factorySelectors, 1);

        // Permit router restricted functions for role 1
        bytes4[] memory routerSelectors = new bytes4[](4);
        routerSelectors[0] = router.withdraw.selector;
        routerSelectors[1] = router.withdrawNative.selector;
        routerSelectors[2] = router.pause.selector;
        routerSelectors[3] = router.unpause.selector;
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

        bytes4[] memory tokenRegistrySelectors = new bytes4[](5);
        tokenRegistrySelectors[0] = tokenRegistry.addToken.selector;
        tokenRegistrySelectors[1] = tokenRegistry.addTokenDestChainKey.selector;
        tokenRegistrySelectors[2] = tokenRegistry.setTokenBridgeType.selector;
        tokenRegistrySelectors[3] = tokenRegistry.setTokenTransferAccumulatorCap.selector;
        tokenRegistrySelectors[4] = tokenRegistry.updateTokenTransferAccumulator.selector;
        accessManager.setTargetFunctionRole(address(tokenRegistry), tokenRegistrySelectors, 1);
        vm.stopPrank();

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
        tokenRegistry.addToken(address(tokenMintBurn), TokenRegistry.BridgeTypeLocal.MintBurn, type(uint256).max);
        vm.prank(tokenAdmin);
        tokenRegistry.addToken(address(tokenLockUnlock), TokenRegistry.BridgeTypeLocal.LockUnlock, type(uint256).max);
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
        tokenRegistry.addToken(address(weth), TokenRegistry.BridgeTypeLocal.LockUnlock, type(uint256).max);
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
        emit DepositRequest(ethChainKey, bytes32(uint256(uint160(user))), address(tokenMintBurn), 1_000e18, 0);
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
        emit DepositRequest(polygonChainKey, bytes32(uint256(uint160(user))), address(tokenLockUnlock), 500e18, 0);
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

        // Withdraw via router to user
        vm.prank(bridgeOperator);
        router.withdraw(ethChainKey, address(tokenMintBurn), user, 50e18, 123);
    }

    function testRouterWithdrawNative() public {
        // Ensure weth balance at router then withdraw native to user
        vm.deal(user, 1 ether);
        vm.prank(user);
        router.depositNative{value: 0.1 ether}(ethChainKey, bytes32(uint256(uint160(user))));

        uint256 balBefore = user.balance;
        vm.prank(bridgeOperator);
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
        vm.expectRevert();
        router.withdrawNative(ethChainKey, 0.1 ether, 999, payable(address(npc)));
    }
}
