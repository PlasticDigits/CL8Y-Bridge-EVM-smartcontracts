import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { WalletButton } from './WalletButton'

vi.mock('../lib/sounds', () => ({
  sounds: { playButtonPress: vi.fn() },
}))

vi.mock('../hooks/useWallet', () => ({
  useWallet: vi.fn(),
}))

import { useWallet } from '../hooks/useWallet'

const mockUseWallet = vi.mocked(useWallet)

function disconnected(overrides: Record<string, unknown> = {}) {
  return {
    connected: false,
    connecting: false,
    address: null,
    chainId: null,
    luncBalance: '0',
    disconnect: vi.fn(),
    showWalletModal: false,
    setShowWalletModal: vi.fn(),
    cancelConnection: vi.fn(),
    ...overrides,
  }
}

describe('WalletButton (GL-137)', () => {
  beforeEach(() => {
    vi.clearAllMocks()
  })

  it('exposes Connect Terra Wallet as the accessible name while disconnected', () => {
    mockUseWallet.mockReturnValue(disconnected() as unknown as ReturnType<typeof useWallet>)
    render(<WalletButton />)
    const btn = screen.getByRole('button', { name: 'Connect Terra Wallet' })
    expect(btn).toBeEnabled()
    expect(btn).toHaveAttribute('aria-haspopup', 'dialog')
    expect(btn).toHaveAttribute('aria-expanded', 'false')
    expect(btn).toHaveAttribute('data-testid', 'connect-terra-wallet')
  })

  it('opens the modal on first tap and does not disable the CTA', async () => {
    const setShowWalletModal = vi.fn()
    mockUseWallet.mockReturnValue(
      disconnected({ setShowWalletModal }) as unknown as ReturnType<typeof useWallet>
    )
    const user = userEvent.setup()
    render(<WalletButton />)
    await user.click(screen.getByRole('button', { name: 'Connect Terra Wallet' }))
    expect(setShowWalletModal).toHaveBeenCalledWith(true)
  })

  it('toggles the open modal closed on a second tap (no duplicate WC sessions)', async () => {
    const setShowWalletModal = vi.fn()
    mockUseWallet.mockReturnValue(
      disconnected({ showWalletModal: true, setShowWalletModal }) as unknown as ReturnType<typeof useWallet>
    )
    const user = userEvent.setup()
    render(<WalletButton />)
    expect(screen.getByRole('button', { name: 'Connect Terra Wallet' })).toHaveAttribute(
      'aria-expanded',
      'true'
    )
    await user.click(screen.getByRole('button', { name: 'Connect Terra Wallet' }))
    expect(setShowWalletModal).toHaveBeenCalledWith(false)
  })

  it('shows Cancel instead of a disabled spinner while connecting', async () => {
    const cancelConnection = vi.fn()
    const setShowWalletModal = vi.fn()
    mockUseWallet.mockReturnValue(
      disconnected({
        connecting: true,
        cancelConnection,
        setShowWalletModal,
      }) as unknown as ReturnType<typeof useWallet>
    )
    const user = userEvent.setup()
    render(<WalletButton />)
    const btn = screen.getByRole('button', { name: 'Cancel connecting Terra wallet' })
    expect(btn).toHaveTextContent('Cancel')
    expect(btn).toBeEnabled()
    await user.click(btn)
    expect(cancelConnection).toHaveBeenCalled()
    expect(setShowWalletModal).toHaveBeenCalledWith(false)
  })
})
