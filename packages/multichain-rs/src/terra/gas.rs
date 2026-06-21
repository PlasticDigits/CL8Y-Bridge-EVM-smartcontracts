//! Terra Classic gas price estimation and fee calculation.

use reqwest::Client;
use serde::Deserialize;
use tracing::warn;

pub const MAINNET_FCD_URL: &str = "https://terra-classic-fcd.publicnode.com";
pub const TESTNET_FCD_URL: &str = "https://fcd.luncblaze.com";

pub const DEFAULT_GAS_LIMIT: u64 = 500_000;

/// LocalTerra / dev default gas price (uluna per gas unit).
pub const LOCAL_GAS_PRICE_ULUNA: f64 = 0.015;

/// Backwards-compatible alias for local dev gas price.
pub const DEFAULT_GAS_PRICE: f64 = LOCAL_GAS_PRICE_ULUNA;

/// Terra Classic mainnet minimum gas price (uluna per gas unit).
pub const MAINNET_GAS_PRICE_ULUNA: f64 = 28.325;

/// Safety bump applied on top of quoted gas price (percent).
pub const GAS_PRICE_BUMP_PERCENT: u32 = 10;

#[derive(Debug, Clone, Deserialize)]
pub struct GasPrices {
    pub uluna: String,
    #[serde(default)]
    pub uusd: Option<String>,
}

#[derive(Debug, Clone, Copy)]
pub struct GasFeeEstimate {
    pub gas_limit: u64,
    pub gas_price: f64,
    pub fee_amount: u128,
}

pub fn fcd_url_for_chain(chain_id: &str) -> &'static str {
    match chain_id {
        "columbus-5" => MAINNET_FCD_URL,
        _ => TESTNET_FCD_URL,
    }
}

/// Chain-aware fallback uluna gas price when FCD is unavailable.
pub fn fallback_gas_price_uluna(chain_id: &str) -> f64 {
    match chain_id {
        "columbus-5" => MAINNET_GAS_PRICE_ULUNA,
        "localterra" => LOCAL_GAS_PRICE_ULUNA,
        _ => LOCAL_GAS_PRICE_ULUNA,
    }
}

pub fn fallback_gas_prices(chain_id: &str) -> GasPrices {
    GasPrices {
        uluna: fallback_gas_price_uluna(chain_id).to_string(),
        uusd: Some("0.15".to_string()),
    }
}

pub fn parse_uluna_gas_price(raw: &str, chain_id: &str) -> f64 {
    raw.parse().unwrap_or_else(|_| {
        let fallback = fallback_gas_price_uluna(chain_id);
        warn!(
            raw_value = %raw,
            chain_id = %chain_id,
            fallback,
            "Failed to parse uluna gas price, using chain fallback"
        );
        fallback
    })
}

/// Compute tx fee: `ceil(gas_limit * gas_price)` with optional bump.
pub fn fee_from_gas(gas_limit: u64, gas_price: f64, bump_percent: u32) -> GasFeeEstimate {
    let multiplier = 1.0 + (bump_percent as f64 / 100.0);
    let effective_price = gas_price * multiplier;
    let fee_amount = ((gas_limit as f64) * effective_price).ceil() as u128;
    GasFeeEstimate {
        gas_limit,
        gas_price: effective_price,
        fee_amount,
    }
}

pub async fn fetch_gas_prices(client: &Client, chain_id: &str) -> GasPrices {
    let url = format!("{}/v1/txs/gas_prices", fcd_url_for_chain(chain_id));

    match client.get(&url).send().await {
        Ok(response) if response.status().is_success() => match response.json().await {
            Ok(prices) => prices,
            Err(err) => {
                warn!(
                    ?err,
                    chain_id = %chain_id,
                    "Failed to parse Terra FCD gas prices, using chain fallback"
                );
                fallback_gas_prices(chain_id)
            }
        },
        err => {
            warn!(
                ?err,
                chain_id = %chain_id,
                fallback = fallback_gas_price_uluna(chain_id),
                "Could not fetch Terra gas prices from FCD, using chain fallback"
            );
            fallback_gas_prices(chain_id)
        }
    }
}

pub fn estimate_execute_fee(
    gas_limit: u64,
    gas_prices: &GasPrices,
    chain_id: &str,
) -> GasFeeEstimate {
    let quoted = parse_uluna_gas_price(&gas_prices.uluna, chain_id);
    fee_from_gas(gas_limit, quoted, GAS_PRICE_BUMP_PERCENT)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn mainnet_execute_fee_meets_required_minimum() {
        // columbus-5: 500k gas @ 28.325 uluna/gas (+10% bump)
        let estimate = fee_from_gas(
            DEFAULT_GAS_LIMIT,
            MAINNET_GAS_PRICE_ULUNA,
            GAS_PRICE_BUMP_PERCENT,
        );
        assert!(estimate.fee_amount >= 14_162_500);
        assert!(estimate.fee_amount <= 15_578_751);
    }

    #[test]
    fn localterra_uses_low_gas_price() {
        let estimate = fee_from_gas(DEFAULT_GAS_LIMIT, LOCAL_GAS_PRICE_ULUNA, 0);
        assert_eq!(estimate.fee_amount, 7_500);
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
