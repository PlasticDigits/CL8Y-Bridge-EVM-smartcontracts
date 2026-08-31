/**
 * Keplr-compatible injected providers (GitLab #137; ustr-cmm working control).
 *
 * Cosmes `KeplrController` reads `window.keplr`. Trust Wallet's in-app browser
 * may inject that alias, or only `window.trustwallet.cosmos` (Keplr-shaped).
 * Chrome Android has neither — that path uses WalletConnect instead
 * (`terraConnectWalletOptions.ts`).
 */

export type KeplrLikeProvider = {
  enable: (chainId: string) => Promise<void>
  getOfflineSigner: (chainId: string) => unknown
  experimentalSuggestChain?: (chainInfo: unknown) => Promise<void>
}

type KeplrWindow = {
  keplr?: KeplrLikeProvider
  trustwallet?: {
    cosmos?: KeplrLikeProvider
    ethereum?: { isTrust?: boolean }
  }
}

function currentKeplrWindow(): KeplrWindow | undefined {
  return typeof window === 'undefined' ? undefined : (window as unknown as KeplrWindow)
}

/**
 * Prefer `window.keplr` (Keplr + wallets that alias it). Fall back to Trust’s
 * official Cosmos inject, which may exist without `window.keplr`.
 */
export function getKeplrCompatibleProvider(
  win: KeplrWindow | undefined = currentKeplrWindow()
): KeplrLikeProvider | undefined {
  if (!win) return undefined
  return win.keplr ?? win.trustwallet?.cosmos
}

export function isKeplrCompatibleInstalled(
  win: KeplrWindow | undefined = currentKeplrWindow()
): boolean {
  return !!getKeplrCompatibleProvider(win)
}

/**
 * Alias Trust’s Cosmos provider onto `window.keplr` so KeplrController works.
 * Never overwrites an existing `window.keplr`.
 */
export function ensureKeplrCompatibleProvider(
  win: KeplrWindow | undefined = currentKeplrWindow()
): boolean {
  if (!win) return false
  if (win.keplr) return true
  const trustCosmos = win.trustwallet?.cosmos
  if (!trustCosmos) return false
  win.keplr = trustCosmos
  return true
}
