// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {AccessManager} from "@openzeppelin/contracts/access/manager/AccessManager.sol";

contract AccessManagerScript is Script {
    AccessManager public accessManager;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        // Deploy AccessManager with the deployer as the initial admin
        accessManager = new AccessManager(msg.sender);

        console.log("AccessManager deployed at:", address(accessManager));
        console.log("Initial admin:", msg.sender);

        vm.stopBroadcast();
    }
}
