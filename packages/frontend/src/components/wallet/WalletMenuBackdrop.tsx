import { createPortal } from 'react-dom'

type WalletMenuBackdropProps = {
  onClose: () => void
}

/**
 * INV-FE-WC-MOBILE-1: full-viewport click-catcher for connected-wallet menus.
 * Portaled to `document.body` at z-40 so the sticky header (z-50) — including
 * Connect Terra Wallet — stays tappable. Do not render this inside the header
 * stacking context or it covers nav + Connect.
 */
export function WalletMenuBackdrop({ onClose }: WalletMenuBackdropProps) {
  return createPortal(
    <button
      type="button"
      aria-label="Close wallet menu"
      data-testid="wallet-menu-backdrop"
      className="fixed inset-0 z-40 cursor-default bg-transparent"
      onClick={onClose}
    />,
    document.body
  )
}
