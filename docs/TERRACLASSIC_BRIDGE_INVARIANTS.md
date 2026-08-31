# Terra Classic bridge invariants

Cross-links: [contracts-terraclassic.md](./contracts-terraclassic.md), [deployment-terraclassic-upgrade.md](./deployment-terraclassic-upgrade.md), [`packages/contracts-terraclassic/docs/OPERATIONAL_NOTES.md`](../packages/contracts-terraclassic/docs/OPERATIONAL_NOTES.md), [`skills/agent-terraclassic-active-withdrawals.md`](../skills/agent-terraclassic-active-withdrawals.md), GitLab issue **139**.

These invariants apply to `packages/contracts-terraclassic/bridge/` and to operator/canceler Terra polling. They do **not** change EVM or Solana pending-hash sets.

## INV-TC-AW1 — Canonical record vs active index (GL-139)

`PENDING_WITHDRAWS` is the **canonical** by-hash withdrawal record. `ACTIVE_WITHDRAW_HASHES` is a **membership index** of non-terminal rows.

| Rule | Behavior |
|------|----------|
| **Membership** | Hash is in `ACTIVE_WITHDRAW_HASHES` **iff** `PENDING_WITHDRAWS[hash]` exists and `!executed && !cancelled`. |
| **Submit** | Inserts the canonical row and the index key. Duplicate hash is rejected while the canonical row exists (including after execute). |
| **Approve** | Updates the canonical row; membership stays. |
| **Cancel** | Sets `cancelled`; **removes** the index key. Canonical row remains so authorized `WithdrawUncancel` can restore it. |
| **Uncancel** | Clears `cancelled`, resets `approved_at`, **reinserts** the index key. |
| **Execute** (unlock or mint) | Sets `executed`; **removes** the index key. Canonical row remains for status and replay. |
| **Nonce replay** | `(src_chain, nonce)` stays rejected via `WITHDRAW_NONCE_USED` after approval, independent of the index. |
| **Atomicity** | Canonical write and index insert/remove happen in the same execute message (`save_pending_and_sync_index`). A later `Err` rolls both back. |
| **No privileged delete** | There is no admin path that erases an actionable canonical row or its replay evidence. |
| **Fail closed** | `ActiveWithdrawals` skips index keys whose canonical row is missing or terminal (`inconsistent_skipped`). It does not panic and does not approve/execute from the index alone. Execute/approve still load the canonical row. |

| Evidence | Location |
|----------|----------|
| Index + migration state | `packages/contracts-terraclassic/bridge/src/state.rs` |
| Helpers | `packages/contracts-terraclassic/bridge/src/active_withdraw.rs` |
| Lifecycle | `packages/contracts-terraclassic/bridge/src/execute/withdraw.rs` |
| Queries | `packages/contracts-terraclassic/bridge/src/query.rs` (`ActiveWithdrawals`, `PendingWithdrawals`, `PendingWithdraw`) |
| Unit + property tests | `active_withdraw` module tests, `tests/proptest_active_withdraw.rs` |
| Integration | `tests/test_withdraw_flow.rs` (`test_active_index_*`) |

## INV-TC-AW2 — Query compatibility

| Query | Semantics | Who should use it |
|-------|-----------|-------------------|
| `pending_withdraw` | Single-hash status, including executed/cancelled/missing (`exists: false`) | Frontend transfer status, scripts, replay checks |
| `pending_withdrawals` | **All-status** historical pagination over `PENDING_WITHDRAWS`. **Unchanged** in v2.1 | Hash monitor historical discovery, audits. **Not** operator/canceler steady-state polling |
| `active_withdrawals` | Pagination over `ACTIVE_WITHDRAW_HASHES` only. Errors if migrate reconstruction is incomplete | Operator, canceler, execution watchers |
| `active_withdraw_index` | `active_count` + migration progress | Ops, health, migrate loops |

Do **not** silently change `pending_withdrawals` to filter terminal rows. That would break clients that enumerate history.

## INV-TC-AW3 — Bounded, resumable migrate

v2.0.0 → v2.1.0 reconstructs `ACTIVE_WITHDRAW_HASHES` from `PENDING_WITHDRAWS`.

| Rule | Behavior |
|------|----------|
| **Batch** | Each `migrate` scans at most 100 canonical rows (default 50). Repeat until attribute `active_index_complete=true`. |
| **Idempotent** | A completed migrate is a no-op. Resume continues from `last_key`. Re-insert of an already-indexed active hash does not double-count. |
| **Instantiate** | New contracts mark migration complete with an empty index. |
| **Incomplete index** | `active_withdrawals` errors so operator/canceler **fall back** to `pending_withdrawals` (watchtower must not miss approved rows). |
| **Rollback** | Rolling the wasm back to v2.0.0 leaves the extra maps unused; `pending_withdrawals` still works. New binaries on old code must keep the legacy fallback. |

`MigrateMsg` remains `{}`-compatible. Optional `active_index_batch_limit` overrides the per-call scan size.

## INV-TC-AW4 — Operator / canceler polling

| Rule | Behavior |
|------|----------|
| **Prefer active** | Query `active_withdrawals` first. |
| **Fallback** | On unknown variant, LCD error, missing `withdrawals` array, or incomplete migrate, use `pending_withdrawals` for that cycle. |
| **Canceler filter** | Only **approved && !cancelled && !executed** rows are cancel candidates. Unapproved active rows are skipped. |
| **Operator filter** | Only **unapproved && !cancelled && !executed** rows are approval candidates. |
| **Logs** | Cycle summaries and metrics; no per-entry debug for terminal history. |
| **Metrics** | `relayer_terra_withdraw_query_mode`, `relayer_terra_active_withdrawals_polled`, `relayer_terra_inconsistent_skipped_total`; canceler `canceler_terra_withdraw_query_mode`, `canceler_terra_inconsistent_skipped`. No RPC credentials or addresses in metric labels. |

Unapproved spam can still grow the **active** set; that is bounded operator-retry work tracked separately in GitLab **138**, not by deleting canonical rows.

## Frontend

Transfer-status hash discovery in `hashMonitor.ts` keeps `pending_withdrawals` so executed/cancelled hashes remain listed (bounded by page cap). Per-hash status uses `pending_withdraw`. See [FRONTEND_BRIDGE_INVARIANTS.md](./FRONTEND_BRIDGE_INVARIANTS.md) **INV-FE-TC-AW1**.
