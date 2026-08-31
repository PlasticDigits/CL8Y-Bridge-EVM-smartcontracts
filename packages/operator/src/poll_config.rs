//! Validated EVM poll / writer-schedule configuration (GL-138).
//!
//! Parsed once at startup. Zero, overflow, and out-of-range values are rejected
//! rather than clamped so misconfiguration cannot produce a tight poll loop or
//! an unbounded `eth_getLogs` range.
//!
//! Bounds are documented in `docs/OPERATOR_WRITER_INVARIANTS.md` (INV-OP-W8).

use eyre::{eyre, Result};
use std::env;
use std::time::Duration;

/// Default writer-manager interval (independent of watcher `POLL_INTERVAL_MS`).
pub const DEFAULT_WRITER_POLL_INTERVAL_MS: u64 = 5_000;
pub const MIN_WRITER_POLL_INTERVAL_MS: u64 = 200;
pub const MAX_WRITER_POLL_INTERVAL_MS: u64 = 120_000;

pub const DEFAULT_LOOKBACK_BLOCKS: u64 = 5_000;
pub const MIN_LOOKBACK_BLOCKS: u64 = 1;
pub const MAX_LOOKBACK_BLOCKS: u64 = 100_000;

pub const DEFAULT_CHUNK_SIZE: u64 = 5_000;
pub const MIN_CHUNK_SIZE: u64 = 1;
pub const MAX_CHUNK_SIZE: u64 = 50_000;

pub const DEFAULT_RPC_BACKOFF_INITIAL_MS: u64 = 2_000;
pub const MIN_RPC_BACKOFF_INITIAL_MS: u64 = 100;
pub const MAX_RPC_BACKOFF_INITIAL_MS: u64 = 60_000;

pub const DEFAULT_RPC_BACKOFF_MAX_MS: u64 = 60_000;
pub const MIN_RPC_BACKOFF_MAX_MS: u64 = 1_000;
pub const MAX_RPC_BACKOFF_MAX_MS: u64 = 600_000;

pub const DEFAULT_NEGATIVE_RETRY_INITIAL_MS: u64 = 5_000;
pub const MIN_NEGATIVE_RETRY_INITIAL_MS: u64 = 100;
pub const MAX_NEGATIVE_RETRY_INITIAL_MS: u64 = 60_000;

pub const DEFAULT_NEGATIVE_RETRY_MAX_MS: u64 = 300_000;
pub const MIN_NEGATIVE_RETRY_MAX_MS: u64 = 1_000;
pub const MAX_NEGATIVE_RETRY_MAX_MS: u64 = 3_600_000;

pub const DEFAULT_NEGATIVE_RETRY_TTL_SECS: u64 = 86_400;
pub const MIN_NEGATIVE_RETRY_TTL_SECS: u64 = 60;
pub const MAX_NEGATIVE_RETRY_TTL_SECS: u64 = 604_800;

pub const DEFAULT_NEGATIVE_RETRY_CACHE_SIZE: usize = 10_000;
pub const MIN_NEGATIVE_RETRY_CACHE_SIZE: usize = 16;
pub const MAX_NEGATIVE_RETRY_CACHE_SIZE: usize = 100_000;

pub const DEFAULT_MAX_VERIFY_PER_CYCLE: usize = 64;
pub const MIN_MAX_VERIFY_PER_CYCLE: usize = 1;
pub const MAX_MAX_VERIFY_PER_CYCLE: usize = 10_000;

/// Jitter as basis points of the backoff (1500 = ±15%).
pub const DEFAULT_BACKOFF_JITTER_BPS: u32 = 1_500;
pub const MAX_BACKOFF_JITTER_BPS: u32 = 5_000;

pub const BACKOFF_MULTIPLIER: f64 = 2.0;

/// Parse `raw` as u64 in `[min, max]`. Missing/empty uses `default` (which must itself be in range).
pub fn parse_bounded_u64(
    name: &str,
    raw: Option<&str>,
    default: u64,
    min: u64,
    max: u64,
) -> Result<u64> {
    debug_assert!(min <= default && default <= max);
    match raw {
        None => Ok(default),
        Some(s) if s.trim().is_empty() => Ok(default),
        Some(s) => {
            let v: u64 = s
                .trim()
                .parse()
                .map_err(|_| eyre!("{name} must be an integer in [{min}, {max}], got {s:?}"))?;
            if v < min || v > max {
                return Err(eyre!(
                    "{name}={v} is outside the documented bounds [{min}, {max}]"
                ));
            }
            Ok(v)
        }
    }
}

pub fn parse_bounded_usize(
    name: &str,
    raw: Option<&str>,
    default: usize,
    min: usize,
    max: usize,
) -> Result<usize> {
    let v = parse_bounded_u64(name, raw, default as u64, min as u64, max as u64)?;
    Ok(v as usize)
}

fn env_opt(name: &str) -> Option<String> {
    env::var(name).ok()
}

/// Shared lookback/chunk settings for EVM watcher and writer event polling.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct EvmPollConfig {
    pub lookback_blocks: u64,
    pub chunk_size: u64,
}

impl EvmPollConfig {
    pub fn from_env() -> Result<Self> {
        let lookback_blocks = parse_bounded_u64(
            "EVM_POLL_LOOKBACK_BLOCKS",
            env_opt("EVM_POLL_LOOKBACK_BLOCKS").as_deref(),
            DEFAULT_LOOKBACK_BLOCKS,
            MIN_LOOKBACK_BLOCKS,
            MAX_LOOKBACK_BLOCKS,
        )?;
        let chunk_size = parse_bounded_u64(
            "EVM_POLL_CHUNK_SIZE",
            env_opt("EVM_POLL_CHUNK_SIZE").as_deref(),
            DEFAULT_CHUNK_SIZE,
            MIN_CHUNK_SIZE,
            MAX_CHUNK_SIZE,
        )?;
        Ok(Self {
            lookback_blocks,
            chunk_size,
        })
    }
}

/// Per-chain writer interval, RPC backoff, and negative-verification schedule.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct WriterScheduleConfig {
    pub poll_interval: Duration,
    pub rpc_backoff_initial: Duration,
    pub rpc_backoff_max: Duration,
    pub jitter_bps: u32,
    pub negative_retry_initial: Duration,
    pub negative_retry_max: Duration,
    pub negative_retry_ttl: Duration,
    pub negative_retry_cache_size: usize,
    pub max_verify_per_cycle: usize,
}

impl WriterScheduleConfig {
    pub fn from_env() -> Result<Self> {
        let poll_ms = parse_bounded_u64(
            "WRITER_POLL_INTERVAL_MS",
            env_opt("WRITER_POLL_INTERVAL_MS").as_deref(),
            DEFAULT_WRITER_POLL_INTERVAL_MS,
            MIN_WRITER_POLL_INTERVAL_MS,
            MAX_WRITER_POLL_INTERVAL_MS,
        )?;
        let rpc_initial = parse_bounded_u64(
            "WRITER_RPC_BACKOFF_INITIAL_MS",
            env_opt("WRITER_RPC_BACKOFF_INITIAL_MS").as_deref(),
            DEFAULT_RPC_BACKOFF_INITIAL_MS,
            MIN_RPC_BACKOFF_INITIAL_MS,
            MAX_RPC_BACKOFF_INITIAL_MS,
        )?;
        let rpc_max = parse_bounded_u64(
            "WRITER_RPC_BACKOFF_MAX_MS",
            env_opt("WRITER_RPC_BACKOFF_MAX_MS").as_deref(),
            DEFAULT_RPC_BACKOFF_MAX_MS,
            MIN_RPC_BACKOFF_MAX_MS,
            MAX_RPC_BACKOFF_MAX_MS,
        )?;
        if rpc_max < rpc_initial {
            return Err(eyre!(
                "WRITER_RPC_BACKOFF_MAX_MS ({rpc_max}) must be >= WRITER_RPC_BACKOFF_INITIAL_MS ({rpc_initial})"
            ));
        }
        let jitter_bps = parse_bounded_u64(
            "WRITER_BACKOFF_JITTER_BPS",
            env_opt("WRITER_BACKOFF_JITTER_BPS").as_deref(),
            DEFAULT_BACKOFF_JITTER_BPS as u64,
            0,
            MAX_BACKOFF_JITTER_BPS as u64,
        )? as u32;
        let neg_initial = parse_bounded_u64(
            "WRITER_NEGATIVE_RETRY_INITIAL_MS",
            env_opt("WRITER_NEGATIVE_RETRY_INITIAL_MS").as_deref(),
            DEFAULT_NEGATIVE_RETRY_INITIAL_MS,
            MIN_NEGATIVE_RETRY_INITIAL_MS,
            MAX_NEGATIVE_RETRY_INITIAL_MS,
        )?;
        let neg_max = parse_bounded_u64(
            "WRITER_NEGATIVE_RETRY_MAX_MS",
            env_opt("WRITER_NEGATIVE_RETRY_MAX_MS").as_deref(),
            DEFAULT_NEGATIVE_RETRY_MAX_MS,
            MIN_NEGATIVE_RETRY_MAX_MS,
            MAX_NEGATIVE_RETRY_MAX_MS,
        )?;
        if neg_max < neg_initial {
            return Err(eyre!(
                "WRITER_NEGATIVE_RETRY_MAX_MS ({neg_max}) must be >= WRITER_NEGATIVE_RETRY_INITIAL_MS ({neg_initial})"
            ));
        }
        let neg_ttl = parse_bounded_u64(
            "WRITER_NEGATIVE_RETRY_TTL_SECS",
            env_opt("WRITER_NEGATIVE_RETRY_TTL_SECS").as_deref(),
            DEFAULT_NEGATIVE_RETRY_TTL_SECS,
            MIN_NEGATIVE_RETRY_TTL_SECS,
            MAX_NEGATIVE_RETRY_TTL_SECS,
        )?;
        let neg_cache = parse_bounded_usize(
            "WRITER_NEGATIVE_RETRY_CACHE_SIZE",
            env_opt("WRITER_NEGATIVE_RETRY_CACHE_SIZE").as_deref(),
            DEFAULT_NEGATIVE_RETRY_CACHE_SIZE,
            MIN_NEGATIVE_RETRY_CACHE_SIZE,
            MAX_NEGATIVE_RETRY_CACHE_SIZE,
        )?;
        let max_verify = parse_bounded_usize(
            "WRITER_MAX_VERIFY_PER_CYCLE",
            env_opt("WRITER_MAX_VERIFY_PER_CYCLE").as_deref(),
            DEFAULT_MAX_VERIFY_PER_CYCLE,
            MIN_MAX_VERIFY_PER_CYCLE,
            MAX_MAX_VERIFY_PER_CYCLE,
        )?;
        Ok(Self {
            poll_interval: Duration::from_millis(poll_ms),
            rpc_backoff_initial: Duration::from_millis(rpc_initial),
            rpc_backoff_max: Duration::from_millis(rpc_max),
            jitter_bps,
            negative_retry_initial: Duration::from_millis(neg_initial),
            negative_retry_max: Duration::from_millis(neg_max),
            negative_retry_ttl: Duration::from_secs(neg_ttl),
            negative_retry_cache_size: neg_cache,
            max_verify_per_cycle: max_verify,
        })
    }
}

/// Capped exponential backoff with symmetric jitter.
///
/// `seed` should combine chain id / hash / attempt so concurrent operators do not
/// retry in lockstep (INV-OP-W7). `jitter_bps` of 1500 yields ±15%.
pub fn jittered_exponential_backoff(
    attempt: u32,
    initial: Duration,
    max: Duration,
    jitter_bps: u32,
    seed: u64,
) -> Duration {
    let exp = initial.as_secs_f64() * BACKOFF_MULTIPLIER.powi(attempt.min(31) as i32);
    let capped = exp.min(max.as_secs_f64());
    Duration::from_secs_f64(apply_jitter_factor(capped, jitter_bps, seed).max(0.001))
}

/// SplitMix64 → `0..=1`, then scale to `[1 - span, 1 + span]` where span = jitter_bps/10000.
pub fn apply_jitter_factor(base: f64, jitter_bps: u32, seed: u64) -> f64 {
    if jitter_bps == 0 {
        return base;
    }
    let span = (jitter_bps as f64 / 10_000.0).min(0.5);
    let unit = splitmix64_unit(seed);
    let factor = (1.0 - span) + (2.0 * span * unit);
    base * factor
}

fn splitmix64_unit(seed: u64) -> f64 {
    let mut z = seed.wrapping_add(0x9E3779B97F4A7C15);
    z = (z ^ (z >> 30)).wrapping_mul(0xBF58476D1CE4E5B9);
    z = (z ^ (z >> 27)).wrapping_mul(0x94D049BB133111EB);
    z ^= z >> 31;
    (z as f64) / (u64::MAX as f64)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_default_when_absent() {
        assert_eq!(parse_bounded_u64("X", None, 5, 1, 10).unwrap(), 5);
        assert_eq!(parse_bounded_u64("X", Some(""), 5, 1, 10).unwrap(), 5);
    }

    #[test]
    fn parse_rejects_zero_when_min_is_one() {
        assert!(parse_bounded_u64("X", Some("0"), 5, 1, 10).is_err());
    }

    #[test]
    fn parse_rejects_above_max() {
        assert!(parse_bounded_u64("X", Some("11"), 5, 1, 10).is_err());
    }

    #[test]
    fn parse_rejects_non_integer() {
        assert!(parse_bounded_u64("X", Some("nope"), 5, 1, 10).is_err());
    }

    #[test]
    fn parse_rejects_overflow_u64() {
        assert!(parse_bounded_u64("X", Some("18446744073709551616"), 5, 1, 10).is_err());
    }

    #[test]
    fn parse_accepts_bounds() {
        assert_eq!(parse_bounded_u64("X", Some("1"), 5, 1, 10).unwrap(), 1);
        assert_eq!(parse_bounded_u64("X", Some("10"), 5, 1, 10).unwrap(), 10);
    }

    #[test]
    fn jitter_zero_is_identity() {
        let d =
            jittered_exponential_backoff(0, Duration::from_secs(2), Duration::from_secs(60), 0, 42);
        assert_eq!(d, Duration::from_secs(2));
    }

    #[test]
    fn jitter_caps_at_max() {
        let d =
            jittered_exponential_backoff(20, Duration::from_secs(2), Duration::from_secs(8), 0, 1);
        assert_eq!(d, Duration::from_secs(8));
    }

    #[test]
    fn jitter_varies_with_seed() {
        let a = apply_jitter_factor(100.0, 1500, 1);
        let b = apply_jitter_factor(100.0, 1500, 2);
        assert_ne!(a, b);
        assert!((85.0..=115.0).contains(&a));
        assert!((85.0..=115.0).contains(&b));
    }

    #[test]
    fn default_configs_are_in_bounds() {
        const {
            assert!(DEFAULT_WRITER_POLL_INTERVAL_MS >= MIN_WRITER_POLL_INTERVAL_MS);
            assert!(DEFAULT_LOOKBACK_BLOCKS >= MIN_LOOKBACK_BLOCKS);
            assert!(DEFAULT_CHUNK_SIZE >= MIN_CHUNK_SIZE);
            assert!(
                DEFAULT_NEGATIVE_RETRY_CACHE_SIZE as u64 >= MIN_NEGATIVE_RETRY_CACHE_SIZE as u64
            );
        }
    }
}
