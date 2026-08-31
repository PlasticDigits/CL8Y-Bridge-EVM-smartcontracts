import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { BridgeTermsGate } from './BridgeTermsGate'
import { useBridgeClickwrapAccount } from '../../hooks/useBridgeClickwrapAccount'
import { BRIDGE_CLICKWRAP_APP_NAME, BRIDGE_CLICKWRAP_PROPERTY } from '../../utils/clickwrap'

const getSignatureStatus = vi.fn()
const getTermsLatest = vi.fn()

vi.mock('../../hooks/useBridgeClickwrapAccount', () => ({
  useBridgeClickwrapAccount: vi.fn(),
}))

vi.mock('../../services/clickwrapClient', () => ({
  getClickwrapClient: () => ({
    apiBaseUrl: 'https://api.terms.cl8y.com',
    termsBaseUrl: 'https://terms.cl8y.com',
    getSignatureStatus,
    getTermsLatest,
    getTermsContent: vi.fn(),
    submitWallet: vi.fn(),
    submitTelegram: vi.fn(),
  }),
}))

const mockAccount = vi.mocked(useBridgeClickwrapAccount)

function signedStatus(signedLatest: boolean) {
  return {
    property: BRIDGE_CLICKWRAP_PROPERTY,
    latest_version: 'v1',
    signed_latest: signedLatest,
    signed_version: signedLatest ? 'v1' : null,
    signed_at: signedLatest ? '2026-01-01T00:00:00Z' : null,
  }
}

const latestTerms = {
  property: BRIDGE_CLICKWRAP_PROPERTY,
  version_label: 'v1',
  effective_date: '2026-01-01',
  content_sha256: 'abc',
  published_at: '2026-01-01T00:00:00Z',
  sign_urls: {
    telegram: 'https://terms.cl8y.com/sign/telegram?property=bridge.cl8y.com',
    evm: 'https://terms.cl8y.com/sign/evm?property=bridge.cl8y.com',
    terra_classic: 'https://terms.cl8y.com/sign/terra-classic?property=bridge.cl8y.com',
    solana: 'https://terms.cl8y.com/sign/solana?property=bridge.cl8y.com',
  },
}

describe('BridgeTermsGate', () => {
  beforeEach(() => {
    getSignatureStatus.mockReset()
    getTermsLatest.mockReset()
    getTermsLatest.mockResolvedValue(latestTerms)
    mockAccount.mockReturnValue({ network: 'EVM', account: null })
    vi.stubGlobal('location', { ...window.location, href: 'https://bridge.cl8y.com/' })
  })

  it('renders children when no account is connected (connect UX stays usable)', () => {
    mockAccount.mockReturnValue({ network: 'EVM', account: null })
    render(
      <BridgeTermsGate chainKind="evm">
        <button type="button">Bridge from EVM</button>
      </BridgeTermsGate>,
    )
    expect(screen.getByRole('button', { name: 'Bridge from EVM' })).toBeInTheDocument()
    expect(screen.queryByTestId('bridge-terms-gate')).not.toBeInTheDocument()
    expect(getSignatureStatus).not.toHaveBeenCalled()
  })

  it('renders children when signed_latest is true', async () => {
    mockAccount.mockReturnValue({ network: 'EVM', account: '0xabc' })
    getSignatureStatus.mockResolvedValue(signedStatus(true))
    render(
      <BridgeTermsGate chainKind="evm">
        <button type="button">Bridge from EVM</button>
      </BridgeTermsGate>,
    )
    expect(await screen.findByRole('button', { name: 'Bridge from EVM' })).toBeInTheDocument()
  })

  it('hides mutative children and shows Accept when unsigned', async () => {
    mockAccount.mockReturnValue({ network: 'EVM', account: '0xabc' })
    getSignatureStatus.mockResolvedValue(signedStatus(false))
    render(
      <BridgeTermsGate chainKind="evm">
        <button type="button">Bridge from EVM</button>
      </BridgeTermsGate>,
    )
    expect(await screen.findByRole('button', { name: 'Accept Terms' })).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Bridge from EVM' })).not.toBeInTheDocument()
    expect(getSignatureStatus).toHaveBeenCalledWith(
      BRIDGE_CLICKWRAP_PROPERTY,
      'EVM',
      '0xabc',
    )
  })

  it('fails closed on status errors', async () => {
    mockAccount.mockReturnValue({ network: 'TerraClassic', account: 'terra1abc' })
    getSignatureStatus.mockRejectedValue(new Error('CORS'))
    render(
      <BridgeTermsGate chainKind="cosmos">
        <button type="button">Bridge from Terra</button>
      </BridgeTermsGate>,
    )
    expect(await screen.findByRole('alert')).toHaveTextContent(/Unable to verify terms acceptance/)
    expect(screen.queryByRole('button', { name: 'Bridge from Terra' })).not.toBeInTheDocument()
  })

  it('builds portal URL with property, network path, redirect_uri, app_name, and account', async () => {
    mockAccount.mockReturnValue({ network: 'EVM', account: '0xabc' })
    getSignatureStatus.mockResolvedValue(signedStatus(false))
    const assign = vi.fn()
    const hrefHolder = { href: 'https://bridge.cl8y.com/transfer/0xhash' }
    vi.stubGlobal('location', hrefHolder)
    Object.defineProperty(window, 'location', {
      configurable: true,
      value: {
        get href() {
          return hrefHolder.href
        },
        set href(next: string) {
          assign(next)
          hrefHolder.href = next
        },
      },
    })

    render(
      <BridgeTermsGate chainKind="evm">
        <button type="button">Bridge from EVM</button>
      </BridgeTermsGate>,
    )
    await userEvent.click(await screen.findByRole('button', { name: 'Accept Terms' }))
    await waitFor(() => expect(assign).toHaveBeenCalled())
    const url = new URL(assign.mock.calls[0]![0] as string)
    expect(url.origin).toBe('https://terms.cl8y.com')
    expect(url.pathname).toBe('/sign/evm')
    expect(url.searchParams.get('property')).toBe(BRIDGE_CLICKWRAP_PROPERTY)
    expect(url.searchParams.get('app_name')).toBe(BRIDGE_CLICKWRAP_APP_NAME)
    expect(url.searchParams.get('account')).toBe('0xabc')
    expect(url.searchParams.get('redirect_uri')).toContain('https://bridge.cl8y.com/transfer/0xhash')
  })

  it('re-checks status on window focus and unblocks when signed', async () => {
    mockAccount.mockReturnValue({ network: 'Solana', account: 'SoL111' })
    getSignatureStatus
      .mockResolvedValueOnce(signedStatus(false))
      .mockResolvedValueOnce(signedStatus(true))
    render(
      <BridgeTermsGate chainKind="solana">
        <button type="button">Bridge from Solana</button>
      </BridgeTermsGate>,
    )
    expect(await screen.findByRole('button', { name: 'Accept Terms' })).toBeInTheDocument()
    window.dispatchEvent(new Event('focus'))
    expect(await screen.findByRole('button', { name: 'Bridge from Solana' })).toBeInTheDocument()
  })
})
