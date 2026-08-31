//! Method-level EVM JSON-RPC fallback shared by the watcher and writer (GL-138).
//!
//! Selecting an endpoint with `eth_blockNumber` is not proof that `eth_getLogs`
//! will succeed. Each log query is retried against the remaining validated URLs
//! on retryable transport / HTTP / rate-limit / provider-limit errors.
//!
//! Logs and metrics use [`multichain_rs::sanitize_rpc_endpoint`] so credentials
//! and query tokens never appear (INV-OP-W9).

use alloy::providers::{Provider, RootProvider};
use alloy::rpc::types::{Filter, Log};
use alloy::transports::http::{Client, Http};
use eyre::{eyre, Result};
use std::future::Future;
use tracing::{debug, info, warn};

use crate::metrics;

/// Run `op(provider_index)` against endpoints in try-order until one returns `Ok`.
///
/// Used for method-level fallback (`eth_getLogs`, typed event queries). Cursor
/// advancement is the caller's responsibility (INV-OP-W2).
pub async fn with_endpoint_fallback<T, F, Fut>(
    urls: &[String],
    prefer_index: Option<usize>,
    chain_label: &str,
    method: &str,
    mut op: F,
) -> Result<T>
where
    F: FnMut(usize) -> Fut,
    Fut: Future<Output = Result<T>>,
{
    if urls.is_empty() {
        return Err(eyre!("no EVM RPC endpoints configured for {method}"));
    }
    let order = endpoint_try_order(urls.len(), prefer_index);
    let mut last_err: Option<eyre::Report> = None;

    for (attempt, idx) in order.iter().copied().enumerate() {
        match op(idx).await {
            Ok(v) => {
                if attempt > 0 {
                    metrics::record_rpc_fallback(chain_label, method);
                    info!(
                        chain = chain_label,
                        method,
                        rpc = %multichain_rs::sanitize_rpc_endpoint(&urls[idx]),
                        fallback_attempt = attempt,
                        "{method} succeeded on fallback endpoint"
                    );
                }
                return Ok(v);
            }
            Err(e) => {
                metrics::record_rpc_failure(chain_label, method);
                let retryable = multichain_rs::is_retryable_evm_rpc_error_message(&e.to_string());
                warn!(
                    chain = chain_label,
                    method,
                    rpc = %multichain_rs::sanitize_rpc_endpoint(&urls[idx]),
                    retryable,
                    remaining = order.len().saturating_sub(attempt + 1),
                    error = %e,
                    "{method} failed on endpoint"
                );
                last_err = Some(e);
                if !retryable && attempt + 1 < order.len() {
                    debug!(
                        chain = chain_label,
                        method, "error not classified retryable; still trying remaining endpoints"
                    );
                }
            }
        }
    }

    Err(eyre!(
        "{method} failed on all configured RPC endpoints: {}",
        last_err.unwrap_or_else(|| eyre!("{method} failed"))
    ))
}

/// `eth_getLogs` against `providers`, trying `prefer_index` first then the rest.
///
/// Advances through endpoints only; never skips the caller's block range.
/// The caller owns contiguous cursor semantics.
pub async fn get_logs_with_endpoint_fallback(
    urls: &[String],
    providers: &[RootProvider<Http<Client>>],
    filter: &Filter,
    prefer_index: Option<usize>,
    chain_label: &str,
) -> Result<Vec<Log>> {
    if providers.len() != urls.len() {
        return Err(eyre!(
            "RPC URL/provider length mismatch ({} urls, {} providers)",
            urls.len(),
            providers.len()
        ));
    }
    with_endpoint_fallback(urls, prefer_index, chain_label, "eth_getLogs", |idx| {
        let provider = providers[idx].clone();
        let filter = filter.clone();
        async move { provider.get_logs(&filter).await.map_err(|e| eyre::eyre!(e)) }
    })
    .await
}

/// Prefer `prefer_index` (consensus head provider) then remaining indices in order.
pub fn endpoint_try_order(count: usize, prefer_index: Option<usize>) -> Vec<usize> {
    if count == 0 {
        return Vec::new();
    }
    let mut order: Vec<usize> = (0..count).collect();
    if let Some(pref) = prefer_index {
        if pref < count {
            order.remove(pref);
            order.insert(0, pref);
        }
    }
    order
}

#[cfg(test)]
mod tests {
    use super::*;
    use alloy::providers::ProviderBuilder;
    use axum::{
        extract::State, http::StatusCode, response::IntoResponse, routing::post, Json, Router,
    };
    use serde_json::{json, Value};
    use std::sync::{
        atomic::{AtomicU64, Ordering},
        Arc,
    };

    #[test]
    fn try_order_prefers_consensus_index() {
        assert_eq!(endpoint_try_order(3, Some(1)), vec![1, 0, 2]);
        assert_eq!(endpoint_try_order(3, Some(0)), vec![0, 1, 2]);
        assert_eq!(endpoint_try_order(2, None), vec![0, 1]);
        assert!(endpoint_try_order(0, Some(0)).is_empty());
    }

    #[derive(Clone)]
    struct MockCfg {
        fail_logs: bool,
        log_calls: Arc<AtomicU64>,
        block_calls: Arc<AtomicU64>,
        log_status: StatusCode,
    }

    async fn jsonrpc_handler(
        State(cfg): State<MockCfg>,
        Json(req): Json<Value>,
    ) -> impl IntoResponse {
        let method = req.get("method").and_then(|m| m.as_str()).unwrap_or("");
        let id = req.get("id").cloned().unwrap_or(json!(1));
        match method {
            "eth_blockNumber" => {
                cfg.block_calls.fetch_add(1, Ordering::SeqCst);
                Json(json!({"jsonrpc":"2.0","id": id, "result": "0x64"})).into_response()
            }
            "eth_getLogs" => {
                cfg.log_calls.fetch_add(1, Ordering::SeqCst);
                if cfg.fail_logs {
                    (
                        cfg.log_status,
                        Json(json!({
                            "jsonrpc": "2.0",
                            "id": id,
                            "error": {"code": -32005, "message": "Too many requests"}
                        })),
                    )
                        .into_response()
                } else {
                    Json(json!({"jsonrpc":"2.0","id": id, "result": []})).into_response()
                }
            }
            _ => Json(json!({
                "jsonrpc": "2.0",
                "id": id,
                "error": {"code": -32601, "message": "method not found"}
            }))
            .into_response(),
        }
    }

    async fn spawn_mock(fail_logs: bool, log_status: StatusCode) -> (String, MockCfg) {
        let cfg = MockCfg {
            fail_logs,
            log_calls: Arc::new(AtomicU64::new(0)),
            block_calls: Arc::new(AtomicU64::new(0)),
            log_status,
        };
        let app = Router::new()
            .route("/", post(jsonrpc_handler))
            .with_state(cfg.clone());
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        tokio::spawn(async move {
            axum::serve(listener, app).await.ok();
        });
        (format!("http://{addr}"), cfg)
    }

    #[tokio::test]
    async fn get_logs_falls_back_when_primary_rate_limits() {
        let (primary, pcfg) = spawn_mock(true, StatusCode::TOO_MANY_REQUESTS).await;
        let (fallback, fcfg) = spawn_mock(false, StatusCode::OK).await;
        let urls = vec![primary, fallback];
        let providers = vec![
            ProviderBuilder::new().on_http(urls[0].parse().unwrap()),
            ProviderBuilder::new().on_http(urls[1].parse().unwrap()),
        ];
        let filter = Filter::new();
        let logs = get_logs_with_endpoint_fallback(&urls, &providers, &filter, None, "evm-test")
            .await
            .expect("fallback should succeed");
        assert!(logs.is_empty());
        assert!(pcfg.log_calls.load(Ordering::SeqCst) >= 1);
        assert!(fcfg.log_calls.load(Ordering::SeqCst) >= 1);
    }

    #[tokio::test]
    async fn get_logs_errors_when_all_endpoints_fail() {
        let (a, _) = spawn_mock(true, StatusCode::TOO_MANY_REQUESTS).await;
        let (b, _) = spawn_mock(true, StatusCode::SERVICE_UNAVAILABLE).await;
        let urls = vec![a, b];
        let providers = vec![
            ProviderBuilder::new().on_http(urls[0].parse().unwrap()),
            ProviderBuilder::new().on_http(urls[1].parse().unwrap()),
        ];
        let err =
            get_logs_with_endpoint_fallback(&urls, &providers, &Filter::new(), Some(0), "evm-test")
                .await
                .unwrap_err();
        let msg = err.to_string();
        assert!(
            msg.contains("all configured RPC endpoints") || msg.contains("eth_getLogs"),
            "{msg}"
        );
    }

    #[tokio::test]
    async fn get_logs_does_not_call_block_number() {
        // Method-level: log query must not depend on a prior eth_blockNumber success
        // on the same endpoint (the livelock root cause).
        let (url, cfg) = spawn_mock(false, StatusCode::OK).await;
        let urls = vec![url.clone()];
        let providers = vec![ProviderBuilder::new().on_http(url.parse().unwrap())];
        let _ =
            get_logs_with_endpoint_fallback(&urls, &providers, &Filter::new(), None, "evm-test")
                .await
                .unwrap();
        assert_eq!(cfg.block_calls.load(Ordering::SeqCst), 0);
        assert!(cfg.log_calls.load(Ordering::SeqCst) >= 1);
    }
}
