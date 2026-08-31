import { CopyButton } from '../ui'
import { Modal } from '../ui'
import { useWalletStore } from '../../stores/wallet'
import { useWalletConnectPairingStore } from '../../stores/walletConnectPairing'
import { sounds } from '../../lib/sounds'
import { buildWalletConnectDeepLinks, isAllowedWalletConnectDeepLink } from '../../utils/walletConnectPairing'

export function WalletConnectPairingModal() {
  const { isOpen, payload, close } = useWalletConnectPairingStore()
  const cancelConnection = useWalletStore((s) => s.cancelConnection)

  if (!isOpen || !payload) return null

  const links = buildWalletConnectDeepLinks(payload, payload.uri)

  function handleUserDismiss() {
    close()
    cancelConnection()
  }

  return (
    <Modal
      isOpen={true}
      onClose={handleUserDismiss}
      title={`Connect ${payload.name}`}
      zIndexClassName="z-[10001]"
      rootTestId="walletconnect-pairing-portal"
      closeAriaLabel="Close pairing"
    >
      <div className="walletconnect-pairing px-6 py-4" data-testid="walletconnect-pairing-modal">
        <p className="mb-4 text-sm text-gray-400">
          Open your wallet, then return here. Use Open or Copy — the browser will not auto-redirect.
        </p>
        <div className="flex flex-col gap-2">
          {links.map((link) => (
            <a
              key={link.id}
              className={
                link.id === 'wallet'
                  ? 'btn-primary walletconnect-pairing-link justify-center'
                  : 'btn-muted walletconnect-pairing-link justify-center'
              }
              href={isAllowedWalletConnectDeepLink(link.href) ? link.href : undefined}
              data-testid={`walletconnect-pairing-${link.id}`}
              onClick={(event) => {
                if (!isAllowedWalletConnectDeepLink(link.href)) {
                  event.preventDefault()
                  return
                }
                sounds.playButtonPress()
              }}
            >
              {link.label}
            </a>
          ))}
          <CopyButton
            text={payload.uri}
            label="Copy pairing link"
            testId="walletconnect-pairing-copy"
            showLabel
            className="btn-muted justify-center w-full"
          />
          <label className="mt-1 block text-xs text-gray-500">
            Pairing link (long-press to copy if Copy fails)
            <input
              readOnly
              data-testid="walletconnect-pairing-uri"
              className="mt-1 w-full rounded border border-white/10 bg-black/40 px-2 py-1.5 text-[11px] text-gray-300 font-mono select-all"
              value={payload.uri}
              aria-label="WalletConnect pairing URI"
              onFocus={(event) => event.currentTarget.select()}
            />
          </label>
          <button
            type="button"
            className="btn-muted justify-center"
            data-testid="walletconnect-pairing-cancel"
            onClick={() => {
              sounds.playButtonPress()
              handleUserDismiss()
            }}
          >
            Cancel
          </button>
        </div>
      </div>
    </Modal>
  )
}
