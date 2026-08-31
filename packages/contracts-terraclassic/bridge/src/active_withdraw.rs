//! Bounded active-withdrawal index (INV-TC-AW1, GL-139).
//!
//! `PENDING_WITHDRAWS` is the canonical by-hash record, including executed and
//! cancelled history. `ACTIVE_WITHDRAW_HASHES` is a membership index over
//! non-terminal records so operator/canceler list queries have work
//! proportional to in-flight withdrawals, not lifetime history.
//!
//! Lifecycle transitions must call [`save_pending_and_sync_index`] so the
//! canonical row and the index update in the same CosmWasm transaction
//! (atomic: a later `Err` rolls both writes back).

use cosmwasm_std::{Order, StdResult, Storage};
use cw_storage_plus::Bound;

use crate::state::{
    ActiveIndexMigration, PendingWithdraw, ACTIVE_INDEX_MARKER, ACTIVE_INDEX_MIGRATION,
    ACTIVE_WITHDRAW_COUNT, ACTIVE_WITHDRAW_HASHES, PENDING_WITHDRAWS,
};

/// Default canonical rows scanned per migrate call.
pub const DEFAULT_MIGRATE_BATCH: u32 = 50;
/// Hard cap so a single migrate cannot exhaust block gas on large history.
pub const MAX_MIGRATE_BATCH: u32 = 100;
/// Extra index keys `query_active_withdrawals` may visit beyond the return
/// `limit` when skipping orphans/terminals. Caps LCD/gas griefing on a
/// polluted index; a short page with `next_start_after` set must be continued.
pub const MAX_ACTIVE_QUERY_SKIPS: u32 = 64;

/// INV-TC-AW1: a canonical record is active iff it is not executed and not cancelled.
#[inline]
pub fn is_active(pending: &PendingWithdraw) -> bool {
    !pending.executed && !pending.cancelled
}

fn load_count(storage: &dyn Storage) -> StdResult<u64> {
    Ok(ACTIVE_WITHDRAW_COUNT.may_load(storage)?.unwrap_or(0))
}

/// Insert `hash` into the active index if it is not already present.
pub fn insert_active(storage: &mut dyn Storage, hash: &[u8]) -> StdResult<()> {
    if ACTIVE_WITHDRAW_HASHES.may_load(storage, hash)?.is_some() {
        return Ok(());
    }
    ACTIVE_WITHDRAW_HASHES.save(storage, hash, &ACTIVE_INDEX_MARKER)?;
    let count = load_count(storage)?;
    ACTIVE_WITHDRAW_COUNT.save(storage, &(count + 1))?;
    Ok(())
}

/// Remove `hash` from the active index if present.
pub fn remove_active(storage: &mut dyn Storage, hash: &[u8]) -> StdResult<()> {
    if ACTIVE_WITHDRAW_HASHES.may_load(storage, hash)?.is_none() {
        return Ok(());
    }
    ACTIVE_WITHDRAW_HASHES.remove(storage, hash);
    let count = load_count(storage)?;
    ACTIVE_WITHDRAW_COUNT.save(storage, &count.saturating_sub(1))?;
    Ok(())
}

/// Align index membership with [`is_active`].
pub fn sync_active_index(
    storage: &mut dyn Storage,
    hash: &[u8],
    pending: &PendingWithdraw,
) -> StdResult<()> {
    if is_active(pending) {
        insert_active(storage, hash)
    } else {
        remove_active(storage, hash)
    }
}

/// Write the canonical record and sync the active index in one call.
pub fn save_pending_and_sync_index(
    storage: &mut dyn Storage,
    hash: &[u8; 32],
    pending: &PendingWithdraw,
) -> StdResult<()> {
    PENDING_WITHDRAWS.save(storage, hash, pending)?;
    sync_active_index(storage, hash, pending)
}

/// Initialize empty-index state for a new contract (migration already complete).
pub fn init_empty_active_index(storage: &mut dyn Storage) -> StdResult<()> {
    ACTIVE_WITHDRAW_COUNT.save(storage, &0u64)?;
    ACTIVE_INDEX_MIGRATION.save(
        storage,
        &ActiveIndexMigration {
            complete: true,
            last_key: None,
            scanned: 0,
            indexed: 0,
        },
    )?;
    Ok(())
}

/// True when `version` is a wasm that updates [`ACTIVE_WITHDRAW_HASHES`] on
/// every lifecycle write (cw2 **2.1.0+**). v2.0.x leaves the index stale, so
/// a leftover `complete=true` from a prior 2.1 install must not be trusted.
///
/// Rollback wasm to 2.0.0 then re-upgrade to 2.1.x is the HIGH from MR !18:
/// 2.0 writes only `PENDING_WITHDRAWS`, so re-upgrade must rebuild.
pub fn version_maintains_active_index(version: &str) -> bool {
    let mut parts = version.split('.');
    let major = parts
        .next()
        .and_then(|s| s.parse::<u32>().ok())
        .unwrap_or(0);
    let minor = parts
        .next()
        .and_then(|s| s.parse::<u32>().ok())
        .unwrap_or(0);
    major > 2 || (major == 2 && minor >= 1)
}

/// Reset reconstruction so the next [`migrate_active_index_batch`] scans from
/// the start. Does **not** delete canonical [`PENDING_WITHDRAWS`] rows
/// (INV-TC-AW1: no privileged wipe of replay/status evidence).
///
/// Call when migrating from a version that does not maintain the index, or
/// when the admin requests an emergency rebuild (`rebuild: true`).
pub fn reset_active_index_migration(storage: &mut dyn Storage) -> StdResult<()> {
    ACTIVE_INDEX_MIGRATION.save(
        storage,
        &ActiveIndexMigration {
            complete: false,
            last_key: None,
            scanned: 0,
            indexed: 0,
        },
    )
}

/// Reconstruct [`ACTIVE_WITHDRAW_HASHES`] from canonical records.
///
/// Scans at most `limit` rows of `PENDING_WITHDRAWS` (clamped to
/// [`MAX_MIGRATE_BATCH`]). Resume by calling again until `complete` is true.
/// Idempotent **while the wasm that maintains the index stays installed**:
/// already-indexed active hashes are left in place; terminal records are
/// **removed** from the index (cleans leftovers after a 2.0 rollback window);
/// a completed reconstruction is a no-op until [`reset_active_index_migration`].
pub fn migrate_active_index_batch(
    storage: &mut dyn Storage,
    limit: u32,
) -> StdResult<ActiveIndexMigration> {
    let mut state = ACTIVE_INDEX_MIGRATION
        .may_load(storage)?
        .unwrap_or_default();

    if state.complete {
        return Ok(state);
    }

    let limit = limit.clamp(1, MAX_MIGRATE_BATCH) as usize;
    let start = state.last_key.as_deref().map(Bound::exclusive);

    let items: Vec<(Vec<u8>, PendingWithdraw)> = PENDING_WITHDRAWS
        .range(storage, start, None, Order::Ascending)
        .take(limit)
        .collect::<StdResult<_>>()?;

    if items.is_empty() {
        state.complete = true;
        ACTIVE_INDEX_MIGRATION.save(storage, &state)?;
        return Ok(state);
    }

    let got = items.len();
    for (hash, pending) in items {
        state.scanned = state.scanned.saturating_add(1);
        // Sync both ways: insert active, remove terminal leftovers from a
        // 2.0 window that executed/cancelled while this index was frozen.
        sync_active_index(storage, &hash, &pending)?;
        if is_active(&pending) {
            state.indexed = state.indexed.saturating_add(1);
        }
        state.last_key = Some(hash);
    }

    if got < limit {
        state.complete = true;
    }
    ACTIVE_INDEX_MIGRATION.save(storage, &state)?;
    Ok(state)
}

/// Resolve the per-call migrate batch size from an optional message field.
pub fn resolve_migrate_batch_limit(requested: Option<u32>) -> u32 {
    requested
        .unwrap_or(DEFAULT_MIGRATE_BATCH)
        .clamp(1, MAX_MIGRATE_BATCH)
}

#[cfg(test)]
mod tests {
    use super::*;
    use cosmwasm_std::testing::mock_dependencies;
    use cosmwasm_std::{Addr, Coin, Uint128};

    #[test]
    fn version_gate_matches_2_1_and_later_only() {
        assert!(!version_maintains_active_index(""));
        assert!(!version_maintains_active_index("2.0.0"));
        assert!(!version_maintains_active_index("1.9.0"));
        assert!(!version_maintains_active_index("not-a-version"));
        assert!(version_maintains_active_index("2.1.0"));
        assert!(version_maintains_active_index(
            crate::state::CONTRACT_VERSION
        ));
        assert!(version_maintains_active_index("2.1.1"));
        assert!(version_maintains_active_index("2.2.0"));
        assert!(version_maintains_active_index("3.0.0"));
    }

    fn sample(nonce: u64, cancelled: bool, executed: bool) -> PendingWithdraw {
        PendingWithdraw {
            src_chain: [0, 0, 0, 2],
            src_account: [0xAB; 32],
            dest_account: [0xCD; 32],
            token: "uluna".to_string(),
            recipient: Addr::unchecked("terra1user"),
            amount: Uint128::new(1_000),
            nonce,
            src_decimals: 18,
            dest_decimals: 6,
            operator_funds: Vec::<Coin>::new(),
            submitted_at: 1,
            approved_at: if cancelled || executed { 2 } else { 0 },
            approved: cancelled || executed,
            cancelled,
            executed,
        }
    }

    fn hash(n: u8) -> [u8; 32] {
        let mut h = [0u8; 32];
        h[31] = n;
        h
    }

    fn assert_inv(storage: &dyn Storage) {
        let mut expected = 0u64;
        for item in PENDING_WITHDRAWS
            .range(storage, None, None, Order::Ascending)
            .map(|r| r.unwrap())
        {
            let (key, pending) = item;
            let in_index = ACTIVE_WITHDRAW_HASHES
                .may_load(storage, &key)
                .unwrap()
                .is_some();
            assert_eq!(
                in_index,
                is_active(&pending),
                "INV-TC-AW1 violated for hash {}",
                hex::encode(&key)
            );
            if in_index {
                expected += 1;
            }
        }
        assert_eq!(load_count(storage).unwrap(), expected);
    }

    #[test]
    fn submit_inserts_active_duplicate_hash_stays_single() {
        let mut deps = mock_dependencies();
        let h = hash(1);
        let pending = sample(1, false, false);
        save_pending_and_sync_index(&mut deps.storage, &h, &pending).unwrap();
        save_pending_and_sync_index(&mut deps.storage, &h, &pending).unwrap();
        assert_inv(&deps.storage);
        assert_eq!(load_count(&deps.storage).unwrap(), 1);
    }

    #[test]
    fn cancel_removes_uncancel_restores_execute_removes() {
        let mut deps = mock_dependencies();
        let h = hash(2);
        let mut pending = sample(2, false, false);
        save_pending_and_sync_index(&mut deps.storage, &h, &pending).unwrap();
        assert!(ACTIVE_WITHDRAW_HASHES
            .may_load(&deps.storage, &h)
            .unwrap()
            .is_some());

        pending.cancelled = true;
        save_pending_and_sync_index(&mut deps.storage, &h, &pending).unwrap();
        assert!(ACTIVE_WITHDRAW_HASHES
            .may_load(&deps.storage, &h)
            .unwrap()
            .is_none());
        assert!(
            PENDING_WITHDRAWS
                .may_load(&deps.storage, &h)
                .unwrap()
                .unwrap()
                .cancelled
        );

        pending.cancelled = false;
        save_pending_and_sync_index(&mut deps.storage, &h, &pending).unwrap();
        assert!(ACTIVE_WITHDRAW_HASHES
            .may_load(&deps.storage, &h)
            .unwrap()
            .is_some());

        pending.executed = true;
        save_pending_and_sync_index(&mut deps.storage, &h, &pending).unwrap();
        assert!(ACTIVE_WITHDRAW_HASHES
            .may_load(&deps.storage, &h)
            .unwrap()
            .is_none());
        assert!(
            PENDING_WITHDRAWS
                .may_load(&deps.storage, &h)
                .unwrap()
                .unwrap()
                .executed
        );
        assert_inv(&deps.storage);
    }

    #[test]
    fn migrate_empty_marks_complete() {
        let mut deps = mock_dependencies();
        let state = migrate_active_index_batch(&mut deps.storage, 50).unwrap();
        assert!(state.complete);
        assert_eq!(state.scanned, 0);
        assert_eq!(state.indexed, 0);
        let again = migrate_active_index_batch(&mut deps.storage, 50).unwrap();
        assert_eq!(again, state);
    }

    #[test]
    fn migrate_mixed_history_is_batched_and_idempotent() {
        let mut deps = mock_dependencies();
        // 7 canonical rows: 3 active, 2 cancelled, 2 executed
        for i in 1u8..=7 {
            let pending = match i {
                1 | 2 | 3 => sample(i as u64, false, false),
                4 | 5 => sample(i as u64, true, false),
                _ => sample(i as u64, false, true),
            };
            PENDING_WITHDRAWS
                .save(&mut deps.storage, &hash(i), &pending)
                .unwrap();
        }

        let s1 = migrate_active_index_batch(&mut deps.storage, 3).unwrap();
        assert!(!s1.complete);
        assert_eq!(s1.scanned, 3);

        let s2 = migrate_active_index_batch(&mut deps.storage, 3).unwrap();
        assert!(!s2.complete);
        assert_eq!(s2.scanned, 6);

        let s3 = migrate_active_index_batch(&mut deps.storage, 3).unwrap();
        assert!(s3.complete);
        assert_eq!(s3.scanned, 7);
        assert_eq!(s3.indexed, 3);
        assert_inv(&deps.storage);

        let s4 = migrate_active_index_batch(&mut deps.storage, 3).unwrap();
        assert_eq!(s4, s3);
        assert_inv(&deps.storage);
    }

    #[test]
    fn migrate_does_not_reinsert_terminal_or_duplicate_active() {
        let mut deps = mock_dependencies();
        let active = sample(1, false, false);
        let executed = sample(2, false, true);
        PENDING_WITHDRAWS
            .save(&mut deps.storage, &hash(1), &active)
            .unwrap();
        PENDING_WITHDRAWS
            .save(&mut deps.storage, &hash(2), &executed)
            .unwrap();
        insert_active(&mut deps.storage, &hash(1)).unwrap();

        let state = migrate_active_index_batch(&mut deps.storage, 50).unwrap();
        assert!(state.complete);
        assert_eq!(state.indexed, 1);
        assert_eq!(load_count(&deps.storage).unwrap(), 1);
        assert_inv(&deps.storage);
    }

    #[test]
    fn migrate_removes_stale_terminal_index_keys() {
        let mut deps = mock_dependencies();
        let executed = sample(2, false, true);
        PENDING_WITHDRAWS
            .save(&mut deps.storage, &hash(2), &executed)
            .unwrap();
        // Leftover from a 2.0 window that executed while the index was frozen.
        insert_active(&mut deps.storage, &hash(2)).unwrap();
        assert!(ACTIVE_WITHDRAW_HASHES
            .may_load(&deps.storage, &hash(2))
            .unwrap()
            .is_some());

        let state = migrate_active_index_batch(&mut deps.storage, 50).unwrap();
        assert!(state.complete);
        assert!(ACTIVE_WITHDRAW_HASHES
            .may_load(&deps.storage, &hash(2))
            .unwrap()
            .is_none());
        assert_eq!(load_count(&deps.storage).unwrap(), 0);
        assert_inv(&deps.storage);
    }

    #[test]
    fn reset_then_migrate_picks_up_hashes_submitted_after_stale_complete() {
        let mut deps = mock_dependencies();
        // Simulate leftover complete=true from a prior 2.1 install.
        ACTIVE_INDEX_MIGRATION
            .save(
                &mut deps.storage,
                &ActiveIndexMigration {
                    complete: true,
                    last_key: None,
                    scanned: 1,
                    indexed: 0,
                },
            )
            .unwrap();
        let pending = sample(3, false, false);
        PENDING_WITHDRAWS
            .save(&mut deps.storage, &hash(3), &pending)
            .unwrap();

        let noop = migrate_active_index_batch(&mut deps.storage, 50).unwrap();
        assert!(noop.complete);
        assert!(ACTIVE_WITHDRAW_HASHES
            .may_load(&deps.storage, &hash(3))
            .unwrap()
            .is_none());

        reset_active_index_migration(&mut deps.storage).unwrap();
        let rebuilt = migrate_active_index_batch(&mut deps.storage, 50).unwrap();
        assert!(rebuilt.complete);
        assert!(ACTIVE_WITHDRAW_HASHES
            .may_load(&deps.storage, &hash(3))
            .unwrap()
            .is_some());
        assert_inv(&deps.storage);
    }

    #[test]
    fn index_entry_without_canonical_is_detectable() {
        let mut deps = mock_dependencies();
        insert_active(&mut deps.storage, &hash(9)).unwrap();
        assert!(ACTIVE_WITHDRAW_HASHES
            .may_load(&deps.storage, &hash(9))
            .unwrap()
            .is_some());
        assert!(PENDING_WITHDRAWS
            .may_load(&deps.storage, &hash(9))
            .unwrap()
            .is_none());
    }
}
