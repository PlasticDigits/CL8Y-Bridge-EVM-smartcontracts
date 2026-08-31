/**
 * Wrap mutative bridge controls with the Legal SDK TermsGate (GL-134).
 *
 * When no wallet account is available, children render unchanged so Connect
 * controls stay usable (INV-FE-CLICKWRAP-1, related GL-137).
 * TermsGate is not mounted on the app shell / header.
 */

import { useMemo, type ReactNode } from 'react'
import { TermsGate } from '@plasticdigits/cl8y-clickwrap/react'
import { getClickwrapClient } from '../../services/clickwrapClient'
import { useBridgeClickwrapAccount } from '../../hooks/useBridgeClickwrapAccount'
import {
  BRIDGE_CLICKWRAP_APP_NAME,
  BRIDGE_CLICKWRAP_PROPERTY,
  sameOriginClickwrapRedirectUri,
  type BridgeChainKind,
} from '../../utils/clickwrap'

export interface BridgeTermsGateProps {
  chainKind: BridgeChainKind
  children: ReactNode
}

export function BridgeTermsGate({ chainKind, children }: BridgeTermsGateProps) {
  const { network, account } = useBridgeClickwrapAccount(chainKind)
  const redirectUri = useMemo(() => {
    if (typeof window === 'undefined') return undefined
    try {
      return sameOriginClickwrapRedirectUri(window.location.href)
    } catch {
      return undefined
    }
  }, [])

  if (!account) {
    return <>{children}</>
  }

  return (
    <div className="cl8y-bridge-terms-gate" data-testid="bridge-terms-gate">
      <TermsGate
        client={getClickwrapClient()}
        property={BRIDGE_CLICKWRAP_PROPERTY}
        network={network}
        account={account}
        redirectUri={redirectUri}
        appName={BRIDGE_CLICKWRAP_APP_NAME}
        fallback={
          <p className="text-sm text-slate-300" data-testid="bridge-terms-checking">
            Checking CL8Y Terms acceptance…
          </p>
        }
      >
        {children}
      </TermsGate>
    </div>
  )
}
