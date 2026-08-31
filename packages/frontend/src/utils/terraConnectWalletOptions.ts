/**
 * Terra connect-modal row resolution (GitLab #137; DEX #554 / #566).
 *
 * Mobile Chrome without the matching extension offers Keplr / Station /
 * Cosmostation via WalletConnect — not a permanently disabled "Not installed"
 * extension row. Leap stays extension-only and is hidden on mobile (vendor-risk;
 * DEX removed it — do not revive a dead Install URL as the mobile fix).
 */

import { WalletName, WalletType } from '@goblinhunt/cosmes/wallet'

export type ConnectWalletOption = {
  name: string
  walletName: WalletName
  walletType: WalletType
  connectionLabel: string
}

export type ConnectWalletOptionEnv = {
  isMobileClient: boolean
  keplrInjected: boolean
  stationInjected: boolean
  cosmostationInjected: boolean
}

export function shouldOfferMobileExtensionWalletConnect(
  isMobileClient: boolean,
  extensionInjected: boolean
): boolean {
  return isMobileClient && !extensionInjected
}

export function shouldOfferKeplrWalletConnect(env: ConnectWalletOptionEnv): boolean {
  return shouldOfferMobileExtensionWalletConnect(env.isMobileClient, env.keplrInjected)
}

export function shouldOfferStationWalletConnect(env: ConnectWalletOptionEnv): boolean {
  return shouldOfferMobileExtensionWalletConnect(env.isMobileClient, env.stationInjected)
}

export function shouldOfferCosmostationWalletConnect(env: ConnectWalletOptionEnv): boolean {
  return shouldOfferMobileExtensionWalletConnect(env.isMobileClient, env.cosmostationInjected)
}

function extensionOrWalletConnect(
  name: string,
  walletName: WalletName,
  offerWalletConnect: boolean
): ConnectWalletOption {
  if (offerWalletConnect) {
    return {
      name,
      walletName,
      walletType: WalletType.WALLETCONNECT,
      connectionLabel: 'WalletConnect',
    }
  }
  return {
    name,
    walletName,
    walletType: WalletType.EXTENSION,
    connectionLabel: 'Extension',
  }
}

export function resolveConnectWalletOptions(env: ConnectWalletOptionEnv): ConnectWalletOption[] {
  const rows: ConnectWalletOption[] = [
    extensionOrWalletConnect('Terra Station', WalletName.STATION, shouldOfferStationWalletConnect(env)),
    extensionOrWalletConnect('Keplr', WalletName.KEPLR, shouldOfferKeplrWalletConnect(env)),
  ]

  if (!env.isMobileClient) {
    rows.push({
      name: 'Leap',
      walletName: WalletName.LEAP,
      walletType: WalletType.EXTENSION,
      connectionLabel: 'Extension',
    })
  }

  rows.push(
    extensionOrWalletConnect(
      'Cosmostation',
      WalletName.COSMOSTATION,
      shouldOfferCosmostationWalletConnect(env)
    ),
    {
      name: 'LUNC Dash',
      walletName: WalletName.LUNCDASH,
      walletType: WalletType.WALLETCONNECT,
      connectionLabel: 'WalletConnect',
    },
    {
      name: 'Galaxy Station',
      walletName: WalletName.GALAXYSTATION,
      walletType: WalletType.WALLETCONNECT,
      connectionLabel: 'WalletConnect',
    }
  )

  return rows
}
