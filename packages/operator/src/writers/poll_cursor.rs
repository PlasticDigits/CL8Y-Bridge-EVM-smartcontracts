//! Contiguous EVM writer event-poll cursor (GL-138, INV-OP-W2).
//!
//! The cursor advances only through the last contiguous successful `eth_getLogs`
//! chunk. A failed range is retried before later ranges. The first-poll lookback
//! start is sticky so a persistent log-query failure cannot skip blocks by
//! recomputing `head - lookback` every cycle.

use std::time::{Duration, Instant};

/// Inclusive `[from_block, to_block]` planned for this poll cycle.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct PollRange {
    pub from_block: u64,
    pub to_block: u64,
    /// True only when this process first establishes the sticky lookback start.
    pub is_first_poll: bool,
}

/// In-memory writer event cursor. Restart-safe: a process restart re-looks-back
/// (enumeration remains the durable discovery path).
#[derive(Debug, Clone)]
pub struct EventPollCursor {
    /// Last block whose logs were observed (contiguous success). `0` = none yet.
    pub last_polled_block: u64,
    /// First-poll start, retained across failed initial chunks.
    sticky_from_block: Option<u64>,
    pub consecutive_log_failures: u32,
    backoff_until: Option<Instant>,
    first_poll_logged: bool,
}

impl Default for EventPollCursor {
    fn default() -> Self {
        Self::new()
    }
}

impl EventPollCursor {
    pub fn new() -> Self {
        Self {
            last_polled_block: 0,
            sticky_from_block: None,
            consecutive_log_failures: 0,
            backoff_until: None,
            first_poll_logged: false,
        }
    }

    #[allow(dead_code)]
    pub fn sticky_from_block(&self) -> Option<u64> {
        self.sticky_from_block
    }

    pub fn backoff_until(&self) -> Option<Instant> {
        self.backoff_until
    }

    pub fn in_backoff(&self, now: Instant) -> bool {
        self.backoff_until.map(|t| now < t).unwrap_or(false)
    }

    /// Head rewound below the cursor (Anvil restart / deep reorg).
    pub fn detect_reset(&self, current_block: u64) -> bool {
        if current_block < self.last_polled_block {
            return true;
        }
        if let Some(sticky) = self.sticky_from_block {
            if current_block < sticky {
                return true;
            }
        }
        false
    }

    pub fn reset(&mut self) {
        *self = Self::new();
    }

    /// Plan the next inclusive scan range, or `None` if there is nothing to do
    /// (backoff, or head has not advanced past the cursor).
    pub fn plan_range(
        &mut self,
        current_block: u64,
        lookback: u64,
        now: Instant,
    ) -> Option<PollRange> {
        if self.in_backoff(now) {
            return None;
        }
        if current_block <= self.last_polled_block {
            return None;
        }

        if self.last_polled_block == 0 {
            let is_first_poll = self.sticky_from_block.is_none();
            let from = *self
                .sticky_from_block
                .get_or_insert(current_block.saturating_sub(lookback));
            Some(PollRange {
                from_block: from,
                to_block: current_block,
                is_first_poll,
            })
        } else {
            Some(PollRange {
                from_block: self.last_polled_block.saturating_add(1),
                to_block: current_block,
                is_first_poll: false,
            })
        }
    }

    pub fn take_first_poll_log(&mut self) -> bool {
        if !self.first_poll_logged {
            self.first_poll_logged = true;
            true
        } else {
            false
        }
    }

    /// Advance through a successful chunk end. Never skips: caller must pass the
    /// chunk that was just observed, in order.
    pub fn on_chunk_success(&mut self, chunk_end: u64) {
        self.last_polled_block = chunk_end;
        self.consecutive_log_failures = 0;
        self.backoff_until = None;
    }

    /// All endpoints failed this chunk. Cursor stays put; retries wait `backoff`.
    pub fn on_chunk_failure(&mut self, now: Instant, backoff: Duration) {
        self.consecutive_log_failures = self.consecutive_log_failures.saturating_add(1);
        self.backoff_until = Some(now + backoff);
    }
}

/// Inclusive chunk bounds covering `[from, to]` with `chunk_size` blocks each.
pub fn chunk_bounds(from: u64, to: u64, chunk_size: u64) -> Vec<(u64, u64)> {
    if chunk_size == 0 || from > to {
        return Vec::new();
    }
    let mut out = Vec::new();
    let mut start = from;
    loop {
        let end = start.saturating_add(chunk_size - 1).min(to);
        out.push((start, end));
        if end >= to {
            break;
        }
        start = end.saturating_add(1);
        if start == 0 {
            // overflow wrap — stop rather than looping
            break;
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn now() -> Instant {
        Instant::now()
    }

    #[test]
    fn first_poll_lookback_is_sticky_across_head_growth() {
        let mut c = EventPollCursor::new();
        let t = now();
        let r1 = c.plan_range(10_000, 5_000, t).unwrap();
        assert_eq!(r1.from_block, 5_000);
        assert_eq!(r1.to_block, 10_000);
        assert!(r1.is_first_poll);

        // First chunk fails — cursor stays at 0, sticky remains 5000.
        c.on_chunk_failure(t, Duration::from_secs(0));
        // Clear backoff for the next plan (zero-duration backoff may still be "now").
        c.backoff_until = None;

        let r2 = c.plan_range(10_050, 5_000, now()).unwrap();
        assert_eq!(
            r2.from_block, 5_000,
            "must not recompute lookback from the new head"
        );
        assert_eq!(r2.to_block, 10_050);
        assert!(!r2.is_first_poll);
        assert_eq!(c.last_polled_block, 0);
    }

    #[test]
    fn first_poll_log_emitted_once() {
        let mut c = EventPollCursor::new();
        let r = c.plan_range(100, 50, now()).unwrap();
        assert!(r.is_first_poll);
        assert!(c.take_first_poll_log());
        assert!(!c.take_first_poll_log());
    }

    #[test]
    fn partial_chunk_success_retries_failed_chunk() {
        let mut c = EventPollCursor::new();
        let t = now();
        let r = c.plan_range(250, 150, t).unwrap();
        assert_eq!(r.from_block, 100);
        c.on_chunk_success(199);
        assert_eq!(c.last_polled_block, 199);
        c.on_chunk_failure(t, Duration::from_secs(0));
        c.backoff_until = None;
        let r2 = c.plan_range(250, 150, now()).unwrap();
        assert_eq!(r2.from_block, 200);
        assert_eq!(r2.to_block, 250);
    }

    #[test]
    fn no_new_blocks_returns_none() {
        let mut c = EventPollCursor::new();
        c.on_chunk_success(100);
        assert!(c.plan_range(100, 5_000, now()).is_none());
    }

    #[test]
    fn backoff_skips_planning() {
        let mut c = EventPollCursor::new();
        let t = now();
        c.on_chunk_failure(t, Duration::from_secs(60));
        assert!(c.in_backoff(t));
        assert!(c.plan_range(10_000, 5_000, t).is_none());
    }

    #[test]
    fn reset_on_rewound_head() {
        let mut c = EventPollCursor::new();
        c.on_chunk_success(500);
        assert!(c.detect_reset(10));
        c.reset();
        assert_eq!(c.last_polled_block, 0);
        assert!(c.sticky_from_block().is_none());
    }

    #[test]
    fn chunk_bounds_split_and_tail() {
        assert_eq!(chunk_bounds(100, 250, 100), vec![(100, 199), (200, 250)]);
        assert_eq!(chunk_bounds(5, 5, 100), vec![(5, 5)]);
        assert!(chunk_bounds(10, 5, 100).is_empty());
        assert!(chunk_bounds(1, 10, 0).is_empty());
    }

    #[test]
    fn recovery_scans_failed_range_before_new_head() {
        let mut c = EventPollCursor::new();
        let t = now();
        let _ = c.plan_range(1_000, 1_000, t); // sticky from 0
        c.on_chunk_success(499); // first chunk 0-499 ok, 500-1000 not yet
                                 // fail at 500
        c.on_chunk_failure(t, Duration::from_secs(0));
        c.backoff_until = None;
        let r = c.plan_range(2_000, 1_000, now()).unwrap();
        assert_eq!(r.from_block, 500, "must resume at first failed chunk");
        assert_eq!(r.to_block, 2_000);
    }
}
