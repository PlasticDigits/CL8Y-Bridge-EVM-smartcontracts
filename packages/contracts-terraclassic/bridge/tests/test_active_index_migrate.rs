//! Entry-point tests for `contract::migrate` and active-index reconstruction.
//!
//! These cover the MR !18 HIGH (stale `complete=true` after rollback to 2.0.0
//! then re-upgrade) and the cw-multi-test wiring gap: resume, idempotent
//! second call, incomplete query error, complete query OK.

use bridge::active_withdraw::{insert_active, is_active};
use bridge::contract::{migrate, query};
use bridge::fee_manager::{FeeConfig, FEE_CONFIG};
use bridge::msg::{ActiveWithdrawalsResponse, MigrateMsg, QueryMsg};
use bridge::state::{
    Config, PendingWithdraw, ACTIVE_INDEX_MIGRATION, ACTIVE_WITHDRAW_HASHES, CONFIG, CONTRACT_NAME,
    PENDING_WITHDRAWS, WITHDRAW_DELAY,
};
use cosmwasm_std::testing::{mock_dependencies, mock_env};
use cosmwasm_std::{from_json, Addr, Uint128};
use cw2::set_contract_version;
use cw_multi_test::{App, ContractWrapper, Executor};

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

fn query_active(
    deps: cosmwasm_std::Deps,
) -> Result<ActiveWithdrawalsResponse, cosmwasm_std::StdError> {
    let bin = query(
        deps,
        mock_env(),
        QueryMsg::ActiveWithdrawals {
            start_after: None,
            limit: None,
        },
    )?;
    from_json(&bin)
}

fn seed_runtime(storage: &mut dyn cosmwasm_std::Storage, cw2_version: &str) {
    set_contract_version(storage, CONTRACT_NAME, cw2_version).unwrap();
    CONFIG
        .save(
            storage,
            &Config {
                admin: Addr::unchecked("terra1admin"),
                paused: false,
                min_signatures: 1,
                min_bridge_amount: Uint128::zero(),
                max_bridge_amount: Uint128::new(u128::MAX),
                fee_bps: 50,
                fee_collector: Addr::unchecked("terra1fee"),
            },
        )
        .unwrap();
    FEE_CONFIG
        .save(
            storage,
            &FeeConfig::default_with_recipient(Addr::unchecked("terra1fee")),
        )
        .unwrap();
    WITHDRAW_DELAY.save(storage, &300u64).unwrap();
}

#[test]
fn migrate_empty_from_v2_0_marks_complete() {
    let mut deps = mock_dependencies();
    seed_runtime(&mut deps.storage, "2.0.0");
    let resp = migrate(
        deps.as_mut(),
        mock_env(),
        MigrateMsg {
            active_index_batch_limit: Some(50),
        },
    )
    .unwrap();
    assert_eq!(
        resp.attributes
            .iter()
            .find(|a| a.key == "active_index_complete")
            .unwrap()
            .value,
        "true"
    );
    assert_eq!(
        resp.attributes
            .iter()
            .find(|a| a.key == "active_index_reset")
            .unwrap()
            .value,
        "true"
    );
    let q = query_active(deps.as_ref()).unwrap();
    assert!(q.withdrawals.is_empty());
}

#[test]
fn migrate_mixed_history_resumes_then_is_idempotent() {
    let mut deps = mock_dependencies();
    seed_runtime(&mut deps.storage, "2.0.0");
    for i in 1u8..=5 {
        let pending = match i {
            1 | 2 => sample(i as u64, false, false),
            3 => sample(i as u64, true, false),
            _ => sample(i as u64, false, true),
        };
        PENDING_WITHDRAWS
            .save(&mut deps.storage, &hash(i), &pending)
            .unwrap();
    }

    let first = migrate(
        deps.as_mut(),
        mock_env(),
        MigrateMsg {
            active_index_batch_limit: Some(2),
        },
    )
    .unwrap();
    assert_eq!(
        first
            .attributes
            .iter()
            .find(|a| a.key == "active_index_complete")
            .unwrap()
            .value,
        "false"
    );
    let err = query_active(deps.as_ref()).unwrap_err();
    assert!(err.to_string().contains("incomplete"));

    let second = migrate(
        deps.as_mut(),
        mock_env(),
        MigrateMsg {
            active_index_batch_limit: Some(2),
        },
    )
    .unwrap();
    assert_eq!(
        second
            .attributes
            .iter()
            .find(|a| a.key == "active_index_complete")
            .unwrap()
            .value,
        "false"
    );

    let third = migrate(
        deps.as_mut(),
        mock_env(),
        MigrateMsg {
            active_index_batch_limit: Some(2),
        },
    )
    .unwrap();
    assert_eq!(
        third
            .attributes
            .iter()
            .find(|a| a.key == "active_index_complete")
            .unwrap()
            .value,
        "true"
    );
    let q = query_active(deps.as_ref()).unwrap();
    assert_eq!(q.withdrawals.len(), 2);
    assert!(q.next_start_after.is_none());

    let again = migrate(
        deps.as_mut(),
        mock_env(),
        MigrateMsg {
            active_index_batch_limit: Some(2),
        },
    )
    .unwrap();
    assert_eq!(
        again
            .attributes
            .iter()
            .find(|a| a.key == "active_index_reset")
            .unwrap()
            .value,
        "false",
        "same-version 2.1 continue must not reset a completed index"
    );
    assert_eq!(query_active(deps.as_ref()).unwrap().withdrawals.len(), 2);
}

#[test]
fn migrate_from_v2_0_resets_stale_complete_and_indexes_new_hash() {
    let mut deps = mock_dependencies();
    seed_runtime(&mut deps.storage, "2.0.0");
    // Leftover from a prior 2.1 install: reconstruction marked done.
    ACTIVE_INDEX_MIGRATION
        .save(
            &mut deps.storage,
            &bridge::state::ActiveIndexMigration {
                complete: true,
                last_key: None,
                scanned: 99,
                indexed: 0,
            },
        )
        .unwrap();
    // Submitted while 2.0 wasm was installed — not in the frozen index.
    PENDING_WITHDRAWS
        .save(&mut deps.storage, &hash(7), &sample(7, false, false))
        .unwrap();

    migrate(
        deps.as_mut(),
        mock_env(),
        MigrateMsg {
            active_index_batch_limit: Some(50),
        },
    )
    .unwrap();

    assert!(ACTIVE_WITHDRAW_HASHES
        .may_load(&deps.storage, &hash(7))
        .unwrap()
        .is_some());
    let q = query_active(deps.as_ref()).unwrap();
    assert_eq!(q.withdrawals.len(), 1);
}

#[test]
fn migrate_from_v2_0_removes_terminal_leftover_index_key() {
    let mut deps = mock_dependencies();
    seed_runtime(&mut deps.storage, "2.0.0");
    let executed = sample(8, false, true);
    PENDING_WITHDRAWS
        .save(&mut deps.storage, &hash(8), &executed)
        .unwrap();
    insert_active(&mut deps.storage, &hash(8)).unwrap();
    assert!(!is_active(&executed));

    migrate(
        deps.as_mut(),
        mock_env(),
        MigrateMsg {
            active_index_batch_limit: Some(50),
        },
    )
    .unwrap();

    assert!(ACTIVE_WITHDRAW_HASHES
        .may_load(&deps.storage, &hash(8))
        .unwrap()
        .is_none());
}

#[test]
fn cw_multitest_migrate_entry_is_wired() {
    let mut app = App::default();
    let admin = Addr::unchecked("terra1admin");
    let operator = Addr::unchecked("terra1operator");
    let contract = ContractWrapper::new(
        bridge::contract::execute,
        bridge::contract::instantiate,
        bridge::contract::query,
    )
    .with_migrate(bridge::contract::migrate);
    let code_id = app.store_code(Box::new(contract));
    let addr = app
        .instantiate_contract(
            code_id,
            admin.clone(),
            &bridge::msg::InstantiateMsg {
                admin: admin.to_string(),
                operators: vec![operator.to_string()],
                min_signatures: 1,
                min_bridge_amount: Uint128::new(1),
                max_bridge_amount: Uint128::new(1_000_000_000_000),
                fee_bps: 30,
                fee_collector: admin.to_string(),
                this_chain_id: cosmwasm_std::Binary::from(vec![0, 0, 0, 2]),
            },
            &[],
            "bridge",
            Some(admin.to_string()),
        )
        .unwrap();

    let code_id2 = app.store_code(Box::new(
        ContractWrapper::new(
            bridge::contract::execute,
            bridge::contract::instantiate,
            bridge::contract::query,
        )
        .with_migrate(bridge::contract::migrate),
    ));
    app.migrate_contract(
        admin,
        addr.clone(),
        &MigrateMsg {
            active_index_batch_limit: Some(50),
        },
        code_id2,
    )
    .unwrap();

    let idx: bridge::msg::ActiveWithdrawIndexResponse = app
        .wrap()
        .query_wasm_smart(&addr, &QueryMsg::ActiveWithdrawIndex {})
        .unwrap();
    assert!(idx.migration_complete);

    let active: ActiveWithdrawalsResponse = app
        .wrap()
        .query_wasm_smart(
            &addr,
            &QueryMsg::ActiveWithdrawals {
                start_after: None,
                limit: None,
            },
        )
        .unwrap();
    assert!(active.withdrawals.is_empty());
}
