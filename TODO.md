### Goal

Introduce an approval-based withdrawal flow with operator-quoted fees. The operator pre-approves a withdrawal in `CL8YBridge` with a fee and recipient, then anyone can complete the withdrawal via the router. Fees are handled differently for ERC20 and native withdrawals.

### High-level changes

- Add withdrawal approvals to `CL8YBridge` keyed by the existing withdraw hash.
- Add `approveWithdraw` (restricted) with fee and feeRecipient, and a `deductFromAmount` flag for native path.
- Add `cancelWithdrawApproval` (restricted).
- Enforce approval existence/consumption in `CL8YBridge.withdraw` (defense-in-depth). Mark executed before any external calls.
- Make `CL8YBridge.withdraw` payable to support native fee payment for ERC20 withdrawals. Enforce `msg.value` range when fee is paid.
- Keep router entrypoints public (unrestricted) and payable where needed. Router reads the approval for fee/recipient.
  - ERC20 withdraw: Router validates `msg.value >= fee` and `< 2x` fee, refunds any excess to the caller, then forwards exactly `fee` to `CL8YBridge.withdraw` as `msg.value`.
  - Native withdraw: Operator approves using the wrapped native token (e.g., WETH) with `deductFromAmount = true`. Router calls bridge to mint/unlock WETH to itself, unwraps, and splits: sends `fee` to `feeRecipient` and `amount - fee` to the user. No `msg.value` required.

### Invariants and rules (from user requirements)

- Fee currency is always native.
- For ERC20 withdraws:
  - `msg.value` should be at least the approved fee.
  - Block overpayments that are 2x or more the fee.
  - Excess over the exact fee (but < 2x) is refunded to the caller by the router before calling the bridge.
  - Bridge re-checks the range defensively.
- For native withdraws:
  - Approvals are created on the wrapped native token (WETH or chain equivalent).
  - No `msg.value` is required; fee is deducted from the withdrawal proceeds on the router after unwrapping.
- Anyone can pay the fee and complete the withdrawal.
- Approvals have no expiry.
- Approvals are cancellable by the bridge operator prior to execution.
- Checks for approval/execution must be enforced in `CL8YBridge` (router doesn’t need to trust itself).
- Zero-fee is allowed.
- All functions obey pause state.
- Events are emitted: `WithdrawApproved`, `WithdrawApprovalCancelled`, and `WithdrawExecutedWithFee` (or equivalent), in addition to the existing `WithdrawRequest`.

### API changes

- `CL8YBridge.sol`

  - New struct `WithdrawApproval { uint256 fee; address feeRecipient; bool deductFromAmount; bool cancelled; bool executed; }`
  - `approveWithdraw(bytes32 srcChainKey, address token, address to, uint256 amount, uint256 nonce, uint256 fee, address feeRecipient, bool deductFromAmount)` restricted whenNotPaused
  - `cancelWithdrawApproval(bytes32 srcChainKey, address token, address to, uint256 amount, uint256 nonce)` restricted whenNotPaused
  - `getWithdrawApproval(bytes32 withdrawHash) public view returns (WithdrawApproval memory)`
  - `withdraw(...)` becomes `payable`, enforces approval existence and fee behavior, and marks executed before external interactions
  - New errors for approval/fee validation; new events for approval lifecycle and execution with fee

- `BridgeRouter.sol`
  - `withdraw` becomes `payable` and is public (unrestricted)
  - `withdrawNative` remains public (unrestricted); no `payable` needed but acceptable
  - Router reads approval from bridge to:
    - Validate fee range and refund any overage for ERC20 withdraws, then forward exactly `fee` to the bridge
    - For native withdraws, unwrap and split to `feeRecipient` and `to`
  - Reuse existing errors where possible; add a specific error if needed (e.g., `RefundFailed`, `FeeExceedsAmount`)

### Step-by-step implementation

1. Add approval storage and lifecycle to `CL8YBridge`:

   - Mapping from `withdrawHash` to `WithdrawApproval`
   - `approveWithdraw` and `cancelWithdrawApproval`
   - Events: `WithdrawApproved`, `WithdrawApprovalCancelled`
   - View accessor: `getWithdrawApproval`

2. Make `CL8YBridge.withdraw` payable and enforce:

   - Verify token/chain validations and accumulator like today
   - Compute `withdrawHash` and load approval
   - Require approval exists, not cancelled, not executed
   - If `deductFromAmount == false` (ERC20 path):
     - If `fee == 0`: require `msg.value == 0`
     - Else: require `msg.value >= fee` and `msg.value < fee * 2`
     - Forward exactly `fee` to `feeRecipient`
     - If `msg.value > fee`, refund the difference to `msg.sender`
   - If `deductFromAmount == true` (native path): require `msg.value == 0`
   - Mark executed before external calls
   - Perform mint/unlock as before; emit `WithdrawRequest`
   - Emit `WithdrawExecutedWithFee(withdrawHash, fee, feeRecipient, deductFromAmount)`

3. Update `BridgeRouter`:

   - Make `withdraw` payable and public (remove `restricted`)
   - For ERC20:
     - Compute `withdrawHash`, read approval
     - Require `deductFromAmount == false`
     - Enforce range: `msg.value >= fee` and `< 2x`
     - If `msg.value > fee`, refund the difference to the caller
     - Call `bridge.withdraw{value: fee}`
   - For native path (`withdrawNative`):
     - Call `bridge.withdraw` to mint/unlock wrapped native to router (no value)
     - Read approval again
     - Unwrap full `amount`; send `fee` to `feeRecipient` and `amount - fee` to `to`
     - Require `fee <= amount`
     - Emit existing `WithdrawNative`

4. Tests

   - Update `BridgeRouter.t.sol`:
     - New tests:
       - ERC20: approve + withdraw with exact fee; assert feeRecipient receives fee and tokens delivered
       - ERC20: overpay < 2x; refund difference and forward exact fee
       - ERC20: overpay >= 2x; revert
       - Zero-fee path (ERC20): allow msg.value = 0
       - Native: approve on wrapped token with `deductFromAmount = true`; withdrawNative; assert fee split and unwrap
       - Cancel: cancel approval; ensure withdraw reverts
     - Keep pause tests valid; ensure `approveWithdraw` and `withdraw` obey pause

5. Run `forge test` and fix any issues; if failures recur, re-run with `-vvvvv` for diagnostics.

### Notes

- Approvals keyed by the same `withdrawHash` as existing `Withdraw` struct.
- Router relies on bridge’s `getWithdrawApproval` for fee data; approval check is enforced in bridge.
- For native withdrawals, approvals must target `to = router`, as the router unwraps and forwards.
- Defense-in-depth: both router and bridge validate fee ranges for ERC20 path; only bridge enforces approval lifecycle.
