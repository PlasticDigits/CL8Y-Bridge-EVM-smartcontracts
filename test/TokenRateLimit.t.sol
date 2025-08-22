// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {AccessManager} from "@openzeppelin/contracts/access/manager/AccessManager.sol";

import {TokenRateLimit} from "../src/TokenRateLimit.sol";
import {GuardBridge} from "../src/GuardBridge.sol";
import {DatastoreSetAddress} from "../src/DatastoreSetAddress.sol";

contract TokenRateLimitTest is Test {
    AccessManager public accessManager;
    TokenRateLimit public rateLimit;
    GuardBridge public guard;
    DatastoreSetAddress public datastore;

    address public owner = address(1);
    address public user = address(2);
    address public tokenA = address(0xA1);
    address public tokenB = address(0xB2);

    function setUp() public {
        vm.prank(owner);
        accessManager = new AccessManager(owner);
        rateLimit = new TokenRateLimit(address(accessManager));
        datastore = new DatastoreSetAddress();
        guard = new GuardBridge(address(accessManager), datastore);

        // Grant test contract role 1 and set it as allowed caller for admin functions
        vm.startPrank(owner);
        accessManager.grantRole(1, address(this), 0);

        // Allow rate limit admin setters
        bytes4[] memory rl = new bytes4[](3);
        rl[0] = rateLimit.setDepositLimit.selector;
        rl[1] = rateLimit.setWithdrawLimit.selector;
        rl[2] = rateLimit.setLimitsBatch.selector;
        accessManager.setTargetFunctionRole(address(rateLimit), rl, 1);

        // Allow guard module mgmt
        bytes4[] memory gb = new bytes4[](6);
        gb[0] = guard.addGuardModuleDeposit.selector;
        gb[1] = guard.addGuardModuleWithdraw.selector;
        gb[2] = guard.addGuardModuleAccount.selector;
        gb[3] = guard.removeGuardModuleDeposit.selector;
        gb[4] = guard.removeGuardModuleWithdraw.selector;
        gb[5] = guard.removeGuardModuleAccount.selector;
        accessManager.setTargetFunctionRole(address(guard), gb, 1);
        vm.stopPrank();
    }

    function test_DefaultUnlimited_NoRevert() public {
        rateLimit.checkDeposit(tokenA, 1_000_000 ether, user);
        rateLimit.checkWithdraw(tokenA, 1_000_000 ether, user);
    }

    function test_DepositLimit_WindowAndReset() public {
        rateLimit.setDepositLimit(tokenA, 500);
        rateLimit.checkDeposit(tokenA, 200, user);
        rateLimit.checkDeposit(tokenA, 300, user);
        vm.expectRevert();
        rateLimit.checkDeposit(tokenA, 1, user);

        // Advance just before window end, still should revert
        vm.warp(block.timestamp + 24 hours - 1);
        vm.expectRevert();
        rateLimit.checkDeposit(tokenA, 1, user);

        // Advance to boundary; new window begins at boundary (<= fix)
        vm.warp(block.timestamp + 1);
        // Should not revert and usage resets
        rateLimit.checkDeposit(tokenA, 500, user);
    }

    function test_WithdrawLimit_WindowAndReset() public {
        rateLimit.setWithdrawLimit(tokenA, 500);
        rateLimit.checkWithdraw(tokenA, 400, user);
        rateLimit.checkWithdraw(tokenA, 100, user);
        vm.expectRevert();
        rateLimit.checkWithdraw(tokenA, 1, user);

        vm.warp(block.timestamp + 24 hours);
        rateLimit.checkWithdraw(tokenA, 500, user);
    }

    function test_MultiTokenIndependentAccounting() public {
        rateLimit.setDepositLimit(tokenA, 500);
        rateLimit.setDepositLimit(tokenB, 1_000);
        rateLimit.checkDeposit(tokenA, 500, user);
        rateLimit.checkDeposit(tokenB, 1_000, user);
        vm.expectRevert();
        rateLimit.checkDeposit(tokenA, 1, user);
        // tokenB still fine next window
        vm.warp(block.timestamp + 1);
        vm.expectRevert();
        rateLimit.checkDeposit(tokenB, 1, user); // same window for B

        // Move full window; both reset independently
        vm.warp(block.timestamp + 24 hours);
        rateLimit.checkDeposit(tokenA, 500, user);
        rateLimit.checkDeposit(tokenB, 1_000, user);
    }

    function test_Integration_With_GuardBridge() public {
        // Register the module for both directions
        guard.addGuardModuleDeposit(address(rateLimit));
        guard.addGuardModuleWithdraw(address(rateLimit));

        // Configure limits
        rateLimit.setDepositLimit(tokenA, 500);
        rateLimit.setWithdrawLimit(tokenA, 400);

        // Enforced via guard aggregator
        guard.checkDeposit(tokenA, 300, user);
        guard.checkDeposit(tokenA, 200, user);
        vm.expectRevert();
        guard.checkDeposit(tokenA, 1, user);

        guard.checkWithdraw(tokenA, 400, user);
        vm.expectRevert();
        guard.checkWithdraw(tokenA, 1, user);
    }

    function test_GetCurrentUsed_Deposit_And_Withdraw_ExpiredAndActive() public {
        // Configure limits and do operations
        rateLimit.setDepositLimit(tokenA, 100);
        rateLimit.setWithdrawLimit(tokenA, 150);

        // Initially zero
        assertEq(rateLimit.getCurrentDepositUsed(tokenA), 0);
        assertEq(rateLimit.getCurrentWithdrawUsed(tokenA), 0);

        // Accrue some usage
        rateLimit.checkDeposit(tokenA, 60, user);
        rateLimit.checkWithdraw(tokenA, 50, user);
        assertEq(rateLimit.getCurrentDepositUsed(tokenA), 60);
        assertEq(rateLimit.getCurrentWithdrawUsed(tokenA), 50);

        // Still in same window
        vm.warp(block.timestamp + 24 hours - 1);
        assertEq(rateLimit.getCurrentDepositUsed(tokenA), 60);
        assertEq(rateLimit.getCurrentWithdrawUsed(tokenA), 50);

        // After full window has passed (boundary), usage resets to 0
        vm.warp(block.timestamp + 2);
        assertEq(rateLimit.getCurrentDepositUsed(tokenA), 0);
        assertEq(rateLimit.getCurrentWithdrawUsed(tokenA), 0);
    }

    function test_SetLimitsBatch_And_Usage() public {
        address[] memory toks = new address[](2);
        toks[0] = tokenA;
        toks[1] = tokenB;
        uint256[] memory deps = new uint256[](2);
        deps[0] = 11;
        deps[1] = 22;
        uint256[] memory withs = new uint256[](2);
        withs[0] = 33;
        withs[1] = 44;
        rateLimit.setLimitsBatch(toks, deps, withs);

        // Exercise both tokens and directions
        rateLimit.checkDeposit(tokenA, 11, user);
        vm.expectRevert();
        rateLimit.checkDeposit(tokenA, 1, user);
        rateLimit.checkWithdraw(tokenB, 44, user);
        vm.expectRevert();
        rateLimit.checkWithdraw(tokenB, 1, user);
    }

    function test_CheckAccount_NoOp() public {
        rateLimit.checkAccount(user);
        rateLimit.checkAccount(address(0xBEEF));
    }

    function test_SetDepositLimitZero_MakesUnlimitedEvenAfterUsage() public {
        rateLimit.setDepositLimit(tokenA, 10);
        rateLimit.checkDeposit(tokenA, 10, user);
        vm.expectRevert();
        rateLimit.checkDeposit(tokenA, 1, user);
        // Now switch to unlimited and ensure it bypasses accounting
        rateLimit.setDepositLimit(tokenA, 0);
        rateLimit.checkDeposit(tokenA, type(uint256).max / 2, user);
    }

    function test_SetWithdrawLimitZero_MakesUnlimitedEvenAfterUsage() public {
        rateLimit.setWithdrawLimit(tokenA, 9);
        rateLimit.checkWithdraw(tokenA, 9, user);
        vm.expectRevert();
        rateLimit.checkWithdraw(tokenA, 1, user);
        rateLimit.setWithdrawLimit(tokenA, 0);
        rateLimit.checkWithdraw(tokenA, type(uint256).max / 2, user);
    }
}
