//! Terra withdrawal list pagination helpers (GL-139 / INV-TC-AW5).
//!
//! Contract list queries cap pages at [`WITHDRAW_LIST_MAX_PAGE`]. The canceler
//! default used to request 50 and treat `len < 50` as EOF, which drops later
//! approvals on both `pending_withdrawals` fallback and `active_withdrawals`
//! once more than 30 rows are active.

/// Must match `bridge::active_withdraw::WITHDRAW_LIST_MAX_LIMIT`.
pub const WITHDRAW_LIST_MAX_PAGE: u32 = 30;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum PageAdvance {
    Continue(String),
    Exhausted,
}

pub fn clamp_page_size(requested: u32) -> u32 {
    requested.clamp(1, WITHDRAW_LIST_MAX_PAGE)
}

pub fn advance_withdraw_list_page(
    page_len: usize,
    effective_limit: u32,
    next_start_after: Option<String>,
    has_next_field: bool,
    last_hash: Option<String>,
) -> PageAdvance {
    if let Some(cursor) = next_start_after {
        if !cursor.is_empty() {
            return PageAdvance::Continue(cursor);
        }
    }
    if has_next_field {
        return PageAdvance::Exhausted;
    }
    if page_len == 0 || page_len < effective_limit as usize {
        return PageAdvance::Exhausted;
    }
    match last_hash {
        Some(h) if !h.is_empty() => PageAdvance::Continue(h),
        _ => PageAdvance::Exhausted,
    }
}

pub fn is_canceler_candidate(approved: bool, cancelled: bool, executed: bool) -> bool {
    approved && !cancelled && !executed
}

#[cfg(test)]
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SoakStats {
    pub processed: u32,
    pub candidates: u32,
    pub skipped: u32,
    pub pages_fetched: u32,
}

#[cfg(test)]
pub fn soak_canceler_pages(
    pages: &[Vec<(bool, bool, bool, String)>],
    effective_limit: u32,
    use_cursor_field: bool,
) -> SoakStats {
    let mut processed = 0u32;
    let mut candidates = 0u32;
    let mut skipped = 0u32;
    let mut pages_fetched = 0u32;
    let mut idx = 0usize;
    loop {
        if idx >= pages.len() {
            break;
        }
        let page = &pages[idx];
        pages_fetched += 1;
        let last_hash = page.last().map(|e| e.3.clone());
        let is_last_synthetic = idx + 1 == pages.len();
        let next_start_after = if use_cursor_field && !is_last_synthetic {
            last_hash.clone()
        } else {
            None
        };
        for (approved, cancelled, executed, _) in page {
            processed += 1;
            if is_canceler_candidate(*approved, *cancelled, *executed) {
                candidates += 1;
            } else {
                skipped += 1;
            }
        }
        match advance_withdraw_list_page(
            page.len(),
            effective_limit,
            next_start_after,
            use_cursor_field,
            last_hash,
        ) {
            PageAdvance::Continue(_) => idx += 1,
            PageAdvance::Exhausted => break,
        }
    }
    SoakStats {
        processed,
        candidates,
        skipped,
        pages_fetched,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn hash(n: u32) -> String {
        format!("h{n}")
    }

    fn prod_pages() -> Vec<Vec<(bool, bool, bool, String)>> {
        let mut rows = Vec::new();
        for i in 0..95u32 {
            rows.push((true, false, true, hash(i)));
        }
        for i in 95..106u32 {
            rows.push((true, false, false, hash(i)));
        }
        rows.chunks(30).map(|c| c.to_vec()).collect()
    }

    #[test]
    fn default_fifty_without_cursor_misses_production_approvals() {
        let pages = prod_pages();
        let stats = soak_canceler_pages(&pages, 50, false);
        assert_eq!(stats.pages_fetched, 1);
        assert_eq!(stats.candidates, 0);
    }

    #[test]
    fn clamped_thirty_sees_all_production_cancel_candidates() {
        let pages = prod_pages();
        let stats = soak_canceler_pages(&pages, 30, false);
        assert_eq!(stats.pages_fetched, 4);
        assert_eq!(stats.processed, 106);
        assert_eq!(stats.candidates, 11);
        assert_eq!(stats.skipped, 95);
    }

    #[test]
    fn cursor_repairs_oversized_request() {
        let pages = prod_pages();
        let stats = soak_canceler_pages(&pages, 50, true);
        assert_eq!(stats.candidates, 11);
        assert_eq!(stats.pages_fetched, 4);
    }

    #[test]
    fn active_index_soak_ignores_terminal_history_size() {
        let active: Vec<(bool, bool, bool, String)> =
            (0..11u32).map(|i| (true, false, false, hash(i))).collect();
        let stats = soak_canceler_pages(&[active], 30, true);
        assert_eq!(stats.pages_fetched, 1);
        assert_eq!(stats.processed, 11);
        assert_eq!(stats.candidates, 11);
    }
}
