# Operator EVM writer invariants (GL-138)

Cross-links: [operator.md](./operator.md), [architecture.md](./architecture.md), [testing.md](./testing.md), [deployment-guide.md](./deployment-guide.md), [`skills/agent-operator-evm-writer-rpc.md`](../skills/agent-operator-evm-writer-rpc.md), GitLab issue **138**.

These rules apply to the operator **EVM writer** event poll, RPC fallback, and pending-withdrawal enumeration. They do **not** relax source-chain verification. Companion Terra history work is GitLab **139**.

## INV-OP-W1 — Fail closed on source verification

Never call `withdrawApprove` unless source-chain verification succeeds against the **configured** chain and bridge (`verify_deposit_on_source`). Unknown source chain IDs return `false` (no approval). Method-level RPC fallback must not skip chain-ID checks performed at startup (`verify_evm_rpc_chain_ids`).

## INV-OP-W2 — No cursor skip

`EventPollCursor` advances only through the last **contiguous successful** `eth_getLogs` chunk. A failed range is retried before later ranges. Partial success (chunk 1 ok, chunk 2 fail) leaves the cursor at chunk 1.

The first-poll lookback start is **sticky**. Recomputing `head - EVM_POLL_LOOKBACK_BLOCKS` after an initial-chunk failure would skip blocks and livelock at `last_polled_block == 0`.

## INV-OP-W3 — Method-level RPC fallback

Selecting an endpoint with `eth_blockNumber` is not proof that `eth_getLogs` will work. Each log chunk is attempted against remaining validated URLs (`rpc_fallback::with_endpoint_fallback` / `get_logs_with_endpoint_fallback`). The watcher and writer share this helper.

## INV-OP-W4 — Bounded negative verification retry

Unapproved destination hashes without a visible source deposit use a size- and TTL-capped retry schedule (`NegativeVerifySchedule`). A later-valid deposit is retried after TTL/backoff expiry, or immediately when a new `WithdrawSubmit` is observed. Approved, cancelled, and executed hashes are evicted. Per-cycle verify count is capped (`WRITER_MAX_VERIFY_PER_CYCLE`).

## INV-OP-W5 — Chain isolation

Each EVM writer and the Terra writer run on their **own** interval and backoff. A degraded chain must not `sleep` the shared manager. Shutdown sets a watch flag and waits at most 5s for loops to exit.

## INV-OP-W6 — Enumeration remains the safety net

Contract `getPendingWithdrawHashes` still runs each cycle (subject to per-hash backoff). Event polling is secondary. Do not remove enumeration without an equivalent durable discovery path.

## INV-OP-W7 — Jittered capped backoff

RPC and negative-retry delays use capped exponential backoff with jitter (`WRITER_BACKOFF_JITTER_BPS`) so operators restarting together do not synchronize.

## INV-OP-W8 — Validated configuration

Lookback, chunk, interval, backoff, cache size, and TTL are parsed once at startup. Zero, overflow, and out-of-range values are **rejected** (not silently clamped). Bounds:

| Variable | Default | Min | Max |
|----------|---------|-----|-----|
| `WRITER_POLL_INTERVAL_MS` | 5000 | 200 | 120000 |
| `EVM_POLL_LOOKBACK_BLOCKS` | 5000 | 1 | 100000 |
| `EVM_POLL_CHUNK_SIZE` | 5000 | 1 | 50000 |
| `WRITER_RPC_BACKOFF_INITIAL_MS` | 2000 | 100 | 60000 |
| `WRITER_RPC_BACKOFF_MAX_MS` | 60000 | 1000 | 600000 |
| `WRITER_BACKOFF_JITTER_BPS` | 1500 | 0 | 5000 |
| `WRITER_NEGATIVE_RETRY_INITIAL_MS` | 5000 | 100 | 60000 |
| `WRITER_NEGATIVE_RETRY_MAX_MS` | 300000 | 1000 | 3600000 |
| `WRITER_NEGATIVE_RETRY_TTL_SECS` | 86400 | 60 | 604800 |
| `WRITER_NEGATIVE_RETRY_CACHE_SIZE` | 10000 | 16 | 100000 |
| `WRITER_MAX_VERIFY_PER_CYCLE` | 64 | 1 | 10000 |
| `APPROVED_HASH_CACHE_SIZE` | 100000 | 16 | 2000000 |
| `PENDING_EXECUTION_CACHE_SIZE` | 50000 | 16 | 2000000 |
| `HASH_CACHE_TTL_SECS` | 86400 | 60 | 604800 |

## INV-OP-W9 — No secret leakage

Metrics and logs must not include RPC credentials, URL query tokens, private keys, database URLs, or signed payloads. RPC endpoints in logs use `sanitize_rpc_endpoint` (host + path only). Metric labels are `evm-<nativeChainId>` plus method name.

## INV-OP-W10 — Production log default is `info`

When `RUST_LOG` is unset, the operator defaults to `info` (not `cl8y_operator=debug`). Repeated no-progress verification is `debug`. Approvals and first-poll / fallback **state changes** stay at `info`.

## Code map

| Concern | Location |
|---------|----------|
| Shared log fallback | `packages/operator/src/rpc_fallback.rs` |
| Retryable RPC classification | `packages/multichain-rs/src/evm/rpc_fallback.rs` |
| Cursor | `packages/operator/src/writers/poll_cursor.rs` |
| Negative retry | `packages/operator/src/writers/negative_retry.rs` |
| Config bounds | `packages/operator/src/poll_config.rs` |
| Isolated loops | `packages/operator/src/writers/mod.rs` |
| EVM poll + enumerate | `packages/operator/src/writers/evm.rs` |
| Watcher `eth_getLogs` | `packages/operator/src/watchers/evm.rs` |
