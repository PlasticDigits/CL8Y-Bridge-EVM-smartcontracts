import { beforeEach, describe, expect, it, vi } from 'vitest'
import { fetchTerraWithdrawHashes } from './hashMonitor'
import * as lcdClient from './lcdClient'

vi.mock('./lcdClient', () => ({
  queryContract: vi.fn(),
}))

function b64Hash(n: number): string {
  const bytes = new Uint8Array(32)
  bytes[31] = n
  return btoa(String.fromCharCode(...bytes))
}

function row(
  n: number,
  flags: { approved?: boolean; cancelled?: boolean; executed?: boolean }
) {
  return {
    xchain_hash_id: b64Hash(n),
    submitted_at: 1_700_000_000 + n,
    approved: flags.approved ?? false,
    cancelled: flags.cancelled ?? false,
    executed: flags.executed ?? false,
  }
}

describe('fetchTerraWithdrawHashes (INV-FE-TC-AW1)', () => {
  beforeEach(() => {
    vi.clearAllMocks()
  })

  it('queries pending_withdrawals, never active_withdrawals', async () => {
    vi.mocked(lcdClient.queryContract).mockResolvedValue({
      withdrawals: [row(1, { executed: true, approved: true })],
    })

    const entries = await fetchTerraWithdrawHashes(
      ['http://lcd'],
      'terra1bridge',
      'columbus-5',
      'Terra Classic'
    )

    expect(entries).toHaveLength(1)
    expect(entries[0]!.executed).toBe(true)
    expect(lcdClient.queryContract).toHaveBeenCalledTimes(1)
    const query = vi.mocked(lcdClient.queryContract).mock.calls[0]![2] as {
      pending_withdrawals?: unknown
      active_withdrawals?: unknown
    }
    expect(query.pending_withdrawals).toBeDefined()
    expect(query.active_withdrawals).toBeUndefined()
  })

  it('keeps executed and cancelled rows in the historical list', async () => {
    vi.mocked(lcdClient.queryContract).mockResolvedValue({
      withdrawals: [
        row(1, { executed: true, approved: true }),
        row(2, { cancelled: true, approved: true }),
        row(3, { approved: true }),
      ],
    })

    const entries = await fetchTerraWithdrawHashes(
      ['http://lcd'],
      'terra1bridge',
      'columbus-5',
      'Terra Classic'
    )

    expect(entries.map((e) => ({ executed: e.executed, cancelled: e.cancelled }))).toEqual([
      { executed: true, cancelled: false },
      { executed: false, cancelled: true },
      { executed: false, cancelled: false },
    ])
  })

  it('continues past a contract-capped page of 30 via next_start_after', async () => {
    const page1 = Array.from({ length: 30 }, (_, i) => row(i, { executed: true, approved: true }))
    const page2 = [
      row(30, { executed: true, approved: true }),
      row(31, { approved: true }),
    ]
    vi.mocked(lcdClient.queryContract)
      .mockResolvedValueOnce({
        withdrawals: page1,
        next_start_after: page1[29]!.xchain_hash_id,
      })
      .mockResolvedValueOnce({ withdrawals: page2 })

    const entries = await fetchTerraWithdrawHashes(
      ['http://lcd'],
      'terra1bridge',
      'columbus-5',
      'Terra Classic'
    )

    expect(entries).toHaveLength(32)
    expect(entries.filter((e) => e.executed)).toHaveLength(31)
    expect(lcdClient.queryContract).toHaveBeenCalledTimes(2)
    const secondQuery = vi.mocked(lcdClient.queryContract).mock.calls[1]![2] as {
      pending_withdrawals: { start_after?: string; limit: number }
    }
    expect(secondQuery.pending_withdrawals.limit).toBe(30)
    expect(secondQuery.pending_withdrawals.start_after).toBe(page1[29]!.xchain_hash_id)
  })

  it('does not stop after 30 rows when the caller requested 50 (pre-fix bug)', async () => {
    const page1 = Array.from({ length: 30 }, (_, i) => row(i, { executed: true, approved: true }))
    vi.mocked(lcdClient.queryContract)
      .mockResolvedValueOnce({
        withdrawals: page1,
        next_start_after: page1[29]!.xchain_hash_id,
      })
      .mockResolvedValueOnce({
        withdrawals: [row(30, { executed: true, approved: true })],
      })

    const entries = await fetchTerraWithdrawHashes(
      ['http://lcd'],
      'terra1bridge',
      'columbus-5',
      'Terra Classic',
      { limit: 50 }
    )

    expect(entries).toHaveLength(31)
    const firstLimit = (
      vi.mocked(lcdClient.queryContract).mock.calls[0]![2] as {
        pending_withdrawals: { limit: number }
      }
    ).pending_withdrawals.limit
    expect(firstLimit).toBe(30)
  })
})
