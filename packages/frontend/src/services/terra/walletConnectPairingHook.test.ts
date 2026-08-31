import { afterEach, beforeEach, describe, expect, it } from 'vitest'
import { useWalletStore } from '../../stores/wallet'
import { useWalletConnectPairingStore } from '../../stores/walletConnectPairing'
import { installWalletConnectPairingHook } from './walletConnectPairingHook'
import { getWalletConnectPairingHook, WC_PAIRING_HOOK_KEY } from '../../utils/walletConnectPairing'

const WC_V1 = 'wc:00e46b69-d0cc-4b3e-b6a2-cee442f97188@1?bridge=https%3A%2F%2Fwalletconnect.luncdash.com&key=abc'

const LUNC_PAYLOAD = {
  uri: WC_V1,
  name: 'LUNC Dash',
  android: '',
  ios: '',
  isStation: true,
  isLuncDash: true,
}

function stubNavigator(partial: { userAgent: string; platform?: string; maxTouchPoints?: number }) {
  Object.defineProperty(navigator, 'userAgent', { configurable: true, value: partial.userAgent })
  Object.defineProperty(navigator, 'platform', { configurable: true, value: partial.platform ?? 'Win32' })
  Object.defineProperty(navigator, 'maxTouchPoints', { configurable: true, value: partial.maxTouchPoints ?? 0 })
}

describe('installWalletConnectPairingHook (GL-137)', () => {
  let uninstall: (() => void) | undefined

  beforeEach(() => {
    stubNavigator({ userAgent: 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)' })
    useWalletConnectPairingStore.setState({ isOpen: false, payload: null })
    uninstall = installWalletConnectPairingHook()
  })

  afterEach(() => {
    uninstall?.()
    useWalletConnectPairingStore.setState({ isOpen: false, payload: null })
  })

  it('registers the global hook used by the cosmes QRCodeModal patch', () => {
    expect(getWalletConnectPairingHook()).toBeTruthy()
    expect((globalThis as Record<string, unknown>)[WC_PAIRING_HOOK_KEY]).toBeTruthy()
  })

  it('opens the pairing store on a mobile client and returns true', () => {
    const hook = getWalletConnectPairingHook()!
    const handled = hook.open(LUNC_PAYLOAD)
    expect(handled).toBe(true)
    const state = useWalletConnectPairingStore.getState()
    expect(state.isOpen).toBe(true)
    expect(state.payload?.uri).toBe(WC_V1)
  })

  it('ignores desktop clients so the cosmes QR path stays unchanged', () => {
    const original = window.matchMedia
    window.matchMedia = ((query: string) => ({
      matches: false,
      media: query,
      onchange: null,
      addListener: () => undefined,
      removeListener: () => undefined,
      addEventListener: () => undefined,
      removeEventListener: () => undefined,
      dispatchEvent: () => false,
    })) as typeof window.matchMedia
    stubNavigator({ userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)', platform: 'Win32', maxTouchPoints: 0 })

    uninstall?.()
    uninstall = installWalletConnectPairingHook()
    const handled = getWalletConnectPairingHook()!.open(LUNC_PAYLOAD)
    expect(handled).toBe(false)
    expect(useWalletConnectPairingStore.getState().isOpen).toBe(false)

    window.matchMedia = original
  })

  it('rejects non-wc URIs', () => {
    const handled = getWalletConnectPairingHook()!.open({ ...LUNC_PAYLOAD, uri: 'https://evil.example' })
    expect(handled).toBe(false)
    expect(useWalletConnectPairingStore.getState().isOpen).toBe(false)
  })

  it('close() clears the store', () => {
    const hook = getWalletConnectPairingHook()!
    hook.open(LUNC_PAYLOAD)
    hook.close()
    expect(useWalletConnectPairingStore.getState().isOpen).toBe(false)
    expect(useWalletConnectPairingStore.getState().payload).toBeNull()
  })

  it('treats Android 16 Chrome as mobile and hides Connect Wallet on open', () => {
    stubNavigator({
      userAgent:
        'Mozilla/5.0 (Linux; Android 16; Pixel 9) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Mobile Safari/537.36',
    })
    uninstall?.()
    uninstall = installWalletConnectPairingHook()
    useWalletStore.setState({ showWalletModal: true })
    const handled = getWalletConnectPairingHook()!.open(LUNC_PAYLOAD)
    expect(handled).toBe(true)
    expect(useWalletConnectPairingStore.getState().isOpen).toBe(true)
    expect(useWalletStore.getState().showWalletModal).toBe(false)
  })

  it('does not rotate an in-flight pairing URI when open() is called again', () => {
    const hook = getWalletConnectPairingHook()!
    expect(hook.open(LUNC_PAYLOAD)).toBe(true)
    const second = {
      ...LUNC_PAYLOAD,
      uri: 'wc:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff@2?relay-protocol=irn&symKey=test',
    }
    expect(hook.open(second)).toBe(true)
    expect(useWalletConnectPairingStore.getState().payload?.uri).toBe(WC_V1)
  })

  it('exposes isAllowedDeepLink for the cosmes QR fallback Open button', () => {
    const hook = getWalletConnectPairingHook()!
    expect(hook.isAllowedDeepLink?.('luncdash://wallet_connect?x')).toBe(true)
    expect(hook.isAllowedDeepLink?.('intent://steal#Intent;package=com.evil.app;end;')).toBe(false)
  })
})
