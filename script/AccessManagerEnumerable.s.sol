// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {AccessManagerEnumerable} from "src/AccessManagerEnumerable.sol";

contract AccessManagerScript is Script {
    AccessManagerEnumerable public accessManager;

    address public constant CZ_MANAGER = 0xCd4Eb82CFC16d5785b4f7E3bFC255E735e79F39c;
    bytes32 public constant SALT = keccak256("ACCESS_MANAGER_ENUMERABLE_V1");

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        // Deploy AccessManagerEnumerable deterministically with CREATE2
        accessManager = new AccessManagerEnumerable{salt: SALT}(CZ_MANAGER);

        console.log("AccessManagerEnumerable deployed at:", address(accessManager));
        console.log("Initial admin (CZ_MANAGER):", CZ_MANAGER);
        console.logBytes32(SALT);

        vm.stopBroadcast();
    }
}
