import { beforeEach, describe, expect, it, vi } from 'vitest'
import { render, screen } from '@testing-library/react'
import { TerraWalletModal } from './TerraWalletModal'
import { useWalletConnectPairingStore } from '../../stores/walletConnectPairing'

vi.mock('../../lib/sounds', () => ({
  sounds: { playButtonPress: vi.fn() },
}))

vi.mock('../../utils/constants', async () => {
  const actual = await vi.importActual<typeof import('../../utils/constants')>(
    '../../utils/constants'
  )
  return { ...actual, DEV_MODE: false }
})

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

import { useWallet } from '../../hooks/useWallet'
import { isWalletConnectMobileClient } from '../../utils/walletConnectPairing'

const mockUseWallet = vi.mocked(useWallet)
const mockIsMobile = vi.mocked(isWalletConnectMobileClient)

describe('TerraWalletModal production (GL-137)', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    useWalletConnectPairingStore.setState({ isOpen: false, payload: null })
    mockIsMobile.mockReturnValue(true)
    mockUseWallet.mockReturnValue({
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
    } as unknown as ReturnType<typeof useWallet>)
  })

  it('hides Simulated Terra Wallet when DEV_MODE is false', () => {
    render(<TerraWalletModal isOpen={true} onClose={() => {}} />)
    expect(screen.queryByTestId('wallet-option-simulated-terra-wallet')).not.toBeInTheDocument()
    expect(screen.getByTestId('wallet-option-lunc-dash')).toBeEnabled()
    expect(screen.getByTestId('wallet-option-keplr')).toBeEnabled()
  })
})
