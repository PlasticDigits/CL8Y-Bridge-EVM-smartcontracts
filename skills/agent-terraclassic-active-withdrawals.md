# Skill: Terra Classic active withdrawals (agents / automation)

When changing Terra Classic withdrawal storage, list queries, migrate, operator Terra polling, or canceler Terra polling, preserve **INV-TC-AW1–AW4** in [`docs/TERRACLASSIC_BRIDGE_INVARIANTS.md`](../docs/TERRACLASSIC_BRIDGE_INVARIANTS.md) (GitLab **139**).

## Do not regress

1. **Canonical history stays** — Never delete `PENDING_WITHDRAWS` rows on execute or cancel. Replay, single-hash status, and `WithdrawUncancel` depend on them.
2. **Active index is membership-only** — `ACTIVE_WITHDRAW_HASHES` contains a hash **iff** the canonical row exists and `!executed && !cancelled`. Update both in the same execute via `save_pending_and_sync_index`.
3. **Do not silently filter `pending_withdrawals`** — That query remains all-status. Add or use `active_withdrawals` for operator/canceler work.
4. **Do not scan `PENDING_WITHDRAWS` to implement `active_withdrawals`** — Range the index. Skip orphan/terminal index keys (`inconsistent_skipped`); do not panic.
5. **Migrate is batched** — Reconstruction must be resumable (`active_index_batch_limit`, default 50, max 100). Repeat migrate until `active_index_complete=true`. Incomplete index → `active_withdrawals` errors → clients fall back to `pending_withdrawals`.
6. **No privileged wipe** — Do not add an admin “delete pending withdrawals” path.
7. **Frontend status** — Hash monitor historical listing stays on `pending_withdrawals`; per-hash status stays on `pending_withdraw`. Do not switch the monitor to `active_withdrawals` or completed transfers vanish (**INV-FE-TC-AW1**).
8. **Operator/canceler** — Prefer `active_withdrawals`, keep a legacy fallback, log cycle summaries not per-terminal-entry debug.

## Where it lives

- Index + invariant: `packages/contracts-terraclassic/bridge/src/state.rs`, `active_withdraw.rs`
- Lifecycle: `packages/contracts-terraclassic/bridge/src/execute/withdraw.rs`
- Queries: `packages/contracts-terraclassic/bridge/src/query.rs`, `msg.rs`
- Migrate: `packages/contracts-terraclassic/bridge/src/contract.rs`
- Operator: `packages/operator/src/writers/terra.rs`
- Canceler: `packages/canceler/src/watcher.rs`
- Client types: `packages/multichain-rs/src/terra/contracts.rs`
- Tests: `tests/test_withdraw_flow.rs` (`test_active_index_*`), `tests/proptest_active_withdraw.rs`

## Related docs

- [`docs/TERRACLASSIC_BRIDGE_INVARIANTS.md`](../docs/TERRACLASSIC_BRIDGE_INVARIANTS.md)
- [`docs/contracts-terraclassic.md`](../docs/contracts-terraclassic.md)
- [`docs/deployment-terraclassic-upgrade.md`](../docs/deployment-terraclassic-upgrade.md) (v2.1 migrate loop)
- [`docs/FRONTEND_BRIDGE_INVARIANTS.md`](../docs/FRONTEND_BRIDGE_INVARIANTS.md) (**INV-FE-TC-AW1**)
- Companion operator RPC livelock: GitLab **138** (not this skill)

## Tracking issues

- GitLab **139** — stop pending-withdrawal polling from scaling with terminal history.
