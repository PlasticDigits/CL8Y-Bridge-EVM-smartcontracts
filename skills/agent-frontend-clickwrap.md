# Agent skill: CL8Y Legal clickwrap (GL-134)

Use when wiring **deposit / withdraw-submit / withdraw-execute** CTAs, debugging **“Accept Terms”** vs missing Bridge buttons, Legal CORS failures, or **portal return** from `https://terms.cl8y.com`. Do **not** mount a full-page overlay over the header Connect controls (GL-137).

## Code map

| Concern | Location |
|---------|----------|
| Property, network map, same-origin `redirect_uri` | [`packages/frontend/src/utils/clickwrap.ts`](../packages/frontend/src/utils/clickwrap.ts) |
| Singleton `createClient` + submit-time `requireSignedLatest` | [`packages/frontend/src/services/clickwrapClient.ts`](../packages/frontend/src/services/clickwrapClient.ts) |
| Wallet → SDK `Network` + account | [`useBridgeClickwrapAccount`](../packages/frontend/src/hooks/useBridgeClickwrapAccount.ts) |
| Fail-closed `allowsMutative` | [`useBridgeClickwrapGate`](../packages/frontend/src/hooks/useBridgeClickwrapGate.ts) |
| `TermsGate` wrapper (children-swap, not overlay) | [`BridgeTermsGate`](../packages/frontend/src/components/transfer/BridgeTermsGate.tsx) |
| Deposit CTA | [`TransferForm`](../packages/frontend/src/components/transfer/TransferForm.tsx) |
| Dest hash submit / auto-submit | [`useAutoWithdrawSubmit`](../packages/frontend/src/hooks/useAutoWithdrawSubmit.ts), [`TransferStatusPage`](../packages/frontend/src/pages/TransferStatusPage.tsx) |
| Verify-page submit | [`HashVerificationPage`](../packages/frontend/src/pages/HashVerificationPage.tsx) |
| Solana execute | [`SolanaRecipientExecutePanel`](../packages/frontend/src/components/transfer/SolanaRecipientExecutePanel.tsx) |
| Playwright Legal mock | [`packages/frontend/e2e/fixtures/legal-clickwrap.ts`](../packages/frontend/e2e/fixtures/legal-clickwrap.ts) |

## Invariants

- **INV-FE-CLICKWRAP-1:** Mutative actions require Legal `signed_latest` for **`bridge.cl8y.com`** on the **current** account + network. Status errors fail closed. Connect UX stays outside the gate. See [FRONTEND_BRIDGE_INVARIANTS.md](../docs/FRONTEND_BRIDGE_INVARIANTS.md). Issue: https://gitlab.com/PlasticDigits/cl8y-bridge-monorepo/-/issues/134

## Pitfalls for third-party implementers

- Do **not** wrap `Layout` / `NavBar` with `TermsGate` — no account shows the SDK fallback and hides Connect (GL-137).
- Do **not** treat `?signed=1`, cookies, or localStorage as acceptance. Only `GET /api/v1/signatures/status`.
- Raw `ClickwrapClient.getSignatureStatus` expects API network strings (`EVM`, `TERRA_CLASSIC`, `SOLANA`); `TermsGate` / `useSignatureStatus` take SDK `Network` and map internally.
- Install `@plasticdigits/cl8y-clickwrap` from GitLab npm project **82547916** (see `packages/frontend/.npmrc`). It is **not** on npmjs.org.
- **Solana:** still gate (`Network: Solana`). Legal `/sign/solana` is not production-ready (sign envelope ≠ API verify). Do not silently skip Solana.
- Playwright: keep the default mock at `signed_latest: true` so transfer e2e is not flaky on Legal uptime.
