import { useWalletStore } from '../../stores/wallet'
import { useWalletConnectPairingStore } from '../../stores/walletConnectPairing'
import {
  isAllowedWalletConnectDeepLink,
  isWalletConnectMobileClient,
  isWalletConnectPairingUri,
  WC_PAIRING_HOOK_KEY,
  type WalletConnectPairingHook,
  type WalletConnectPairingHookPayload,
} from '../../utils/walletConnectPairing'

/**
 * Registers the cosmes `QRCodeModal` intercept (GitLab #137 / DEX #519).
 * Install once at boot so the hook exists before any WalletConnect `connect()`.
 */
export function installWalletConnectPairingHook(): () => void {
  const hook: WalletConnectPairingHook = {
    open(payload: WalletConnectPairingHookPayload) {
      if (!isWalletConnectPairingUri(payload.uri)) return false
      if (!isWalletConnectMobileClient()) return false
      const pairing = useWalletConnectPairingStore.getState()
      // INV-FE-WC-MOBILE-1: a second connect() (visibility retry, double-tap)
      // must not replace the URI the wallet may already be approving.
      if (pairing.isOpen && pairing.payload?.uri) {
        return true
      }
      useWalletStore.getState().setShowWalletModal(false)
      pairing.open(payload)
      return true
    },
    close() {
      useWalletConnectPairingStore.getState().close()
    },
    isAllowedDeepLink: isAllowedWalletConnectDeepLink,
  }

  const bag = globalThis as typeof globalThis & Record<string, unknown>
  bag[WC_PAIRING_HOOK_KEY] = hook

  return () => {
    if (bag[WC_PAIRING_HOOK_KEY] === hook) {
      delete bag[WC_PAIRING_HOOK_KEY]
    }
  }
}
