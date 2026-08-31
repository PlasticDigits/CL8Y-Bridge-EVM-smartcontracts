//! Bounded negative source-verification retry schedule (GL-138, INV-OP-W4).
//!
//! Unapproved destination-chain withdrawals whose source deposit is not yet
//! visible (or never will be) must not be re-verified on every writer cycle.
//! Entries expire so a late-visible deposit is retried. Memory is strictly
//! capped; attacker-controlled hashes cannot grow the map without bound.

use crate::poll_config::{jittered_exponential_backoff, WriterScheduleConfig};
use std::collections::HashMap;
use std::time::Instant;

struct NegativeEntry {
    attempts: u32,
    next_retry: Instant,
    inserted_at: Instant,
}

/// Per-destination-writer cache keyed by `xchain_hash_id`.
pub struct NegativeVerifySchedule {
    entries: HashMap<[u8; 32], NegativeEntry>,
    max_size: usize,
    cfg: WriterScheduleConfig,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum VerifyDecision {
    /// Run source-chain verification now.
    Verify,
    /// Skip this cycle (backoff). Caller should count `negative_retry_suppressed`.
    Suppress,
}

impl NegativeVerifySchedule {
    pub fn new(cfg: WriterScheduleConfig) -> Self {
        Self {
            entries: HashMap::new(),
            max_size: cfg.negative_retry_cache_size,
            cfg,
        }
    }

    pub fn len(&self) -> usize {
        self.entries.len()
    }

    pub fn contains(&self, hash: &[u8; 32]) -> bool {
        self.entries.contains_key(hash)
    }

    /// Drop expired entries (TTL) so a late deposit becomes eligible again.
    pub fn evict_expired(&mut self, now: Instant) {
        let ttl = self.cfg.negative_retry_ttl;
        self.entries
            .retain(|_, e| now.saturating_duration_since(e.inserted_at) < ttl);
    }

    pub fn remove(&mut self, hash: &[u8; 32]) {
        self.entries.remove(hash);
    }

    /// Terminal on-chain states (approved / cancelled / executed) stop retry work.
    pub fn record_terminal(&mut self, hash: &[u8; 32]) {
        self.entries.remove(hash);
    }

    /// A newly observed WithdrawSubmit (or other state trigger) may retry immediately.
    pub fn invalidate_for_immediate_retry(&mut self, hash: &[u8; 32]) {
        self.entries.remove(hash);
    }

    pub fn should_verify(&mut self, hash: &[u8; 32], now: Instant) -> VerifyDecision {
        self.evict_expired(now);
        match self.entries.get(hash) {
            None => VerifyDecision::Verify,
            Some(e) if now >= e.next_retry => VerifyDecision::Verify,
            Some(_) => VerifyDecision::Suppress,
        }
    }

    /// Record a negative or transient-failed verification and schedule the next attempt.
    pub fn record_negative(&mut self, hash: [u8; 32], now: Instant, seed: u64) {
        self.evict_expired(now);
        let attempts = self
            .entries
            .get(&hash)
            .map(|e| e.attempts.saturating_add(1))
            .unwrap_or(0);
        let delay = jittered_exponential_backoff(
            attempts,
            self.cfg.negative_retry_initial,
            self.cfg.negative_retry_max,
            self.cfg.jitter_bps,
            seed ^ (attempts as u64),
        );
        let inserted_at = self
            .entries
            .get(&hash)
            .map(|e| e.inserted_at)
            .unwrap_or(now);
        self.ensure_capacity(now);
        self.entries.insert(
            hash,
            NegativeEntry {
                attempts,
                next_retry: now + delay,
                inserted_at,
            },
        );
    }

    fn ensure_capacity(&mut self, now: Instant) {
        if self.entries.len() < self.max_size {
            return;
        }
        // Prefer expired, then earliest inserted_at (FIFO) under size pressure.
        // Evicting by next_retry would re-queue the soonest-due hashes as unknown
        // next cycle and starve older entries.
        self.evict_expired(now);
        if self.entries.len() < self.max_size {
            return;
        }
        while self.entries.len() >= self.max_size && !self.entries.is_empty() {
            let victim = self
                .entries
                .iter()
                .min_by_key(|(_, e)| e.inserted_at)
                .map(|(h, _)| *h);
            if let Some(h) = victim {
                self.entries.remove(&h);
            } else {
                break;
            }
        }
    }
}

/// Shared enumeration + event-poll source-verify budget for one writer cycle
/// (`WRITER_MAX_VERIFY_PER_CYCLE`, INV-OP-W4).
#[derive(Debug, Clone)]
pub struct CycleVerifyBudget {
    used: usize,
    cap: usize,
}

impl CycleVerifyBudget {
    pub fn new(cap: usize) -> Self {
        Self { used: 0, cap }
    }

    pub fn reset(&mut self) {
        self.used = 0;
    }

    /// Consume one verify slot. Returns `false` when the cycle cap is exhausted.
    pub fn try_acquire(&mut self) -> bool {
        if self.used >= self.cap {
            false
        } else {
            self.used += 1;
            true
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::poll_config::WriterScheduleConfig;
    use std::time::Duration;

    fn cfg() -> WriterScheduleConfig {
        WriterScheduleConfig {
            poll_interval: Duration::from_secs(5),
            rpc_backoff_initial: Duration::from_secs(2),
            rpc_backoff_max: Duration::from_secs(60),
            jitter_bps: 0,
            negative_retry_initial: Duration::from_millis(50),
            negative_retry_max: Duration::from_millis(200),
            negative_retry_ttl: Duration::from_secs(2),
            negative_retry_cache_size: 3,
            max_verify_per_cycle: 64,
        }
    }

    #[test]
    fn unknown_hash_is_verified() {
        let mut s = NegativeVerifySchedule::new(cfg());
        let h = [1u8; 32];
        assert_eq!(s.should_verify(&h, Instant::now()), VerifyDecision::Verify);
    }

    #[test]
    fn negative_then_suppressed_until_backoff() {
        let mut s = NegativeVerifySchedule::new(cfg());
        let h = [2u8; 32];
        let t0 = Instant::now();
        s.record_negative(h, t0, 1);
        assert_eq!(s.should_verify(&h, t0), VerifyDecision::Suppress);
        assert_eq!(
            s.should_verify(&h, t0 + Duration::from_millis(60)),
            VerifyDecision::Verify
        );
    }

    #[test]
    fn ttl_expires_entry_for_late_deposit() {
        let mut s = NegativeVerifySchedule::new(cfg());
        let h = [3u8; 32];
        let t0 = Instant::now();
        s.record_negative(h, t0, 1);
        s.evict_expired(t0 + Duration::from_secs(3));
        assert!(!s.contains(&h));
        assert_eq!(
            s.should_verify(&h, t0 + Duration::from_secs(3)),
            VerifyDecision::Verify
        );
    }

    #[test]
    fn terminal_evicts() {
        let mut s = NegativeVerifySchedule::new(cfg());
        let h = [4u8; 32];
        s.record_negative(h, Instant::now(), 1);
        s.record_terminal(&h);
        assert!(!s.contains(&h));
    }

    #[test]
    fn event_invalidation_retries_immediately() {
        let mut s = NegativeVerifySchedule::new(cfg());
        let h = [5u8; 32];
        let t0 = Instant::now();
        s.record_negative(h, t0, 1);
        s.invalidate_for_immediate_retry(&h);
        assert_eq!(s.should_verify(&h, t0), VerifyDecision::Verify);
    }

    #[test]
    fn cache_size_is_bounded() {
        let mut s = NegativeVerifySchedule::new(cfg());
        let t0 = Instant::now();
        s.record_negative([1u8; 32], t0, 1);
        s.record_negative([2u8; 32], t0, 2);
        s.record_negative([3u8; 32], t0, 3);
        s.record_negative([4u8; 32], t0, 4);
        assert!(s.len() <= 3);
        assert!(!s.contains(&[1u8; 32]) || s.len() == 3);
        assert!(s.contains(&[4u8; 32]));
    }

    #[test]
    fn full_cache_evicts_earliest_inserted_not_earliest_retry() {
        let mut s = NegativeVerifySchedule::new(cfg());
        let t0 = Instant::now();
        // Bump hash 1 so its next_retry is later than hashes inserted after it.
        s.record_negative([1u8; 32], t0, 1);
        s.record_negative([1u8; 32], t0, 1);
        s.record_negative([2u8; 32], t0 + Duration::from_millis(1), 2);
        s.record_negative([3u8; 32], t0 + Duration::from_millis(2), 3);
        s.record_negative([4u8; 32], t0 + Duration::from_millis(3), 4);
        assert_eq!(s.len(), 3);
        assert!(
            !s.contains(&[1u8; 32]),
            "FIFO by inserted_at must evict hash 1 even though its next_retry is later"
        );
        assert!(s.contains(&[4u8; 32]));
    }

    #[test]
    fn cycle_verify_budget_caps_and_resets() {
        let mut b = CycleVerifyBudget::new(2);
        assert!(b.try_acquire());
        assert!(b.try_acquire());
        assert!(!b.try_acquire());
        b.reset();
        assert!(b.try_acquire());
        assert!(b.try_acquire());
        assert!(!b.try_acquire());
    }
}
