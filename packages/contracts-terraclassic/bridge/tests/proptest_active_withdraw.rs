//! Property tests for INV-TC-AW1 (canonical record ↔ active index).
//!
//! Run with `PROPTEST_CASES=4096 cargo test -p bridge proptest_active_withdraw` for
//! heavier fuzzing. See [docs/TERRACLASSIC_BRIDGE_INVARIANTS.md](../../../docs/TERRACLASSIC_BRIDGE_INVARIANTS.md).

use bridge::active_withdraw::{is_active, migrate_active_index_batch, save_pending_and_sync_index};
use bridge::state::{
    PendingWithdraw, ACTIVE_WITHDRAW_COUNT, ACTIVE_WITHDRAW_HASHES, PENDING_WITHDRAWS,
};
use cosmwasm_std::testing::mock_dependencies;
use cosmwasm_std::{Addr, Order, Storage, Uint128};
use proptest::prelude::*;

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
        operator_funds: vec![],
        submitted_at: 1,
        approved_at: 2,
        approved: true,
        cancelled,
        executed,
    }
}

fn hash_for(n: u8) -> [u8; 32] {
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
        assert_eq!(in_index, is_active(&pending));
        if in_index {
            expected += 1;
        }
    }
    assert_eq!(
        ACTIVE_WITHDRAW_COUNT
            .may_load(storage)
            .unwrap()
            .unwrap_or(0),
        expected
    );
}

#[derive(Clone, Debug)]
enum Op {
    Submit(u8),
    Cancel(u8),
    Uncancel(u8),
    Execute(u8),
}

fn op_strategy() -> impl Strategy<Value = Op> {
    prop_oneof![
        (0u8..16).prop_map(Op::Submit),
        (0u8..16).prop_map(Op::Cancel),
        (0u8..16).prop_map(Op::Uncancel),
        (0u8..16).prop_map(Op::Execute),
    ]
}

proptest! {
    #![proptest_config(ProptestConfig::with_cases(256))]

    #[test]
    fn proptest_active_index_matches_canonical(ops in prop::collection::vec(op_strategy(), 0..40)) {
        let mut deps = mock_dependencies();
        for op in ops {
            match op {
                Op::Submit(n) => {
                    let h = hash_for(n);
                    if PENDING_WITHDRAWS.may_load(&deps.storage, &h).unwrap().is_none() {
                        save_pending_and_sync_index(
                            &mut deps.storage,
                            &h,
                            &sample(n as u64, false, false),
                        )
                        .unwrap();
                    }
                }
                Op::Cancel(n) => {
                    let h = hash_for(n);
                    if let Some(mut p) = PENDING_WITHDRAWS.may_load(&deps.storage, &h).unwrap() {
                        if !p.executed {
                            p.cancelled = true;
                            save_pending_and_sync_index(&mut deps.storage, &h, &p).unwrap();
                        }
                    }
                }
                Op::Uncancel(n) => {
                    let h = hash_for(n);
                    if let Some(mut p) = PENDING_WITHDRAWS.may_load(&deps.storage, &h).unwrap() {
                        if !p.executed && p.cancelled {
                            p.cancelled = false;
                            save_pending_and_sync_index(&mut deps.storage, &h, &p).unwrap();
                        }
                    }
                }
                Op::Execute(n) => {
                    let h = hash_for(n);
                    if let Some(mut p) = PENDING_WITHDRAWS.may_load(&deps.storage, &h).unwrap() {
                        if !p.cancelled {
                            p.executed = true;
                            save_pending_and_sync_index(&mut deps.storage, &h, &p).unwrap();
                        }
                    }
                }
            }
            assert_inv(&deps.storage);
        }
    }

    #[test]
    fn proptest_migrate_rebuilds_index(
        statuses in prop::collection::vec((any::<bool>(), any::<bool>()), 0..30),
        batch in 1u32..8,
    ) {
        let mut deps = mock_dependencies();
        for (i, (cancelled, executed)) in statuses.iter().enumerate() {
            // executed wins if both true — matches fail-closed terminal
            let pending = sample(i as u64, *cancelled && !*executed, *executed);
            PENDING_WITHDRAWS
                .save(&mut deps.storage, &hash_for(i as u8), &pending)
                .unwrap();
        }

        loop {
            let state = migrate_active_index_batch(&mut deps.storage, batch).unwrap();
            if state.complete {
                break;
            }
        }
        assert_inv(&deps.storage);
        let again = migrate_active_index_batch(&mut deps.storage, batch).unwrap();
        assert!(again.complete);
        assert_inv(&deps.storage);
    }
}
