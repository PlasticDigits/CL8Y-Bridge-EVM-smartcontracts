// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {AccessManager} from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import {Cl8YBridge} from "../src/CL8YBridge.sol";
import {TokenRegistry} from "../src/TokenRegistry.sol";
import {ChainRegistry} from "../src/ChainRegistry.sol";
import {MintBurn} from "../src/MintBurn.sol";
import {LockUnlock} from "../src/LockUnlock.sol";
import {BridgeRouter} from "../src/BridgeRouter.sol";
import {IWETH} from "../src/interfaces/IWETH.sol";
import {GuardBridge} from "../src/GuardBridge.sol";
import {DatastoreSetAddress} from "../src/DatastoreSetAddress.sol";
import {BlacklistBasic} from "../src/BlacklistBasic.sol";
import {TokenRateLimit} from "../src/TokenRateLimit.sol";

contract BridgeRouterScript is Script {
    AccessManager public accessManager;
    ChainRegistry public chainRegistry;
    TokenRegistry public tokenRegistry;
    Cl8YBridge public bridge;
    MintBurn public mintBurn;
    LockUnlock public lockUnlock;
    BridgeRouter public router;
    GuardBridge public guard;
    DatastoreSetAddress public datastore;
    BlacklistBasic public blacklist;
    TokenRateLimit public tokenRateLimit;

    address public accessManagerAddress = address(0xeAaFB20F2b5612254F0da63cf4E0c9cac710f8aF);
    address public tokenRegistryAddress = address(0);
    address public chainRegistryAddress = address(0);
    address public bridgeAddress = address(0);
    address public mintBurnAddress = address(0);
    address public lockUnlockAddress = address(0);
    address public wethAddress = address(0);

    function setUp() public {}

    // IMPORTANT: Deployer must have administrative access to the access manager
    function run() public {
        vm.startBroadcast();

        // Pull or deploy references (AccessManager is expected to be provided)
        accessManager =
            accessManagerAddress != address(0) ? AccessManager(accessManagerAddress) : new AccessManager(msg.sender);

        // Verify deployer has ADMIN role on AccessManager; otherwise revert early
        {
            (bool isAdmin,) = accessManager.hasRole(accessManager.ADMIN_ROLE(), msg.sender);
            console.log("AccessManager:", address(accessManager));
            console.log("Deployer:", msg.sender);
            if (!isAdmin) {
                console.log("ERROR: Deployer does not have ADMIN_ROLE on AccessManager.");
                vm.stopBroadcast();
                revert("deployer_not_accessmanager_admin");
            }
        }

        // Optionally attach existing registry/bridge components if provided, otherwise deploy
        chainRegistry =
            chainRegistryAddress != address(0) ? ChainRegistry(chainRegistryAddress) : ChainRegistry(address(0));
        tokenRegistry =
            tokenRegistryAddress != address(0) ? TokenRegistry(tokenRegistryAddress) : TokenRegistry(address(0));
        bridge = bridgeAddress != address(0) ? Cl8YBridge(bridgeAddress) : Cl8YBridge(address(0));
        mintBurn = mintBurnAddress != address(0) ? MintBurn(mintBurnAddress) : MintBurn(address(0));
        lockUnlock = lockUnlockAddress != address(0) ? LockUnlock(lockUnlockAddress) : LockUnlock(address(0));

        // Deploy chain/token registries if needed
        if (address(chainRegistry) == address(0)) {
            chainRegistry = new ChainRegistry(address(accessManager));
            console.log("ChainRegistry deployed at:", address(chainRegistry));
        }
        if (address(tokenRegistry) == address(0)) {
            tokenRegistry = new TokenRegistry(address(accessManager), chainRegistry);
            console.log("TokenRegistry deployed at:", address(tokenRegistry));
        }

        // Deploy MintBurn/LockUnlock if needed
        if (address(mintBurn) == address(0)) {
            mintBurn = new MintBurn(address(accessManager));
            console.log("MintBurn deployed at:", address(mintBurn));
        }
        if (address(lockUnlock) == address(0)) {
            lockUnlock = new LockUnlock(address(accessManager));
            console.log("LockUnlock deployed at:", address(lockUnlock));
        }

        // Deploy bridge if needed
        if (address(bridge) == address(0)) {
            bridge = new Cl8YBridge(address(accessManager), tokenRegistry, mintBurn, lockUnlock);
            console.log("Cl8YBridge deployed at:", address(bridge));
        }
        // Deploy datastore and guard
        datastore = new DatastoreSetAddress();
        guard = new GuardBridge(address(accessManager), datastore);
        console.log("DatastoreSetAddress deployed at:", address(datastore));
        console.log("GuardBridge deployed at:", address(guard));

        // Deploy blacklist and token rate limit guard modules
        blacklist = new BlacklistBasic(address(accessManager));
        tokenRateLimit = new TokenRateLimit(address(accessManager));
        console.log("BlacklistBasic deployed at:", address(blacklist));
        console.log("TokenRateLimit deployed at:", address(tokenRateLimit));

        // Resolve WETH from env if not set (WETH_ADDRESS)
        if (wethAddress == address(0)) {
            // Try to resolve from env; if not present, this may revert. We'll still validate below.
            string memory envWeth = vm.envString("WETH_ADDRESS");
            wethAddress = vm.parseAddress(envWeth);
        }
        if (wethAddress == address(0)) {
            console.log("ERROR: WETH address is zero. Set WETH_ADDRESS env var for this chain.");
            vm.stopBroadcast();
            revert("missing_weth_address");
        }

        // Deploy router
        router = new BridgeRouter(
            address(accessManager), bridge, tokenRegistry, mintBurn, lockUnlock, IWETH(wethAddress), guard
        );
        console.log("BridgeRouter deployed at:", address(router));

        // NOTE: Ensure deployer has admin permission on AccessManager.
        // Grant role 1 to deployer (for initial configuration), and to contracts that need to call restricted functions
        accessManager.grantRole(1, msg.sender, 0);
        accessManager.grantRole(1, address(router), 0);
        accessManager.grantRole(1, address(bridge), 0);
        accessManager.grantRole(1, address(mintBurn), 0);
        accessManager.grantRole(1, address(lockUnlock), 0);

        // Configure function roles on core contracts
        {
            // Bridge restricted functions
            bytes4[] memory sel = new bytes4[](7);
            sel[0] = bridge.deposit.selector;
            sel[1] = bridge.withdraw.selector;
            sel[2] = bridge.pause.selector;
            sel[3] = bridge.unpause.selector;
            sel[4] = bridge.approveWithdraw.selector;
            sel[5] = bridge.cancelWithdrawApproval.selector;
            sel[6] = bridge.reenableWithdrawApproval.selector;
            accessManager.setTargetFunctionRole(address(bridge), sel, 1);
        }
        {
            // Router restricted functions (pause/unpause)
            bytes4[] memory sel = new bytes4[](2);
            sel[0] = router.pause.selector;
            sel[1] = router.unpause.selector;
            accessManager.setTargetFunctionRole(address(router), sel, 1);
        }
        {
            // MintBurn restricted functions
            bytes4[] memory sel = new bytes4[](2);
            sel[0] = mintBurn.mint.selector;
            sel[1] = mintBurn.burn.selector;
            accessManager.setTargetFunctionRole(address(mintBurn), sel, 1);
        }
        {
            // LockUnlock restricted functions
            bytes4[] memory sel = new bytes4[](2);
            sel[0] = lockUnlock.lock.selector;
            sel[1] = lockUnlock.unlock.selector;
            accessManager.setTargetFunctionRole(address(lockUnlock), sel, 1);
        }
        {
            // ChainRegistry admin functions
            bytes4[] memory sel = new bytes4[](6);
            sel[0] = chainRegistry.addEVMChainKey.selector;
            sel[1] = chainRegistry.addCOSMWChainKey.selector;
            sel[2] = chainRegistry.addSOLChainKey.selector;
            sel[3] = chainRegistry.addOtherChainType.selector;
            sel[4] = chainRegistry.addChainKey.selector;
            sel[5] = chainRegistry.removeChainKey.selector;
            accessManager.setTargetFunctionRole(address(chainRegistry), sel, 1);
        }
        {
            // TokenRegistry admin functions (simplified)
            bytes4[] memory sel = new bytes4[](3);
            sel[0] = tokenRegistry.addToken.selector;
            sel[1] = tokenRegistry.addTokenDestChainKey.selector;
            sel[2] = tokenRegistry.setTokenBridgeType.selector;
            accessManager.setTargetFunctionRole(address(tokenRegistry), sel, 1);
        }
        {
            // GuardBridge management functions
            bytes4[] memory sel = new bytes4[](7);
            sel[0] = guard.addGuardModuleAccount.selector;
            sel[1] = guard.addGuardModuleDeposit.selector;
            sel[2] = guard.addGuardModuleWithdraw.selector;
            sel[3] = guard.removeGuardModuleAccount.selector;
            sel[4] = guard.removeGuardModuleDeposit.selector;
            sel[5] = guard.removeGuardModuleWithdraw.selector;
            sel[6] = guard.execute.selector;
            accessManager.setTargetFunctionRole(address(guard), sel, 1);
        }
        {
            // Blacklist admin functions
            bytes4[] memory sel = new bytes4[](2);
            sel[0] = blacklist.setIsBlacklistedToTrue.selector;
            sel[1] = blacklist.setIsBlacklistedToFalse.selector;
            accessManager.setTargetFunctionRole(address(blacklist), sel, 1);
        }
        {
            // Rate limit admin functions
            bytes4[] memory sel = new bytes4[](3);
            sel[0] = tokenRateLimit.setDepositLimit.selector;
            sel[1] = tokenRateLimit.setWithdrawLimit.selector;
            sel[2] = tokenRateLimit.setLimitsBatch.selector;
            accessManager.setTargetFunctionRole(address(tokenRateLimit), sel, 1);
        }

        // Register guard modules
        guard.addGuardModuleAccount(address(blacklist));
        guard.addGuardModuleDeposit(address(tokenRateLimit));
        guard.addGuardModuleWithdraw(address(tokenRateLimit));

        console.log("Roles and guard modules configured");

        vm.stopBroadcast();
    }
}

// IWETH imported from ../src/interfaces/IWETH.sol
