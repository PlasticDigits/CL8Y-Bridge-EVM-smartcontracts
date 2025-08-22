// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {AccessManagerEnumerable} from "../src/AccessManagerEnumerable.sol";

contract DummyTarget {
    function a() external {}
    function b(uint256) external {}
}

contract AccessManagerEnumerableTest is Test {
    AccessManagerEnumerable internal manager;
    address internal admin;
    address internal user1;
    address internal user2;

    function setUp() public {
        admin = address(this);
        manager = new AccessManagerEnumerable(admin);
        user1 = address(0xBEEF);
        user2 = address(0xCAFE);
    }

    function test_RoleEnumeration_GrantRevokeRenounce() public {
        uint64 roleId = uint64(1);

        // grant
        manager.grantRole(roleId, user1, 0);
        manager.grantRole(roleId, user2, 0);

        // role -> accounts (granted)
        assertEq(manager.getRoleMemberCount(roleId), 2);
        assertTrue(manager.isRoleMember(roleId, user1));
        assertTrue(manager.isRoleMember(roleId, user2));

        // role -> accounts (active)
        assertEq(manager.getActiveRoleMemberCount(roleId), 2);
        assertTrue(manager.isRoleMemberActive(roleId, user1));
        assertTrue(manager.isRoleMemberActive(roleId, user2));

        // account -> roles (granted)
        assertEq(manager.getAccountRoleCount(user1), 1);
        assertEq(manager.getAccountRoleCount(user2), 1);
        assertTrue(manager.isAccountInRole(user1, roleId));
        assertTrue(manager.isAccountInRole(user2, roleId));

        // account -> roles (active)
        assertEq(manager.getActiveAccountRoleCount(user1), 1);
        assertEq(manager.getActiveAccountRoleCount(user2), 1);
        assertTrue(manager.isAccountInActiveRole(user1, roleId));
        assertTrue(manager.isAccountInActiveRole(user2, roleId));

        // revoke user1
        manager.revokeRole(roleId, user1);
        assertEq(manager.getRoleMemberCount(roleId), 1);
        assertFalse(manager.isRoleMember(roleId, user1));
        assertTrue(manager.isRoleMember(roleId, user2));
        assertEq(manager.getAccountRoleCount(user1), 0);
        assertEq(manager.getActiveAccountRoleCount(user1), 0);

        // renounce user2
        vm.prank(user2);
        manager.renounceRole(roleId, user2);
        assertEq(manager.getRoleMemberCount(roleId), 0);
        assertFalse(manager.isRoleMember(roleId, user2));
        assertEq(manager.getAccountRoleCount(user2), 0);
        assertEq(manager.getActiveAccountRoleCount(user2), 0);
    }

    function test_TargetAndSelectorEnumeration() public {
        DummyTarget target = new DummyTarget();
        address targetAddr = address(target);

        // selectors
        bytes4 selA = DummyTarget.a.selector;
        bytes4 selB = DummyTarget.b.selector;

        // Initially empty
        assertEq(manager.getManagedTargetCount(), 0);

        // assign roleId 5 to [a, b]
        uint64 roleA = uint64(5);
        bytes4[] memory sels = new bytes4[](2);
        sels[0] = selA;
        sels[1] = selB;
        manager.setTargetFunctionRole(targetAddr, sels, roleA);

        // target tracked
        assertEq(manager.getManagedTargetCount(), 1);
        assertTrue(manager.isManagedTarget(targetAddr));
        assertEq(manager.getTargetRoleSelectorCount(targetAddr, roleA), 2);
        assertTrue(manager.isTargetRoleSelector(targetAddr, roleA, selA));
        assertTrue(manager.isTargetRoleSelector(targetAddr, roleA, selB));

        // move selB to roleId 7
        uint64 roleB = uint64(7);
        bytes4[] memory selBOnly = new bytes4[](1);
        selBOnly[0] = selB;
        manager.setTargetFunctionRole(targetAddr, selBOnly, roleB);

        assertEq(manager.getTargetRoleSelectorCount(targetAddr, roleA), 1);
        assertEq(manager.getTargetRoleSelectorCount(targetAddr, roleB), 1);
        assertTrue(manager.isTargetRoleSelector(targetAddr, roleA, selA));
        assertTrue(manager.isTargetRoleSelector(targetAddr, roleB, selB));
        assertFalse(manager.isTargetRoleSelector(targetAddr, roleA, selB));
    }
}
