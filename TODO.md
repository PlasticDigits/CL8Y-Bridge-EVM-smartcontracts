CL8Y-Bridge-EVM-smartcontracts TODO

- [x] Withdraw approvals: enforce duplicate nonce prevention (per `srcChainKey`). Added `_withdrawNonceUsed` and `NonceAlreadyApproved` error; tests updated to assert re-use reverts.
- [x] Bridge withdraw fee handling: overpayment and fee forwarded to `feeRecipient` at end of method under `nonReentrant`; emits `WithdrawExecutedWithFee` and reverts on `FeeTransferFailed`.
- [x] Router withdraw: forward full `msg.value` to bridge; no refunds. Added strict checks and aligned tests.
- [x] TokenRegistry: add getter for `destChainTokenDecimals`; on `removeTokenDestChainKey` delete decimals and address data.
- [x] Use custom errors across bridge paths: `WithdrawNotApproved`, `ApprovalCancelled`, `ApprovalExecuted`, `IncorrectFeeValue`, `NoFeeViaMsgValueWhenDeductFromAmount`, `FeeRecipientZero`, `FeeTransferFailed`, `NotCancelled`.
- [x] Tests: stop approving the bridge for ERC20 deposits; only approve downstream modules where needed in router/bridge tests.
- [x] TokenRateLimit window: fix off-by-one (`<=`) and initialize window on first use; tests updated for boundary behavior.
- [x] Enforce non-zero `feeRecipient` when `fee > 0` or any `msg.value` is sent on withdraw; added checks in approval and execution.
- [x] DepositRequest event: include `destTokenAddress`; emissions and tests updated.
- [x] Document unordered returns for getters using `EnumerableSet.values()` in `TokenRegistry`.
- [x] Tests: removed brittle direct storage writes to `_withdrawApprovals` and asserted via public flows.
- [x] Tests: fixed comments to match `restricted` usage.
- [x] Tests: use custom error selectors in expectations instead of strings where applicable.
- [x] Coverage target: verified coverage; changed contracts show ~97-100% statements and 100% funcs; entire suite green.
