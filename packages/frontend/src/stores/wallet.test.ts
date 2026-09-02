import { beforeEach, describe, expect, it, vi } from 'vitest'
import { WalletName, WalletType } from '@goblinhunt/cosmes/wallet'
import {
  applyWalletHydrateReset,
  ConnectionCancelledError,
  isConnectionCancelledError,
  shouldDisconnectGhostWalletConnect,
  useWalletStore,
} from './wallet'
import { useWalletConnectPairingStore } from './walletConnectPairing'
import { connectTerraWallet, disconnectTerraWallet } from '../services/terra'

vi.mock('../services/terra', async () => {
  const actual = await vi.importActual<typeof import('../services/terra')>('../services/terra')
  return {
    ...actual,
    connectTerraWallet: vi.fn(),
    disconnectTerraWallet: vi.fn(),
  }
})

const mockConnect = vi.mocked(connectTerraWallet)
const mockDisconnect = vi.mocked(disconnectTerraWallet)

describe('useWalletStore connecting (GL-137)', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    mockConnect.mockReset()
    mockDisconnect.mockReset()
    mockDisconnect.mockResolvedValue(undefined)
    useWalletStore.setState({
      connected: false,
      connecting: false,
      connectingWallet: null,
      connectingSince: null,
      showWalletModal: false,
      connectionError: null,
      address: null,
      walletType: null,
      connectionType: null,
    })
    useWalletConnectPairingStore.setState({ isOpen: false, payload: null })
  })

  it('starts with connecting false so the header CTA is not spinner-disabled on load', () => {
    expect(useWalletStore.getState().connecting).toBe(false)
    expect(useWalletStore.getState().connectingWallet).toBeNull()
  })

  it('applyWalletHydrateReset clears a stuck spinner, modal, and error from a previous tab', () => {
    const state = {
      connecting: true,
      connectingWallet: WalletName.KEPLR,
      connectingSince: Date.now(),
      showWalletModal: true,
      connectionError: 'stale',
    }
    applyWalletHydrateReset(state)
    expect(state.connecting).toBe(false)
    expect(state.connectingWallet).toBeNull()
    expect(state.connectingSince).toBeNull()
    expect(state.showWalletModal).toBe(false)
    expect(state.connectionError).toBeNull()
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

  it('does not apply a late WalletConnect success after Cancel', async () => {
    let finishConnect!: (value: {
      address: string
      walletType: 'luncdash'
      connectionType: WalletType
    }) => void
    mockConnect.mockReturnValue(
      new Promise((resolve) => {
        finishConnect = resolve
      })
    )

    const pending = useWalletStore.getState().connect(WalletName.LUNCDASH, WalletType.WALLETCONNECT)
    expect(useWalletStore.getState().connecting).toBe(true)

    useWalletStore.getState().cancelConnection()
    expect(useWalletStore.getState().connecting).toBe(false)

    finishConnect({
      address: 'terra1cancelled',
      walletType: 'luncdash',
      connectionType: WalletType.WALLETCONNECT,
    })
    await expect(pending).rejects.toBeInstanceOf(ConnectionCancelledError)
    expect(useWalletStore.getState().connected).toBe(false)
    expect(useWalletStore.getState().address).toBeNull()
    expect(useWalletStore.getState().connecting).toBe(false)
    expect(useWalletStore.getState().connectionError).toBeNull()
    expect(mockDisconnect).toHaveBeenCalled()
  })

  it('does not record connectionError when a cancelled connect later fails', async () => {
    let failConnect!: (reason: Error) => void
    mockConnect.mockReturnValue(
      new Promise((_, reject) => {
        failConnect = reject
      })
    )

    const pending = useWalletStore.getState().connect(WalletName.KEPLR, WalletType.WALLETCONNECT)
    useWalletStore.getState().cancelConnection()
    failConnect(new Error('Keplr relay timeout'))
    await expect(pending).rejects.toBeInstanceOf(ConnectionCancelledError)
    expect(useWalletStore.getState().connectionError).toBeNull()
    expect(useWalletStore.getState().connecting).toBe(false)
  })

  it('isConnectionCancelledError is true only for ConnectionCancelledError', () => {
    expect(isConnectionCancelledError(new ConnectionCancelledError())).toBe(true)
    expect(isConnectionCancelledError(new Error('Connection cancelled'))).toBe(false)
  })

  it('shouldDisconnectGhostWalletConnect is false while a newer connect owns the WC singleton', () => {
    expect(shouldDisconnectGhostWalletConnect(false)).toBe(true)
    expect(shouldDisconnectGhostWalletConnect(true)).toBe(false)
  })

  it('does not disconnect WalletConnect when Retry has already started a newer connect', async () => {
    const wcResult = {
      address: 'terra1stale',
      walletType: 'luncdash' as const,
      connectionType: WalletType.WALLETCONNECT,
    }
    let finishA!: (value: typeof wcResult) => void
    let finishB!: (value: typeof wcResult) => void
    mockConnect
      .mockReturnValueOnce(
        new Promise((resolve) => {
          finishA = resolve
        })
      )
      .mockReturnValueOnce(
        new Promise((resolve) => {
          finishB = resolve
        })
      )

    const pendingA = useWalletStore.getState().connect(WalletName.LUNCDASH, WalletType.WALLETCONNECT)
    expect(useWalletStore.getState().connecting).toBe(true)

    useWalletStore.getState().cancelConnection()
    expect(useWalletStore.getState().connecting).toBe(false)

    const pendingB = useWalletStore.getState().connect(WalletName.LUNCDASH, WalletType.WALLETCONNECT)
    expect(useWalletStore.getState().connecting).toBe(true)
    expect(useWalletStore.getState().connected).toBe(false)

    finishA({ ...wcResult, address: 'terra1stale' })
    await expect(pendingA).rejects.toBeInstanceOf(ConnectionCancelledError)
    expect(useWalletStore.getState().connected).toBe(false)
    expect(useWalletStore.getState().address).toBeNull()
    expect(useWalletStore.getState().connecting).toBe(true)
    expect(useWalletStore.getState().connectionError).toBeNull()
    expect(mockDisconnect).not.toHaveBeenCalled()

    useWalletStore.getState().cancelConnection()
    finishB({ ...wcResult, address: 'terra1retry' })
    await expect(pendingB).rejects.toBeInstanceOf(ConnectionCancelledError)
  })
})
