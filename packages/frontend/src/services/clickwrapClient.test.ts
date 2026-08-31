import { describe, it, expect, vi, beforeEach } from 'vitest'
import { NETWORK_API_VALUES } from '@plasticdigits/cl8y-clickwrap'
import {
  ClickwrapGateError,
  getClickwrapClient,
  requireSignedLatest,
  resetClickwrapClientForTests,
} from './clickwrapClient'
import { BRIDGE_CLICKWRAP_PROPERTY } from '../utils/clickwrap'

const getSignatureStatus = vi.fn()

vi.mock('@plasticdigits/cl8y-clickwrap', async (importOriginal) => {
  const actual = await importOriginal<typeof import('@plasticdigits/cl8y-clickwrap')>()
  return {
    ...actual,
    createClient: vi.fn(() => ({
      apiBaseUrl: 'https://api.terms.cl8y.com',
      termsBaseUrl: 'https://terms.cl8y.com',
      getSignatureStatus,
      getTermsLatest: vi.fn(),
      getTermsContent: vi.fn(),
      submitWallet: vi.fn(),
      submitTelegram: vi.fn(),
    })),
  }
})

describe('requireSignedLatest', () => {
  beforeEach(() => {
    resetClickwrapClientForTests()
    getSignatureStatus.mockReset()
  })

  it('resolves when signed_latest is true', async () => {
    getSignatureStatus.mockResolvedValue({
      property: BRIDGE_CLICKWRAP_PROPERTY,
      latest_version: '1',
      signed_latest: true,
      signed_version: '1',
      signed_at: '2026-01-01T00:00:00Z',
    })
    await requireSignedLatest('EVM', '0xabc')
    expect(getSignatureStatus).toHaveBeenCalledWith(
      BRIDGE_CLICKWRAP_PROPERTY,
      NETWORK_API_VALUES.EVM,
      '0xabc',
    )
  })

  it('throws unsigned when signed_latest is false', async () => {
    getSignatureStatus.mockResolvedValue({
      property: BRIDGE_CLICKWRAP_PROPERTY,
      latest_version: '1',
      signed_latest: false,
      signed_version: null,
      signed_at: null,
    })
    await expect(requireSignedLatest('TerraClassic', 'terra1abc')).rejects.toBeInstanceOf(
      ClickwrapGateError,
    )
    await expect(requireSignedLatest('TerraClassic', 'terra1abc')).rejects.toMatchObject({
      code: 'unsigned',
    })
  })

  it('fails closed when the Legal API throws', async () => {
    getSignatureStatus.mockRejectedValue(new Error('CORS blocked'))
    await expect(requireSignedLatest('Solana', 'SoL111')).rejects.toMatchObject({
      code: 'status-error',
    })
  })

  it('fails closed for an empty account', async () => {
    await expect(requireSignedLatest('EVM', '  ')).rejects.toMatchObject({ code: 'unsigned' })
    expect(getSignatureStatus).not.toHaveBeenCalled()
  })

  it('shares one client instance', () => {
    const a = getClickwrapClient()
    const b = getClickwrapClient()
    expect(a).toBe(b)
  })
})
