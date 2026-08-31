/**
 * Headless Legal signature status for the wallet that performs a mutative action.
 *
 * Fail closed: allowsMutative is true only after a successful status read
 * with signed_latest, and never while a fetch is in flight.
 * No account → not a legal block (connect UX stays usable).
 */

import { useSignatureStatus } from '@plasticdigits/cl8y-clickwrap/react'
import { getClickwrapClient } from '../services/clickwrapClient'
import { BRIDGE_CLICKWRAP_PROPERTY } from '../utils/clickwrap'
import { useBridgeClickwrapAccount } from './useBridgeClickwrapAccount'
import type { BridgeChainKind } from '../utils/clickwrap'

export function useBridgeClickwrapGate(chainKind: BridgeChainKind) {
  const { network, account } = useBridgeClickwrapAccount(chainKind)
  const { status, loading, error, isSigned, refresh } = useSignatureStatus({
    client: getClickwrapClient(),
    property: BRIDGE_CLICKWRAP_PROPERTY,
    network,
    account,
  })

  return {
    network,
    account,
    status,
    loading,
    error,
    isSigned,
    refresh,
    /** True only after a successful status read with signed_latest (not while loading). */
    allowsMutative: Boolean(account && isSigned && !error && !loading),
  }
}
