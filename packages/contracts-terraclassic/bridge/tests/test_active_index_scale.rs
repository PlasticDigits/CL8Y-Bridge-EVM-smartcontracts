//! Scale, pagination-cap, and migrate-batch evidence for GL-139.
//!
//! Production LCD snapshot (columbus-5, 2026-09-01, publicnode):
//! `terra18m02l2f43c2dagqnz3kfccpgz9pzzz5hk9l5mh5wvr6dcvv47zfqdfs7la`
//! still on code_id 10971 (v2.0 — `active_withdraw_index` unknown).
//! `pending_withdrawals` had **106** canonical rows: 95 executed, 11 approved
//! and not executed, 0 cancelled, 0 unapproved.
//!
//! These tests reconstruct that mix (and a 2000-terminal stress mix) in mock
//! storage so migrate batch counts and active-query work stay bounded without
//! a live wasm migrate broadcast.

use bridge::active_withdraw::{
    init_empty_active_index, migrate_active_index_batch, save_pending_and_sync_index,
    DEFAULT_MIGRATE_BATCH, MAX_MIGRATE_BATCH, WITHDRAW_LIST_MAX_LIMIT,
};
use bridge::contract::query;
use bridge::msg::{ActiveWithdrawalsResponse, PendingWithdrawalsResponse, QueryMsg};
use bridge::state::{PendingWithdraw, PENDING_WITHDRAWS, WITHDRAW_DELAY};
use cosmwasm_std::testing::{mock_dependencies, mock_env};
use cosmwasm_std::{from_json, to_json_vec, Addr, Binary, Order, Uint128};

/// LCD snapshot used as the "realistic PENDING_WITHDRAWS size" in issue 139.
const PROD_EXECUTED: u16 = 95;
const PROD_ACTIVE: u16 = 11;
const PROD_TOTAL: u16 = PROD_EXECUTED + PROD_ACTIVE;
const STRESS_TERMINAL: u16 = 2000;

fn sample(nonce: u64, cancelled: bool, executed: bool, approved: bool) -> PendingWithdraw {
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
        operator_funds: vec![],
        submitted_at: 1,
        approved_at: if approved { 2 } else { 0 },
        approved,
        cancelled,
        executed,
    }
}

fn hash_n(n: u16) -> [u8; 32] {
    let mut h = [0u8; 32];
    h[30] = (n >> 8) as u8;
    h[31] = n as u8;
    h
}

fn seed_prod_mix(storage: &mut dyn cosmwasm_std::Storage) {
    for i in 0..PROD_EXECUTED {
        PENDING_WITHDRAWS
            .save(storage, &hash_n(i), &sample(i as u64, false, true, true))
            .unwrap();
    }
    for i in 0..PROD_ACTIVE {
        PENDING_WITHDRAWS
            .save(
                storage,
                &hash_n(PROD_EXECUTED + i),
                &sample((PROD_EXECUTED + i) as u64, false, false, true),
            )
            .unwrap();
    }
}

fn query_active_page(
    deps: cosmwasm_std::Deps,
    start_after: Option<Binary>,
    limit: Option<u32>,
) -> ActiveWithdrawalsResponse {
    from_json(
        query(
            deps,
            mock_env(),
            QueryMsg::ActiveWithdrawals { start_after, limit },
        )
        .unwrap(),
    )
    .unwrap()
}

fn query_pending_page(
    deps: cosmwasm_std::Deps,
    start_after: Option<Binary>,
    limit: Option<u32>,
) -> PendingWithdrawalsResponse {
    from_json(
        query(
            deps,
            mock_env(),
            QueryMsg::PendingWithdrawals { start_after, limit },
        )
        .unwrap(),
    )
    .unwrap()
}

#[test]
fn production_sized_migrate_completes_in_bounded_batches() {
    let mut deps = mock_dependencies();
    seed_prod_mix(&mut deps.storage);

    let mut calls = 0u32;
    loop {
        calls += 1;
        let state = migrate_active_index_batch(&mut deps.storage, DEFAULT_MIGRATE_BATCH).unwrap();
        assert!(
            calls <= (PROD_TOTAL as u32).div_ceil(DEFAULT_MIGRATE_BATCH) + 1,
            "migrate must not scan more than one extra empty batch"
        );
        if state.complete {
            assert_eq!(state.scanned, PROD_TOTAL as u64);
            assert_eq!(state.indexed, PROD_ACTIVE as u64);
            break;
        }
    }
    assert_eq!(calls, 3, "106 rows / batch 50 → 3 migrate calls");

    // Rebuild with max batch: 106 / 100 = 2 calls.
    let mut deps = mock_dependencies();
    seed_prod_mix(&mut deps.storage);
    let first = migrate_active_index_batch(&mut deps.storage, MAX_MIGRATE_BATCH).unwrap();
    assert!(!first.complete);
    assert_eq!(first.scanned, MAX_MIGRATE_BATCH as u64);
    let second = migrate_active_index_batch(&mut deps.storage, MAX_MIGRATE_BATCH).unwrap();
    assert!(second.complete);
    assert_eq!(second.scanned, PROD_TOTAL as u64);
    assert_eq!(second.indexed, PROD_ACTIVE as u64);
}

#[test]
fn production_row_json_size_bounds_per_batch_storage_work() {
    let row = sample(1, false, true, true);
    let bytes = to_json_vec(&row).unwrap().len();
    // Canonical row is a few hundred bytes; 100 * that stays far below typical
    // columbus-5 wasm tx budgets (live execute sample 2026-09-01: ~158–257k
    // gas_used with 500k gas_wanted). This is storage-size evidence for
    // MAX_MIGRATE_BATCH=100, not a substitute for the eventual on-chain
    // migrate tx gas_used.
    assert!(
        bytes < 1024,
        "PendingWithdraw JSON {bytes} bytes — update gas notes if the record grew"
    );
    let worst_batch_bytes = bytes.saturating_mul(MAX_MIGRATE_BATCH as usize);
    assert!(
        worst_batch_bytes < 128 * 1024,
        "100-row migrate payload bound {worst_batch_bytes} bytes"
    );
}

#[test]
fn active_query_work_does_not_grow_with_terminal_history() {
    let mut deps = mock_dependencies();
    WITHDRAW_DELAY.save(&mut deps.storage, &300u64).unwrap();
    init_empty_active_index(&mut deps.storage).unwrap();

    for i in 0..STRESS_TERMINAL {
        let h = hash_n(i);
        save_pending_and_sync_index(&mut deps.storage, &h, &sample(i as u64, false, true, true))
            .unwrap();
    }
    for i in 0..PROD_ACTIVE {
        let n = STRESS_TERMINAL + i;
        save_pending_and_sync_index(
            &mut deps.storage,
            &hash_n(n),
            &sample(n as u64, false, false, true),
        )
        .unwrap();
    }

    let canonical: usize = PENDING_WITHDRAWS
        .range(&deps.storage, None, None, Order::Ascending)
        .count();
    assert_eq!(canonical, (STRESS_TERMINAL + PROD_ACTIVE) as usize);

    let active = query_active_page(deps.as_ref(), None, Some(WITHDRAW_LIST_MAX_LIMIT));
    assert_eq!(active.withdrawals.len(), PROD_ACTIVE as usize);
    assert!(active.next_start_after.is_none());
    assert_eq!(active.inconsistent_skipped, 0);
    for w in &active.withdrawals {
        assert!(!w.executed && !w.cancelled);
    }
}

#[test]
fn pending_list_oversize_limit_still_pages_via_cursor() {
    let mut deps = mock_dependencies();
    WITHDRAW_DELAY.save(&mut deps.storage, &300u64).unwrap();
    for i in 0..40u16 {
        PENDING_WITHDRAWS
            .save(
                &mut deps.storage,
                &hash_n(i),
                &sample(i as u64, false, true, true),
            )
            .unwrap();
    }

    // Clients historically requested 50; contract caps at 30.
    let page1 = query_pending_page(deps.as_ref(), None, Some(50));
    assert_eq!(page1.withdrawals.len(), WITHDRAW_LIST_MAX_LIMIT as usize);
    assert!(
        page1.next_start_after.is_some(),
        "capped full page must set next_start_after so len<50 is not EOF"
    );

    let page2 = query_pending_page(deps.as_ref(), page1.next_start_after.clone(), Some(50));
    assert_eq!(page2.withdrawals.len(), 10);
    assert!(page2.next_start_after.is_none());
}
