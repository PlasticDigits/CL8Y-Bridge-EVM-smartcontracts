import { describe, it, expect, vi, beforeEach } from 'vitest'
import { renderHook } from '@testing-library/react'
import { useSignatureStatus } from '@plasticdigits/cl8y-clickwrap/react'
import { useBridgeClickwrapGate } from './useBridgeClickwrapGate'
import { useBridgeClickwrapAccount } from './useBridgeClickwrapAccount'

vi.mock('@plasticdigits/cl8y-clickwrap/react', () => ({
  useSignatureStatus: vi.fn(),
}))

vi.mock('./useBridgeClickwrapAccount', () => ({
  useBridgeClickwrapAccount: vi.fn(),
}))

vi.mock('../services/clickwrapClient', () => ({
  getClickwrapClient: () => ({ apiBaseUrl: 'https://api.terms.cl8y.com' }),
}))

const mockStatus = vi.mocked(useSignatureStatus)
const mockAccount = vi.mocked(useBridgeClickwrapAccount)

describe('useBridgeClickwrapGate', () => {
  beforeEach(() => {
    mockAccount.mockReturnValue({ network: 'EVM', account: '0xabc' })
    mockStatus.mockReturnValue({
      status: null,
      loading: false,
      error: null,
      isSigned: false,
      refresh: vi.fn(),
    })
  })

  it('does not allow mutative actions until signed_latest', () => {
    const { result } = renderHook(() => useBridgeClickwrapGate('evm'))
    expect(result.current.allowsMutative).toBe(false)
  })

  it('allows mutative actions when signed', () => {
    mockStatus.mockReturnValue({
      status: {
        property: 'bridge.cl8y.com',
        latest_version: '1',
        signed_latest: true,
        signed_version: '1',
        signed_at: '2026-01-01T00:00:00Z',
      },
      loading: false,
      error: null,
      isSigned: true,
      refresh: vi.fn(),
    })
    const { result } = renderHook(() => useBridgeClickwrapGate('evm'))
    expect(result.current.allowsMutative).toBe(true)
  })

  it('fails closed on status error even if a stale isSigned flag were true', () => {
    mockStatus.mockReturnValue({
      status: null,
      loading: false,
      error: new Error('network'),
      isSigned: true,
      refresh: vi.fn(),
    })
    const { result } = renderHook(() => useBridgeClickwrapGate('evm'))
    expect(result.current.allowsMutative).toBe(false)
  })

  it('does not allow mutative actions without an account', () => {
    mockAccount.mockReturnValue({ network: 'EVM', account: null })
    mockStatus.mockReturnValue({
      status: {
        property: 'bridge.cl8y.com',
        latest_version: '1',
        signed_latest: true,
        signed_version: '1',
        signed_at: '2026-01-01T00:00:00Z',
      },
      loading: false,
      error: null,
      isSigned: true,
      refresh: vi.fn(),
    })
    const { result } = renderHook(() => useBridgeClickwrapGate('evm'))
    expect(result.current.allowsMutative).toBe(false)
  })
})
