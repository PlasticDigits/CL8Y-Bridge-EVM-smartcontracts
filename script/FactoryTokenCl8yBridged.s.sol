// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {FactoryTokenCl8yBridged} from "../src/FactoryTokenCl8yBridged.sol";
import {AccessManager} from "@openzeppelin/contracts/access/manager/AccessManager.sol";

contract FactoryTokenCl8yBridgedScript is Script {
    FactoryTokenCl8yBridged public factory;

    // You can set this to a specific AccessManager address if you want to use an existing one
    // If left as address(0), it will deploy a new AccessManager
    address public accessManagerAddress = address(0xeAaFB20F2b5612254F0da63cf4E0c9cac710f8aF);

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        address authority;

        // If no AccessManager address is provided, deploy a new one
        if (accessManagerAddress == address(0)) {
            AccessManager accessManager = new AccessManager(msg.sender);
            authority = address(accessManager);
            console.log("New AccessManager deployed at:", authority);
            console.log("AccessManager admin:", msg.sender);
        } else {
            authority = accessManagerAddress;
            console.log("Using existing AccessManager at:", authority);
        }

        // Deploy FactoryTokenCl8yBridged with the authority
        factory = new FactoryTokenCl8yBridged(authority);

        console.log("FactoryTokenCl8yBridged deployed at:", address(factory));
        console.log("Authority set to:", authority);

        vm.stopBroadcast();
    }

    /// @notice Set the AccessManager address to use (call before run())
    function setAccessManagerAddress(address _accessManagerAddress) public {
        accessManagerAddress = _accessManagerAddress;
    }
}
