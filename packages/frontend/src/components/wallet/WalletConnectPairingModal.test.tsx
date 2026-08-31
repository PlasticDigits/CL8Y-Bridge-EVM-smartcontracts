import { beforeEach, describe, expect, it, vi } from 'vitest'
import { render, screen, fireEvent } from '@testing-library/react'
import { useWalletConnectPairingStore } from '../../stores/walletConnectPairing'
import { WalletConnectPairingModal } from './WalletConnectPairingModal'

vi.mock('../../lib/sounds', () => ({
  sounds: { playButtonPress: vi.fn() },
}))

const WC_V1 = 'wc:00e46b69-d0cc-4b3e-b6a2-cee442f97188@1?bridge=https%3A%2F%2Fwalletconnect.luncdash.com&key=abc'

describe('WalletConnectPairingModal (GL-137)', () => {
  beforeEach(() => {
    useWalletConnectPairingStore.setState({ isOpen: false, payload: null })
  })

  it('renders nothing when the pairing store is closed', () => {
    render(<WalletConnectPairingModal />)
    expect(screen.queryByTestId('walletconnect-pairing-modal')).not.toBeInTheDocument()
  })

  it('shows Open Lunc Dash, Open wallet, and Copy pairing link without a QR canvas', () => {
    useWalletConnectPairingStore.setState({
      isOpen: true,
      payload: {
        uri: WC_V1,
        name: 'LUNC Dash',
        android: '',
        ios: '',
        isStation: true,
        isLuncDash: true,
      },
    })
    render(<WalletConnectPairingModal />)

    expect(screen.getByTestId('walletconnect-pairing-modal')).toBeInTheDocument()
    const openWallet = screen.getByTestId('walletconnect-pairing-wallet')
    expect(openWallet).toHaveTextContent('Open LUNC Dash')
    expect(openWallet.getAttribute('href')?.startsWith('luncdash://')).toBe(true)

    const generic = screen.getByTestId('walletconnect-pairing-generic')
    expect(generic).toHaveTextContent('Open wallet')
    expect(generic).toHaveAttribute('href', WC_V1)

    expect(screen.getByTestId('walletconnect-pairing-copy')).toHaveTextContent('Copy pairing link')
    expect(document.querySelector('canvas')).toBeNull()
  })

  it('stacks the pairing portal above Connect Wallet (z-[10001])', () => {
    useWalletConnectPairingStore.setState({
      isOpen: true,
      payload: {
        uri: WC_V1,
        name: 'LUNC Dash',
        android: '',
        ios: '',
        isStation: true,
        isLuncDash: true,
      },
    })
    render(<WalletConnectPairingModal />)
    const portal = screen.getByTestId('walletconnect-pairing-portal')
    expect(portal.className).toContain('z-[10001]')
    expect(screen.getByTestId('walletconnect-pairing-cancel')).toHaveTextContent('Cancel')
  })

  it('does not dismiss when Open or Copy is used', () => {
    useWalletConnectPairingStore.setState({
      isOpen: true,
      payload: {
        uri: WC_V1,
        name: 'LUNC Dash',
        android: '',
        ios: '',
        isStation: true,
        isLuncDash: true,
      },
    })
    render(<WalletConnectPairingModal />)
    fireEvent.click(screen.getByTestId('walletconnect-pairing-wallet'))
    fireEvent.click(screen.getByTestId('walletconnect-pairing-copy'))
    expect(screen.getByTestId('walletconnect-pairing-modal')).toBeInTheDocument()
    expect(useWalletConnectPairingStore.getState().isOpen).toBe(true)
  })
})
