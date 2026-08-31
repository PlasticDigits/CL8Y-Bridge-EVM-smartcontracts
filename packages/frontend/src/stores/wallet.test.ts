import { beforeEach, describe, expect, it } from 'vitest'
import { useWalletStore } from './wallet'
import { useWalletConnectPairingStore } from './walletConnectPairing'

describe('useWalletStore connecting (GL-137)', () => {
  beforeEach(() => {
    useWalletStore.setState({
      connected: false,
      connecting: false,
      connectingWallet: null,
      connectingSince: null,
      showWalletModal: false,
      connectionError: null,
    })
    useWalletConnectPairingStore.setState({ isOpen: false, payload: null })
  })

  it('starts with connecting false so the header CTA is not spinner-disabled on load', () => {
    expect(useWalletStore.getState().connecting).toBe(false)
    expect(useWalletStore.getState().connectingWallet).toBeNull()
  })

  it('cancelConnection clears spinner state and closes the pairing sheet', () => {
    useWalletStore.setState({ connecting: true, connectingWallet: null, connectingSince: Date.now() })
    useWalletConnectPairingStore.setState({
      isOpen: true,
      payload: {
        uri: 'wc:x@1?bridge=https://walletconnect.luncdash.com',
        name: 'LUNC Dash',
        android: '',
        ios: '',
        isStation: true,
        isLuncDash: true,
      },
    })
    useWalletStore.getState().cancelConnection()
    expect(useWalletStore.getState().connecting).toBe(false)
    expect(useWalletStore.getState().connectingWallet).toBeNull()
    expect(useWalletConnectPairingStore.getState().isOpen).toBe(false)
  })
})
