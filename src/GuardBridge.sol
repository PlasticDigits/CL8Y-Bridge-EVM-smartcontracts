// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.30;

import {IGuardBridge} from "./interfaces/IGuardBridge.sol";
import {DatastoreSetAddress, DatastoreSetIdAddress} from "./DatastoreSetAddress.sol";
import {AccessManaged} from "@openzeppelin/contracts/access/manager/AccessManaged.sol";

contract GuardBridge is IGuardBridge, AccessManaged {
    DatastoreSetAddress public immutable datastoreAddress;

    error CallFailed();

    DatastoreSetIdAddress public constant GUARD_MODULES_DEPOSIT =
        DatastoreSetIdAddress.wrap(keccak256("GUARD_MODULES_DEPOSIT"));

    DatastoreSetIdAddress public constant GUARD_MODULES_WITHDRAW =
        DatastoreSetIdAddress.wrap(keccak256("GUARD_MODULES_WITHDRAW"));

    DatastoreSetIdAddress public constant GUARD_MODULES_ACCOUNT =
        DatastoreSetIdAddress.wrap(keccak256("GUARD_MODULES_ACCOUNT"));

    constructor(address _initialAuthority, DatastoreSetAddress _datastoreAddress) AccessManaged(_initialAuthority) {
        datastoreAddress = _datastoreAddress;
    }

    function checkAccount(address account) external {
        uint256 length = datastoreAddress.length(address(this), GUARD_MODULES_ACCOUNT);
        for (uint256 i; i < length; i++) {
            address guardModule = datastoreAddress.at(address(this), GUARD_MODULES_ACCOUNT, i);
            IGuardBridge(guardModule).checkAccount(account);
        }
    }

    function checkDeposit(address token, uint256 amount, address sender) external {
        uint256 length = datastoreAddress.length(address(this), GUARD_MODULES_DEPOSIT);
        for (uint256 i; i < length; i++) {
            address guardModule = datastoreAddress.at(address(this), GUARD_MODULES_DEPOSIT, i);
            IGuardBridge(guardModule).checkDeposit(token, amount, sender);
        }
    }

    function checkWithdraw(address token, uint256 amount, address sender) external {
        uint256 length = datastoreAddress.length(address(this), GUARD_MODULES_WITHDRAW);
        for (uint256 i; i < length; i++) {
            address guardModule = datastoreAddress.at(address(this), GUARD_MODULES_WITHDRAW, i);
            IGuardBridge(guardModule).checkWithdraw(token, amount, sender);
        }
    }

    function addGuardModuleDeposit(address guardModule) external restricted {
        datastoreAddress.add(GUARD_MODULES_DEPOSIT, guardModule);
    }

    function removeGuardModuleDeposit(address guardModule) external restricted {
        datastoreAddress.remove(GUARD_MODULES_DEPOSIT, guardModule);
    }

    function addGuardModuleWithdraw(address guardModule) external restricted {
        datastoreAddress.add(GUARD_MODULES_WITHDRAW, guardModule);
    }

    function removeGuardModuleWithdraw(address guardModule) external restricted {
        datastoreAddress.remove(GUARD_MODULES_WITHDRAW, guardModule);
    }

    function addGuardModuleAccount(address guardModule) external restricted {
        datastoreAddress.add(GUARD_MODULES_ACCOUNT, guardModule);
    }

    function removeGuardModuleAccount(address guardModule) external restricted {
        datastoreAddress.remove(GUARD_MODULES_ACCOUNT, guardModule);
    }

    function execute(address target, bytes calldata data) external payable restricted returns (bytes memory) {
        (bool success, bytes memory result) = target.call{value: msg.value}(data);
        require(success, CallFailed());
        return result;
    }
}
