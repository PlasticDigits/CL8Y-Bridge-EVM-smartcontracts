import { describe, expect, it } from 'vitest'
import { WalletName, WalletType } from '@goblinhunt/cosmes/wallet'
import {
  resolveConnectWalletOptions,
  shouldOfferCosmostationWalletConnect,
  shouldOfferKeplrWalletConnect,
  shouldOfferStationWalletConnect,
  type ConnectWalletOptionEnv,
} from './terraConnectWalletOptions'

const desktop: ConnectWalletOptionEnv = {
  isMobileClient: false,
  keplrInjected: false,
  stationInjected: false,
  cosmostationInjected: false,
}

const mobileNone: ConnectWalletOptionEnv = {
  isMobileClient: true,
  keplrInjected: false,
  stationInjected: false,
  cosmostationInjected: false,
}

function row(env: ConnectWalletOptionEnv, walletName: WalletName) {
  return resolveConnectWalletOptions(env).find((option) => option.walletName === walletName)
}

describe('resolveConnectWalletOptions (GL-137)', () => {
  it('offers Keplr WalletConnect on mobile when window.keplr is absent', () => {
    expect(shouldOfferKeplrWalletConnect(mobileNone)).toBe(true)
    const keplr = row(mobileNone, WalletName.KEPLR)
    expect(keplr?.walletType).toBe(WalletType.WALLETCONNECT)
    expect(keplr?.connectionLabel).toBe('WalletConnect')
  })

  it('offers Station WalletConnect on mobile when station is not injected', () => {
    expect(shouldOfferStationWalletConnect(mobileNone)).toBe(true)
    expect(row(mobileNone, WalletName.STATION)?.walletType).toBe(WalletType.WALLETCONNECT)
  })

  it('offers Cosmostation WalletConnect on mobile when Cosmostation is not injected', () => {
    expect(shouldOfferCosmostationWalletConnect(mobileNone)).toBe(true)
    expect(row(mobileNone, WalletName.COSMOSTATION)?.walletType).toBe(WalletType.WALLETCONNECT)
  })

  it('keeps Keplr Extension when injected (in-app browser)', () => {
    const env = { ...mobileNone, keplrInjected: true }
    expect(shouldOfferKeplrWalletConnect(env)).toBe(false)
    expect(row(env, WalletName.KEPLR)?.walletType).toBe(WalletType.EXTENSION)
  })

  it('keeps desktop Keplr / Station / Cosmostation as Extension even without injection', () => {
    expect(row(desktop, WalletName.KEPLR)?.walletType).toBe(WalletType.EXTENSION)
    expect(row(desktop, WalletName.STATION)?.walletType).toBe(WalletType.EXTENSION)
    expect(row(desktop, WalletName.COSMOSTATION)?.walletType).toBe(WalletType.EXTENSION)
  })

  it('hides Leap on mobile and keeps it as desktop extension only', () => {
    expect(row(mobileNone, WalletName.LEAP)).toBeUndefined()
    expect(row(desktop, WalletName.LEAP)?.walletType).toBe(WalletType.EXTENSION)
  })

  it('always lists LUNC Dash and Galaxy Station as WalletConnect', () => {
    expect(row(mobileNone, WalletName.LUNCDASH)?.walletType).toBe(WalletType.WALLETCONNECT)
    expect(row(mobileNone, WalletName.GALAXYSTATION)?.walletType).toBe(WalletType.WALLETCONNECT)
  })
})
