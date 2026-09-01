import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { Link, MemoryRouter, Outlet, Route, Routes } from 'react-router-dom'
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

function renderWalletButton() {
  return render(
    <MemoryRouter>
      <WalletButton />
    </MemoryRouter>
  )
}

describe('WalletButton (GL-137)', () => {
  beforeEach(() => {
    vi.clearAllMocks()
  })

  it('exposes Connect Terra Wallet as the accessible name while disconnected', () => {
    mockUseWallet.mockReturnValue(disconnected() as unknown as ReturnType<typeof useWallet>)
    renderWalletButton()
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
    renderWalletButton()
    await user.click(screen.getByRole('button', { name: 'Connect Terra Wallet' }))
    expect(setShowWalletModal).toHaveBeenCalledWith(true)
  })

  it('toggles the open modal closed on a second tap (no duplicate WC sessions)', async () => {
    const setShowWalletModal = vi.fn()
    mockUseWallet.mockReturnValue(
      disconnected({ showWalletModal: true, setShowWalletModal }) as unknown as ReturnType<typeof useWallet>
    )
    const user = userEvent.setup()
    renderWalletButton()
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
    renderWalletButton()
    const btn = screen.getByRole('button', { name: 'Cancel connecting Terra wallet' })
    expect(btn).toHaveTextContent('Cancel')
    expect(btn).toBeEnabled()
    await user.click(btn)
    expect(cancelConnection).toHaveBeenCalled()
    expect(setShowWalletModal).toHaveBeenCalledWith(false)
  })

  it('closes the connected dropdown backdrop on route change while the header stays mounted', async () => {
    mockUseWallet.mockReturnValue(
      disconnected({
        connected: true,
        address: 'terra1abc',
        chainId: 'columbus-5',
        luncBalance: '0',
      }) as unknown as ReturnType<typeof useWallet>
    )

    function Shell() {
      return (
        <>
          <WalletButton />
          <Link to="/history">History</Link>
          <Outlet />
        </>
      )
    }

    const user = userEvent.setup()
    render(
      <MemoryRouter initialEntries={['/']}>
        <Routes>
          <Route element={<Shell />}>
            <Route path="/" element={<div>Home</div>} />
            <Route path="/history" element={<div>History page</div>} />
          </Route>
        </Routes>
      </MemoryRouter>
    )

    await user.click(screen.getByRole('button', { name: 'Connected Terra wallet' }))
    expect(screen.getByTestId('wallet-menu-backdrop')).toBeInTheDocument()
    await user.click(screen.getByRole('link', { name: 'History' }))
    expect(screen.queryByTestId('wallet-menu-backdrop')).not.toBeInTheDocument()
    expect(screen.getByText('History page')).toBeInTheDocument()
  })
})
