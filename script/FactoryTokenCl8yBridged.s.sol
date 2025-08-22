// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {FactoryTokenCl8yBridged} from "../src/FactoryTokenCl8yBridged.sol";

contract FactoryTokenCl8yBridgedScript is Script {
    FactoryTokenCl8yBridged public factory;
    address public accessManagerAddress = address(0xeAaFB20F2b5612254F0da63cf4E0c9cac710f8aF);
    bytes32 public constant SALT = keccak256("FACTORY_TOKEN_CL8Y_BRIDGED_V1");

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        // Deploy FactoryTokenCl8yBridged deterministically with CREATE2
        factory = new FactoryTokenCl8yBridged{salt: SALT}(accessManagerAddress);

        console.log("FactoryTokenCl8yBridged deployed at:", address(factory));
        console.log("Authority set to:", accessManagerAddress);
        console.logBytes32(SALT);

        vm.stopBroadcast();
    }

    /// @notice Set the AccessManager address to use (call before run())
    function setAccessManagerAddress(address _accessManagerAddress) public {
        accessManagerAddress = _accessManagerAddress;
    }
}
