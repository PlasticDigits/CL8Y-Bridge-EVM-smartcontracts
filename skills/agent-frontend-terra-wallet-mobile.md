# Agent skill: Terra wallet connect on mobile Chrome (GL-137)

Use when changing the **header Terra Connect CTA**, **TerraWalletModal**, **WalletConnect pairing** (Lunc Dash / Galaxy Station / Keplr WC), **cosmes `QRCodeModal`**, or a report that **Android Chrome cannot tap Connect**. Companion invariant: [FRONTEND_BRIDGE_INVARIANTS.md](../docs/FRONTEND_BRIDGE_INVARIANTS.md) **INV-FE-WC-MOBILE-1**. Issue: https://gitlab.com/PlasticDigits/cl8y-bridge-monorepo/-/issues/137

Working control on the same phone: **ustr-cmm** (`https://ust1cmm.com`) — `PlasticDigits2/ustr-cmm` `frontend/`. DEX pairing (Open / Copy, no auto-redirect): cl8y-dex-terraclassic **#519 / #554**. Legal `Keplr extension not found` on T&C is **not** this CTA.

## Code map

| Concern | Location |
|---------|----------|
| Header CTA (aria-label, Cancel, hit target) | [`WalletButton.tsx`](../packages/frontend/src/components/WalletButton.tsx) |
| Header stacking / no `overflow-x-clip` | [`Layout.tsx`](../packages/frontend/src/components/Layout.tsx), [`NavBar.tsx`](../packages/frontend/src/components/NavBar.tsx) |
| Modal rows (Keplr WC on mobile) | [`TerraWalletModal.tsx`](../packages/frontend/src/components/wallet/TerraWalletModal.tsx), [`terraConnectWalletOptions.ts`](../packages/frontend/src/utils/terraConnectWalletOptions.ts) |
| Pairing Open / Copy + allowlist | [`walletConnectPairing.ts`](../packages/frontend/src/utils/walletConnectPairing.ts), [`WalletConnectPairingModal.tsx`](../packages/frontend/src/components/wallet/WalletConnectPairingModal.tsx) |
| Cosmes intercept | [`walletConnectPairingHook.ts`](../packages/frontend/src/services/terra/walletConnectPairingHook.ts), patch `QRCodeModal.js` |
| Trust / Keplr-shaped inject | [`keplrCompatible.ts`](../packages/frontend/src/utils/keplrCompatible.ts) |
| In-app browser banner | [`detectInAppBrowser.ts`](../packages/frontend/src/utils/detectInAppBrowser.ts) |
| Connecting reset on hydrate | [`stores/wallet.ts`](../packages/frontend/src/stores/wallet.ts) `onRehydrateStorage` |
| E2E (mobile viewport + aria-label) | [`e2e/wallet-connect.spec.ts`](../packages/frontend/e2e/wallet-connect.spec.ts) |

## Invariants

- **INV-FE-WC-MOBILE-1:** See the table in [FRONTEND_BRIDGE_INVARIANTS.md](../docs/FRONTEND_BRIDGE_INVARIANTS.md). Do not auto-redirect WalletConnect from a non-gesture async callback. Do not require a desktop extension as the only Terra path on mobile Chrome. Simulated wallet stays **DEV_MODE**. Leap is not the mobile fix.

## Checklist (change connect UX)

1. Keep `aria-label="Connect Terra Wallet"` on the disconnected CTA (visual `TC` is fine).
2. Do not `disabled={connecting}` on the header button — use Cancel.
3. After editing cosmes, regenerate `packages/frontend/patches/@goblinhunt+cosmes+*.patch` with `npx patch-package @goblinhunt/cosmes` and keep `__CL8Y_WC_PAIRING_MODAL__`.
4. New deep-link schemes must be added to `isAllowedWalletConnectDeepLink` (never blanket `https:`).
5. Unit tests: `walletConnectPairing.test.ts`, `terraConnectWalletOptions.test.ts`, `WalletButton.test.tsx`, `TerraWalletModal.test.tsx`.
6. E2E: mobile viewport (390×844) must click by aria-label / `data-testid="connect-terra-wallet"`, not only `CONNECT TC`.
7. Future **Legal TermsGate (GL-134)** must not cover the header CTA; gate transfers only.

## Pitfalls for third-party implementers

- Cosmes `QRCodeModal` **will** `location.href` on mobile unless the patch + boot hook (`installWalletConnectPairingHook` in `main.tsx`) are both present. `npm ci` applies `patch-package`.
- Galaxy Station Android templates that look like `https://host/path#Intent;…` must be converted to `intent://` (`toAndroidIntentUri`) or Chrome opens a website.
- `window.keplr` is missing on Android Chrome — that is expected. Offer WalletConnect; do not leave a disabled “Not installed” Keplr row as the only Keplr path.
- Trust Wallet in-app: alias `window.trustwallet.cosmos` onto `window.keplr` only when `window.keplr` is absent. Chrome Android is not that path.
- NavBar renders the CTA three times (breakpoints). Tests must target the **visible** instance (`getByRole` visible, or `getByTestId` at a set viewport).
