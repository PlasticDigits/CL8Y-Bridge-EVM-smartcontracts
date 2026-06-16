//! Terra Client for canceler transactions
//!
//! Handles signing and submitting CancelWithdrawApproval transactions to Terra Classic.

#![allow(dead_code)]

use std::time::Duration;

use bip39::Mnemonic;
use cosmrs::{
    bip32::DerivationPath,
    crypto::secp256k1::SigningKey,
    tx::{self, Fee, Msg, SignDoc, SignerInfo},
    AccountId, Coin,
};
use eyre::{eyre, Result, WrapErr};
use reqwest::Client;
use serde::{Deserialize, Serialize};
use tracing::{debug, info, warn};

use crate::hash::bytes32_to_hex;

/// Terra derivation path
const TERRA_DERIVATION_PATH: &str = "m/44'/330'/0'/0/0";

/// Gas limit for WithdrawCancel execute messages.
const CANCEL_GAS_LIMIT: u64 = 300_000;

/// LocalTerra / dev default gas price (uluna per gas unit).
const LOCAL_GAS_PRICE_ULUNA: f64 = 0.015;

/// Terra Classic mainnet minimum gas price (uluna per gas unit).
const MAINNET_GAS_PRICE_ULUNA: f64 = 28.325;

/// FCD endpoints for live gas price queries.
const MAINNET_FCD_URL: &str = "https://terra-classic-fcd.publicnode.com";
const TESTNET_FCD_URL: &str = "https://fcd.luncblaze.com";

/// Safety bump applied on top of quoted gas price (percent).
const GAS_PRICE_BUMP_PERCENT: u32 = 10;

/// Gas prices from FCD (`/v1/txs/gas_prices`).
#[derive(Debug, Clone, Deserialize)]
struct GasPrices {
    uluna: String,
    #[serde(default)]
    uusd: Option<String>,
}

/// Resolved fee inputs for a cancel transaction.
#[derive(Debug, Clone, Copy)]
struct CancelGasEstimate {
    gas_limit: u64,
    gas_price: f64,
    fee_amount: u128,
}

/// Chain-aware fallback uluna gas price when FCD is unavailable.
fn fallback_gas_price_uluna(chain_id: &str) -> f64 {
    match chain_id {
        "columbus-5" => MAINNET_GAS_PRICE_ULUNA,
        "localterra" => LOCAL_GAS_PRICE_ULUNA,
        _ => LOCAL_GAS_PRICE_ULUNA,
    }
}

/// Compute cancel tx fee: `ceil(gas_limit * gas_price)` with optional bump.
fn fee_from_gas(gas_limit: u64, gas_price: f64, bump_percent: u32) -> CancelGasEstimate {
    let multiplier = 1.0 + (bump_percent as f64 / 100.0);
    let effective_price = gas_price * multiplier;
    let fee_amount = ((gas_limit as f64) * effective_price).ceil() as u128;
    CancelGasEstimate {
        gas_limit,
        gas_price: effective_price,
        fee_amount,
    }
}

/// Cancel message for Terra contract (V2)
///
/// IMPORTANT: Must match the contract's ExecuteMsg::WithdrawCancel variant.
/// CosmWasm serializes enum variants to snake_case, so `WithdrawCancel`
/// becomes `withdraw_cancel` in JSON.
#[derive(Debug, Clone, Serialize)]
pub struct WithdrawCancelMsg {
    pub withdraw_cancel: WithdrawCancelInner,
}

#[derive(Debug, Clone, Serialize)]
pub struct WithdrawCancelInner {
    pub xchain_hash_id: String,
}

/// Account info from LCD
#[derive(Debug, Clone, Deserialize)]
pub struct AccountInfo {
    pub sequence: u64,
    pub account_number: u64,
}

/// Terra client for canceler transactions
pub struct TerraClient {
    lcd_url: String,
    chain_id: String,
    contract_address: String,
    signing_key: SigningKey,
    pub address: AccountId,
    client: Client,
}

impl TerraClient {
    /// Create a new Terra client
    pub fn new(
        lcd_url: &str,
        chain_id: &str,
        contract_address: &str,
        mnemonic: &str,
    ) -> Result<Self> {
        let client = Client::builder()
            .timeout(Duration::from_secs(30))
            .build()
            .wrap_err("Failed to create HTTP client")?;

        // Parse mnemonic and derive signing key
        let mnemonic = Mnemonic::parse(mnemonic).map_err(|e| eyre!("Invalid mnemonic: {}", e))?;

        let seed = mnemonic.to_seed("");
        let path: DerivationPath = TERRA_DERIVATION_PATH
            .parse()
            .map_err(|e| eyre!("Invalid derivation path: {:?}", e))?;

        let signing_key = SigningKey::derive_from_path(seed, &path)
            .map_err(|e| eyre!("Failed to derive signing key: {}", e))?;

        // Get account address
        let public_key = signing_key.public_key();
        let address = public_key
            .account_id("terra")
            .map_err(|e| eyre!("Failed to get account ID: {}", e))?;

        info!(
            canceler_address = %address,
            contract = contract_address,
            "Terra client initialized"
        );

        Ok(Self {
            lcd_url: lcd_url.to_string(),
            chain_id: chain_id.to_string(),
            contract_address: contract_address.to_string(),
            signing_key,
            address,
            client,
        })
    }

    /// Get current gas prices from FCD.
    async fn get_gas_prices(&self) -> Result<GasPrices> {
        let fcd_url = match self.chain_id.as_str() {
            "columbus-5" => MAINNET_FCD_URL,
            _ => TESTNET_FCD_URL,
        };

        let url = format!("{}/v1/txs/gas_prices", fcd_url);

        match self.client.get(&url).send().await {
            Ok(response) if response.status().is_success() => Ok(response.json().await?),
            err => {
                warn!(
                    ?err,
                    chain_id = %self.chain_id,
                    fallback = fallback_gas_price_uluna(&self.chain_id),
                    "Could not fetch Terra gas prices from FCD, using chain fallback"
                );
                Ok(GasPrices {
                    uluna: fallback_gas_price_uluna(&self.chain_id).to_string(),
                    uusd: None,
                })
            }
        }
    }

    /// Estimate gas limit and uluna fee for a cancel transaction.
    async fn estimate_cancel_gas(&self) -> Result<CancelGasEstimate> {
        let gas_prices = self.get_gas_prices().await?;
        let fallback = fallback_gas_price_uluna(&self.chain_id);
        let gas_price: f64 = gas_prices.uluna.parse().unwrap_or_else(|_| {
            warn!(
                raw_value = %gas_prices.uluna,
                fallback,
                "Failed to parse uluna gas price from FCD, using chain fallback"
            );
            fallback
        });

        let estimate = fee_from_gas(CANCEL_GAS_LIMIT, gas_price, GAS_PRICE_BUMP_PERCENT);
        debug!(
            gas_limit = estimate.gas_limit,
            gas_price = estimate.gas_price,
            fee_uluna = estimate.fee_amount,
            "Estimated Terra cancel transaction fee"
        );
        Ok(estimate)
    }

    /// Get account info (sequence and account number)
    async fn get_account_info(&self) -> Result<AccountInfo> {
        let url = format!(
            "{}/cosmos/auth/v1beta1/accounts/{}",
            self.lcd_url, self.address
        );

        let response = self
            .client
            .get(&url)
            .send()
            .await
            .wrap_err("Failed to query account info")?;

        if !response.status().is_success() {
            return Err(eyre!(
                "Account query failed: {} - {}",
                response.status(),
                response.text().await.unwrap_or_default()
            ));
        }

        let data: serde_json::Value = response.json().await?;

        let account = data
            .get("account")
            .ok_or_else(|| eyre!("Missing 'account' field in response"))?;

        let sequence = account
            .get("sequence")
            .or_else(|| account.get("base_account").and_then(|b| b.get("sequence")))
            .and_then(|v| v.as_str())
            .unwrap_or("0")
            .parse()
            .unwrap_or(0);

        let account_number = account
            .get("account_number")
            .or_else(|| {
                account
                    .get("base_account")
                    .and_then(|b| b.get("account_number"))
            })
            .and_then(|v| v.as_str())
            .unwrap_or("0")
            .parse()
            .unwrap_or(0);

        Ok(AccountInfo {
            sequence,
            account_number,
        })
    }

    /// Cancel a pending withdrawal on Terra (V2: WithdrawCancel)
    pub async fn cancel_withdraw_approval(&self, xchain_hash_id: [u8; 32]) -> Result<String> {
        // Build the cancel message — matches ExecuteMsg::WithdrawCancel
        let msg = WithdrawCancelMsg {
            withdraw_cancel: WithdrawCancelInner {
                xchain_hash_id: base64::Engine::encode(
                    &base64::engine::general_purpose::STANDARD,
                    xchain_hash_id,
                ),
            },
        };

        info!(
            xchain_hash_id = %bytes32_to_hex(&xchain_hash_id),
            contract = %self.contract_address,
            "Submitting WithdrawCancel to Terra"
        );

        // Get account info and fee estimate (FCD gas prices + chain fallback)
        let account_info = self.get_account_info().await?;
        let gas_estimate = self.estimate_cancel_gas().await?;
        let gas_limit = gas_estimate.gas_limit;
        let fee_amount = gas_estimate.fee_amount;

        // Build the message
        let msg_json = serde_json::to_vec(&msg)?;

        let execute_msg = cosmrs::cosmwasm::MsgExecuteContract {
            sender: self.address.clone(),
            contract: self
                .contract_address
                .parse()
                .map_err(|e| eyre!("Invalid contract address: {:?}", e))?,
            msg: msg_json,
            funds: vec![],
        };

        // Build transaction body
        let body = tx::Body::new(
            vec![execute_msg
                .to_any()
                .map_err(|e| eyre!("Failed to convert message: {}", e))?],
            "",
            0u32,
        );

        // Build auth info
        let public_key = self.signing_key.public_key();
        let signer_info = SignerInfo::single_direct(Some(public_key), account_info.sequence);

        let fee = Fee::from_amount_and_gas(
            Coin {
                denom: "uluna"
                    .parse()
                    .expect("uluna is a valid constant Terra denom"),
                amount: fee_amount,
            },
            gas_limit,
        );

        let auth_info = signer_info.auth_info(fee);

        // Create sign doc
        let chain_id = self
            .chain_id
            .parse()
            .map_err(|_| eyre!("Invalid chain ID"))?;

        let sign_doc = SignDoc::new(&body, &auth_info, &chain_id, account_info.account_number)
            .map_err(|e| eyre!("Failed to create sign doc: {}", e))?;

        // Sign the transaction
        let tx_raw = sign_doc
            .sign(&self.signing_key)
            .map_err(|e| eyre!("Failed to sign transaction: {}", e))?;

        // Serialize and broadcast
        let tx_bytes = tx_raw
            .to_bytes()
            .map_err(|e| eyre!("Failed to serialize transaction: {}", e))?;

        let tx_hash = self.broadcast_tx(&tx_bytes).await?;

        info!(
            tx_hash = %tx_hash,
            xchain_hash_id = %bytes32_to_hex(&xchain_hash_id),
            "Approval successfully cancelled on Terra"
        );

        Ok(tx_hash)
    }

    /// Broadcast a signed transaction
    async fn broadcast_tx(&self, tx_bytes: &[u8]) -> Result<String> {
        let tx_b64 = base64::Engine::encode(&base64::engine::general_purpose::STANDARD, tx_bytes);

        let broadcast_request = serde_json::json!({
            "tx_bytes": tx_b64,
            "mode": "BROADCAST_MODE_SYNC"
        });

        let broadcast_url = format!("{}/cosmos/tx/v1beta1/txs", self.lcd_url);

        debug!(url = %broadcast_url, "Broadcasting transaction");

        let response = self
            .client
            .post(&broadcast_url)
            .json(&broadcast_request)
            .send()
            .await
            .map_err(|e| eyre!("Failed to broadcast: {}", e))?;

        let status = response.status();
        let body: serde_json::Value = response
            .json()
            .await
            .unwrap_or_else(|_| serde_json::json!({"error": "Failed to parse response"}));

        if status.is_success() {
            if let Some(tx_response) = body.get("tx_response") {
                let code = tx_response
                    .get("code")
                    .and_then(|v| v.as_u64())
                    .unwrap_or(0);

                if code == 0 {
                    let txhash = tx_response
                        .get("txhash")
                        .and_then(|v| v.as_str())
                        .unwrap_or("")
                        .to_string();

                    return Ok(txhash);
                } else {
                    let raw_log = tx_response
                        .get("raw_log")
                        .and_then(|v| v.as_str())
                        .unwrap_or("Unknown error");

                    return Err(eyre!("Transaction failed (code {}): {}", code, raw_log));
                }
            }
        }

        Err(eyre!("Broadcast failed: {}", body))
    }

    /// Check if a withdrawal can be cancelled (V2: QueryMsg::PendingWithdraw)
    pub async fn can_cancel(&self, xchain_hash_id: [u8; 32]) -> Result<bool> {
        // Query matches QueryMsg::PendingWithdraw { xchain_hash_id: Binary }
        let query = serde_json::json!({
            "pending_withdraw": {
                "xchain_hash_id": base64::Engine::encode(
                    &base64::engine::general_purpose::STANDARD,
                    xchain_hash_id,
                )
            }
        });

        let query_b64 = base64::Engine::encode(
            &base64::engine::general_purpose::STANDARD,
            serde_json::to_string(&query)?,
        );

        let url = format!(
            "{}/cosmwasm/wasm/v1/contract/{}/smart/{}",
            self.lcd_url, self.contract_address, query_b64
        );

        debug!(
            xchain_hash_id = %bytes32_to_hex(&xchain_hash_id),
            url = %url,
            "Querying Terra pending withdrawal for cancellability"
        );

        match self.client.get(&url).send().await {
            Ok(resp) if resp.status().is_success() => {
                let json: serde_json::Value = resp.json().await?;

                let exists = json["data"]["exists"].as_bool().unwrap_or(false);
                let approved = json["data"]["approved"].as_bool().unwrap_or(false);
                let cancelled = json["data"]["cancelled"].as_bool().unwrap_or(false);
                let executed = json["data"]["executed"].as_bool().unwrap_or(false);

                let cancellable = exists && approved && !cancelled && !executed;

                debug!(
                    xchain_hash_id = %bytes32_to_hex(&xchain_hash_id),
                    exists, approved, cancelled, executed, cancellable,
                    "Terra withdrawal cancellability check result"
                );

                Ok(cancellable)
            }
            Ok(resp) => {
                let status = resp.status();
                let body = resp.text().await.unwrap_or_default();
                warn!(
                    xchain_hash_id = %bytes32_to_hex(&xchain_hash_id),
                    status = %status,
                    body = %body,
                    "Terra pending_withdraw query failed"
                );
                Ok(false)
            }
            Err(e) => {
                warn!(
                    xchain_hash_id = %bytes32_to_hex(&xchain_hash_id),
                    error = %e,
                    "Could not query Terra pending withdrawal"
                );
                Ok(false)
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn mainnet_cancel_fee_matches_required_minimum() {
        // columbus-5: 300k gas @ 28.325 uluna/gas (+10% bump)
        let estimate = fee_from_gas(
            CANCEL_GAS_LIMIT,
            MAINNET_GAS_PRICE_ULUNA,
            GAS_PRICE_BUMP_PERCENT,
        );
        assert_eq!(estimate.fee_amount, 9_347_250);
        assert!(estimate.fee_amount >= 8_497_500);
    }

    #[test]
    fn localterra_uses_low_gas_price() {
        let estimate = fee_from_gas(CANCEL_GAS_LIMIT, LOCAL_GAS_PRICE_ULUNA, 0);
        assert_eq!(estimate.fee_amount, 4_500);
    }

    #[test]
    fn fallback_gas_price_is_chain_aware() {
        assert_eq!(
            fallback_gas_price_uluna("columbus-5"),
            MAINNET_GAS_PRICE_ULUNA
        );
        assert_eq!(
            fallback_gas_price_uluna("localterra"),
            LOCAL_GAS_PRICE_ULUNA
        );
    }
}
