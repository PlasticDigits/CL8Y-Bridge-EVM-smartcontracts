// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {AccessManager} from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import {Cl8YBridge} from "../src/CL8YBridge.sol";
import {TokenRegistry} from "../src/TokenRegistry.sol";
import {MintBurn} from "../src/MintBurn.sol";
import {LockUnlock} from "../src/LockUnlock.sol";
import {BridgeRouter} from "../src/BridgeRouter.sol";

contract BridgeRouterScript is Script {
    AccessManager public accessManager;
    TokenRegistry public tokenRegistry;
    Cl8YBridge public bridge;
    MintBurn public mintBurn;
    LockUnlock public lockUnlock;
    BridgeRouter public router;

    address public accessManagerAddress = address(0xeAaFB20F2b5612254F0da63cf4E0c9cac710f8aF);
    address public tokenRegistryAddress = address(0);
    address public bridgeAddress = address(0);
    address public mintBurnAddress = address(0);
    address public lockUnlockAddress = address(0);
    address public wethAddress = address(0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c);

    function setUp() public {}

    // IMPORTANT: Deployer must have administrative access to the access manager
    function run() public {
        vm.startBroadcast();

        // Pull or deploy references
        accessManager =
            accessManagerAddress != address(0) ? AccessManager(accessManagerAddress) : new AccessManager(msg.sender);

        tokenRegistry = TokenRegistry(tokenRegistryAddress);
        bridge = Cl8YBridge(bridgeAddress);
        mintBurn = MintBurn(mintBurnAddress);
        lockUnlock = LockUnlock(lockUnlockAddress);

        // Deploy router
        router =
            new BridgeRouter(address(accessManager), bridge, tokenRegistry, mintBurn, lockUnlock, IWETH(wethAddress));
        console.log("BridgeRouter deployed at:", address(router));

        // Grant BRIDGE_OPERATOR_ROLE (1) to router and set function roles
        accessManager.grantRole(1, address(router), 0);
        bytes4[] memory bridgeSelectors = new bytes4[](2);
        bridgeSelectors[0] = bridge.deposit.selector;
        bridgeSelectors[1] = bridge.withdraw.selector;
        accessManager.setTargetFunctionRole(address(bridge), bridgeSelectors, 1);

        // Optionally allow router pause/unpause if desired by ops
        bytes4[] memory routerSelectors = new bytes4[](2);
        routerSelectors[0] = router.pause.selector;
        routerSelectors[1] = router.unpause.selector;
        accessManager.setTargetFunctionRole(address(router), routerSelectors, 1);

        console.log("Roles configured for BridgeRouter");

        vm.stopBroadcast();
    }
}

interface IWETH {
    function deposit() external payable;
    function withdraw(uint256) external;
}
