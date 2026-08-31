//! Admin operations handlers.
//!
//! This module handles:
//! - Pause/unpause contract
//! - Admin transfer (propose/accept/cancel)
//! - Asset recovery (emergency)
//! - Active-index continue/rebuild (GL-139; no canonical-row delete)

use cosmwasm_std::{BankMsg, Coin, CosmosMsg, DepsMut, Env, MessageInfo, Response, Uint128};
use cw20::Cw20ExecuteMsg;

use crate::active_withdraw::{
    migrate_active_index_batch, reset_active_index_migration, resolve_migrate_batch_limit,
};
use crate::error::ContractError;
use crate::state::{PendingAdmin, ADMIN_TIMELOCK_DURATION, CONFIG, PENDING_ADMIN};
use common::AssetInfo;

// ============================================================================
// Pause/Unpause
// ============================================================================

/// Pause the contract (stops all transfers).
pub fn execute_pause(deps: DepsMut, info: MessageInfo) -> Result<Response, ContractError> {
    let mut config = CONFIG.load(deps.storage)?;
    if info.sender != config.admin {
        return Err(ContractError::Unauthorized);
    }

    config.paused = true;
    CONFIG.save(deps.storage, &config)?;

    Ok(Response::new().add_attribute("method", "pause"))
}

/// Unpause the contract (resumes transfers).
pub fn execute_unpause(deps: DepsMut, info: MessageInfo) -> Result<Response, ContractError> {
    let mut config = CONFIG.load(deps.storage)?;
    if info.sender != config.admin {
        return Err(ContractError::Unauthorized);
    }

    config.paused = false;
    CONFIG.save(deps.storage, &config)?;

    Ok(Response::new().add_attribute("method", "unpause"))
}

// ============================================================================
// Admin Transfer
// ============================================================================

/// Propose a new admin (starts timelock).
pub fn execute_propose_admin(
    deps: DepsMut,
    env: Env,
    info: MessageInfo,
    new_admin: String,
) -> Result<Response, ContractError> {
    let config = CONFIG.load(deps.storage)?;
    if info.sender != config.admin {
        return Err(ContractError::Unauthorized);
    }

    let new_admin_addr = deps.api.addr_validate(&new_admin)?;
    let pending = PendingAdmin {
        new_address: new_admin_addr.clone(),
        execute_after: env.block.time.plus_seconds(ADMIN_TIMELOCK_DURATION),
    };
    PENDING_ADMIN.save(deps.storage, &pending)?;

    Ok(Response::new()
        .add_attribute("method", "propose_admin")
        .add_attribute("new_admin", new_admin_addr.to_string())
        .add_attribute("execute_after", pending.execute_after.seconds().to_string()))
}

/// Accept pending admin role (after timelock).
pub fn execute_accept_admin(
    deps: DepsMut,
    env: Env,
    info: MessageInfo,
) -> Result<Response, ContractError> {
    let pending = PENDING_ADMIN
        .may_load(deps.storage)?
        .ok_or(ContractError::NoPendingAdmin)?;

    if info.sender != pending.new_address {
        return Err(ContractError::UnauthorizedPendingAdmin);
    }

    if env.block.time < pending.execute_after {
        let remaining = pending.execute_after.seconds() - env.block.time.seconds();
        return Err(ContractError::TimelockNotExpired {
            remaining_seconds: remaining,
        });
    }

    let mut config = CONFIG.load(deps.storage)?;
    config.admin = pending.new_address.clone();
    CONFIG.save(deps.storage, &config)?;
    PENDING_ADMIN.remove(deps.storage);

    Ok(Response::new()
        .add_attribute("method", "accept_admin")
        .add_attribute("new_admin", pending.new_address.to_string()))
}

/// Cancel pending admin proposal.
pub fn execute_cancel_admin_proposal(
    deps: DepsMut,
    info: MessageInfo,
) -> Result<Response, ContractError> {
    let config = CONFIG.load(deps.storage)?;
    if info.sender != config.admin {
        return Err(ContractError::Unauthorized);
    }

    PENDING_ADMIN.remove(deps.storage);

    Ok(Response::new().add_attribute("method", "cancel_admin_proposal"))
}

// ============================================================================
// Asset Recovery
// ============================================================================

/// Recover stuck assets (emergency, requires paused state).
///
/// LOCKED_BALANCES is intentionally not updated here. Updating it could cause
/// underflow if the recovered amount exceeds the tracked locked balance (e.g.
/// due to prior inconsistencies or dust). The admin must reconcile balances
/// separately if needed after recovery.
pub fn execute_recover_asset(
    deps: DepsMut,
    info: MessageInfo,
    asset: AssetInfo,
    amount: Uint128,
    recipient: String,
) -> Result<Response, ContractError> {
    let config = CONFIG.load(deps.storage)?;
    if info.sender != config.admin {
        return Err(ContractError::Unauthorized);
    }

    if !config.paused {
        return Err(ContractError::RecoveryNotAvailable);
    }

    let recipient_addr = deps.api.addr_validate(&recipient)?;

    let messages: Vec<CosmosMsg> = match asset {
        AssetInfo::Native { denom } => {
            vec![CosmosMsg::Bank(BankMsg::Send {
                to_address: recipient_addr.to_string(),
                amount: vec![Coin { denom, amount }],
            })]
        }
        AssetInfo::Cw20 { contract_addr } => {
            vec![CosmosMsg::Wasm(cosmwasm_std::WasmMsg::Execute {
                contract_addr: contract_addr.to_string(),
                msg: cosmwasm_std::to_json_binary(&Cw20ExecuteMsg::Transfer {
                    recipient: recipient_addr.to_string(),
                    amount,
                })?,
                funds: vec![],
            })]
        }
    };

    Ok(Response::new()
        .add_messages(messages)
        .add_attribute("method", "recover_asset")
        .add_attribute("recipient", recipient)
        .add_attribute("amount", amount.to_string()))
}

/// Continue or emergency-rebuild the active-index reconstruction (INV-TC-AW3).
///
/// Does **not** erase canonical `PENDING_WITHDRAWS` rows. `rebuild: true`
/// only resets the reconstruction cursor so the next batches rescan
/// canonical history into the membership index.
pub fn execute_continue_active_index_migrate(
    deps: DepsMut,
    info: MessageInfo,
    limit: Option<u32>,
    rebuild: bool,
) -> Result<Response, ContractError> {
    let config = CONFIG.load(deps.storage)?;
    if info.sender != config.admin {
        return Err(ContractError::Unauthorized);
    }

    if rebuild {
        reset_active_index_migration(deps.storage)?;
    }

    let batch = resolve_migrate_batch_limit(limit);
    let index_state = migrate_active_index_batch(deps.storage, batch)?;

    Ok(Response::new()
        .add_attribute("method", "continue_active_index_migrate")
        .add_attribute("rebuild", rebuild.to_string())
        .add_attribute("active_index_complete", index_state.complete.to_string())
        .add_attribute("active_index_scanned", index_state.scanned.to_string())
        .add_attribute("active_index_indexed", index_state.indexed.to_string())
        .add_attribute("active_index_batch_limit", batch.to_string()))
}
