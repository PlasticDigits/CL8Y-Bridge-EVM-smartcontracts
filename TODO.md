## CL8Y Bridge: Router + Restricted Deposit Migration

- [x] Add missing NatSpec docs to `src/CL8YBridge.sol`

  - [x] Ensure file header describes purpose, trust/authority model, and pause semantics
  - [x] Constructor params and visibility
  - [x] `deposit(address payer, bytes32 destChainKey, bytes32 destAccount, address token, uint256 amount)` full docs including `restricted` requirement and role expectations
  - [x] `withdraw(bytes32 srcChainKey, address token, address to, uint256 amount, uint256 nonce)` updates
  - [x] `pause()` and `unpause()` docs and access requirements
  - [x] Getter/view helpers (`get*Hashes`, `get*FromHash`) docs
  - [x] Events and errors reviewed for completeness

- [x] Introduce `BridgeRouter`

  - [x] Create `src/BridgeRouter.sol`
  - [x] Constructor: store `Cl8YBridge`, `TokenRegistry`, `MintBurn`, `LockUnlock`, and `wrappedNative` (IWETH-like)
  - [x] Access control: router functions are public, router has permission to call restricted `Cl8YBridge` methods
  - [x] Deposit (ERC20): `deposit(address token, uint256 amount, bytes32 destChainKey, bytes32 destAccount)`
    - [x] Calls `bridge.deposit(msg.sender, destChainKey, destAccount, token, amount)`
    - [x] Note: user must approve `MintBurn` or `LockUnlock` depending on bridge type
  - [x] Deposit (native): `depositNative(bytes32 destChainKey, bytes32 destAccount)` payable
    - [x] Wrap `msg.value` into `wrappedNative`
    - [x] Call `bridge.deposit(address(this), destChainKey, destAccount, wrappedNative, msg.value)`
    - [x] Manage approvals to `LockUnlock` for router-held funds
  - [x] Withdraw (ERC20): `withdraw(bytes32 srcChainKey, address token, address to, uint256 amount, uint256 nonce)`
    - [x] Simply proxies to `bridge.withdraw`
  - [x] Withdraw (native): `withdrawNative(bytes32 srcChainKey, uint256 amount, uint256 nonce, address payable to)`
    - [x] Calls `bridge.withdraw(srcChainKey, wrappedNative, address(this), amount, nonce)`
    - [x] Unwrap and forward ETH to `to`
  - [x] Reentrancy guard where applicable
  - [x] Events for native unwrap failures (if any) and deposits
  - [x] Minimal IWETH interface in `src/interfaces/IWETH.sol`

- [x] Update tests for `Cl8YBridge`

  - [x] Adjust to new restricted `deposit` signature (requires role and `payer` param)
  - [x] Update approvals to target `MintBurn`/`LockUnlock` contracts (not the bridge)
  - [x] Add pause tests: deposit and withdraw revert when paused; succeed when unpaused
  - [x] Keep existing security and hashing tests passing with signature updates

- [x] Write tests for `BridgeRouter`

  - [x] Setup: grant router role to call `bridge.deposit`/`withdraw`
  - [x] ERC20 deposit via router: burns/locks on behalf of `msg.sender`
  - [x] Native deposit via router: wraps and deposits
  - [x] ERC20/native withdraw tests (proxy and unwrap)
  - [x] Pausing: router calls should revert if router is paused
  - [x] Reentrancy checks on router paths (router is nonReentrant)

- [ ] Scripts
  - [ ] Add deployment script for `BridgeRouter` and grant roles
  - [ ] Update README with new call patterns and approval requirements

### Implementation Notes / Open Questions

There are a few integration nuances around native token handling and allowances:

- Deposit allowances: Because `Cl8YBridge.deposit` delegates to `MintBurn.burn(from, token, amount)` or `LockUnlock.lock(from, token, amount)`, the required allowance must be granted to `MintBurn` or `LockUnlock` respectively, not to the bridge/router. Router docs and tests will reflect this. Alternative is adding permit flows or an approval-helper, which is out of scope unless requested.

- Native deposit/withdraw: The router will use a configured `wrappedNative` token (IWETH-like). For native deposits the router becomes the payer for the locked path when wrapping (payer = router). This means the `Deposit.from` in bridge storage will reflect the router instead of the end user for native deposits. If preserving the end-user in `Deposit.from` is critical, options are: (a) add permit-style approvals to `LockUnlock` so `from` can remain the user after wrapping to their address; (b) extend bridge to support a native path that doesn’t rely on ERC20 allowances. Please advise if you prefer either approach.
