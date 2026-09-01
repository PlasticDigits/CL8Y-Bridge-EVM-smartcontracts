import { beforeEach, describe, expect, it, vi } from 'vitest'
import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { WalletName } from '@goblinhunt/cosmes/wallet'
import { TerraWalletModal } from './TerraWalletModal'
import { useWalletConnectPairingStore } from '../../stores/walletConnectPairing'

vi.mock('../../lib/sounds', () => ({
  sounds: { playButtonPress: vi.fn() },
}))

vi.mock('../../hooks/useWallet', async () => {
  const { WalletName, WalletType } = await import('@goblinhunt/cosmes/wallet')
  return {
    useWallet: vi.fn(),
    WalletName,
    WalletType,
  }
})

vi.mock('../../utils/walletConnectPairing', async () => {
  const actual = await vi.importActual<typeof import('../../utils/walletConnectPairing')>(
    '../../utils/walletConnectPairing'
  )
  return {
    ...actual,
    isWalletConnectMobileClient: vi.fn(),
  }
})

vi.mock('../../utils/detectInAppBrowser', () => ({
  detectInAppBrowser: vi.fn(() => ({ isInAppBrowser: false, browserName: null })),
}))

import { useWallet } from '../../hooks/useWallet'
import { isWalletConnectMobileClient } from '../../utils/walletConnectPairing'
import { detectInAppBrowser } from '../../utils/detectInAppBrowser'

const mockUseWallet = vi.mocked(useWallet)
const mockIsMobile = vi.mocked(isWalletConnectMobileClient)
const mockDetectInApp = vi.mocked(detectInAppBrowser)

function walletState(overrides: Record<string, unknown> = {}) {
  return {
    connecting: false,
    connectingWallet: null,
    connectionError: null,
    isStationAvailable: false,
    isKeplrAvailable: false,
    isLeapAvailable: false,
    isCosmostationAvailable: false,
    connect: vi.fn(),
    connectSimulated: vi.fn(),
    cancelConnection: vi.fn(),
    clearConnectionError: vi.fn(),
    ...overrides,
  }
}

describe('TerraWalletModal (GL-137)', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    useWalletConnectPairingStore.setState({ isOpen: false, payload: null })
    mockIsMobile.mockReturnValue(false)
    mockDetectInApp.mockReturnValue({ isInAppBrowser: false, browserName: null })
    mockUseWallet.mockReturnValue(walletState() as unknown as ReturnType<typeof useWallet>)
  })

  it('renders nothing useful when closed', () => {
    render(<TerraWalletModal isOpen={false} onClose={() => {}} />)
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
  })

  it('on desktop without extensions, Keplr is a disabled extension row and WC wallets stay enabled', () => {
    render(<TerraWalletModal isOpen={true} onClose={() => {}} />)
    expect(screen.getByTestId('wallet-option-keplr')).toBeDisabled()
    expect(screen.getByTestId('wallet-option-lunc-dash')).toBeEnabled()
    expect(screen.getByTestId('wallet-option-galaxy-station')).toBeEnabled()
    expect(screen.getByTestId('wallet-option-leap')).toBeDisabled()
  })

  it('on mobile Chrome without keplr, Keplr is an enabled WalletConnect row (not Not installed only)', () => {
    mockIsMobile.mockReturnValue(true)
    render(<TerraWalletModal isOpen={true} onClose={() => {}} />)
    const keplr = screen.getByTestId('wallet-option-keplr')
    expect(keplr).toBeEnabled()
    expect(keplr).toHaveTextContent(/WalletConnect/i)
    expect(screen.getByTestId('wallet-option-lunc-dash')).toBeEnabled()
    expect(screen.getByTestId('wallet-option-galaxy-station')).toBeEnabled()
    expect(screen.queryByTestId('wallet-option-leap')).not.toBeInTheDocument()
    expect(screen.getByTestId('wallet-modal-mobile-hint')).toHaveTextContent(/Leap is desktop-only/)
    expect(screen.getByTestId('wallet-modal-mobile-hint')).toHaveTextContent(/Lunc Dash/)
  })

  it('keeps Keplr as extension when injected on mobile', () => {
    mockIsMobile.mockReturnValue(true)
    mockUseWallet.mockReturnValue(
      walletState({ isKeplrAvailable: true }) as unknown as ReturnType<typeof useWallet>
    )
    render(<TerraWalletModal isOpen={true} onClose={() => {}} />)
    expect(screen.getByTestId('wallet-option-keplr')).toBeEnabled()
    expect(screen.getByTestId('wallet-option-keplr')).toHaveTextContent(/Cosmos ecosystem/)
  })

  it('Cancel during WC wait calls cancelConnection', async () => {
    const cancelConnection = vi.fn()
    mockIsMobile.mockReturnValue(true)
    mockUseWallet.mockReturnValue(
      walletState({
        connecting: true,
        connectingWallet: WalletName.LUNCDASH,
        cancelConnection,
      }) as unknown as ReturnType<typeof useWallet>
    )
    const user = userEvent.setup()
    render(<TerraWalletModal isOpen={true} onClose={() => {}} />)
    await user.click(screen.getByRole('button', { name: 'Cancel' }))
    expect(cancelConnection).toHaveBeenCalled()
  })

  it('shows Simulated Terra Wallet in DEV_MODE', () => {
    render(<TerraWalletModal isOpen={true} onClose={() => {}} />)
    expect(screen.getByTestId('wallet-option-simulated-terra-wallet')).toBeInTheDocument()
  })

  it('shows the in-app browser banner before wallet rows when a wallet WebView is detected', () => {
    mockIsMobile.mockReturnValue(true)
    mockDetectInApp.mockReturnValue({ isInAppBrowser: true, browserName: 'Keplr' })
    render(<TerraWalletModal isOpen={true} onClose={() => {}} />)
    const banner = screen.getByTestId('wallet-modal-in-app-banner')
    expect(banner).toHaveTextContent(/In-app browser detected \(Keplr\)/)
    expect(banner).toHaveTextContent(/default browser/)
    expect(screen.queryByTestId('wallet-modal-mobile-hint')).not.toBeInTheDocument()
    expect(screen.getByTestId('wallet-option-lunc-dash')).toBeEnabled()
  })
})
