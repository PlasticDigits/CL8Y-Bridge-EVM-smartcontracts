/**
 * Shared ClickwrapClient for the bridge SPA (GL-134).
 *
 * One createClient() instance per page load. Status checks go to the Legal API;
 * signatures are created only on the hosted portal — this module never submits
 * wallet signatures and never treats localStorage / query-string as acceptance.
 */

import {
  createClient,
  NETWORK_API_VALUES,
  type ClickwrapClient,
  type Network,
  type StatusResponse,
} from '@plasticdigits/cl8y-clickwrap'
import {
  BRIDGE_CLICKWRAP_PROPERTY,
  CLICKWRAP_STATUS_ERROR_MESSAGE,
  CLICKWRAP_UNSIGNED_MESSAGE,
  clickwrapClientConfig,
} from '../utils/clickwrap'

let client: ClickwrapClient | null = null

/**
 * Transfer Status mounts TermsGate plus a headless useSignatureStatus for the
 * same account. Coalesce identical in-flight status GETs so load/focus does
 * not duplicate /signatures/status. Completed results are not cached — submit
 * re-check via requireSignedLatest always hits the network after in-flight work.
 */
function withInflightStatusCoalesce(inner: ClickwrapClient): ClickwrapClient {
  const inflight = new Map<string, Promise<StatusResponse>>()
  const getSignatureStatus: ClickwrapClient['getSignatureStatus'] = (
    property,
    network,
    account,
  ) => {
    const key = `${property}\0${network}\0${account}`
    const existing = inflight.get(key)
    if (existing) return existing
    const pending = inner.getSignatureStatus(property, network, account).finally(() => {
      inflight.delete(key)
    })
    inflight.set(key, pending)
    return pending
  }
  return { ...inner, getSignatureStatus }
}

function readEnvOverrides(): { apiOverride?: string; termsOverride?: string; isProd: boolean } {
  return {
    apiOverride: import.meta.env.VITE_CLICKWRAP_API_BASE_URL,
    termsOverride: import.meta.env.VITE_CLICKWRAP_TERMS_BASE_URL,
    isProd: import.meta.env.PROD,
  }
}

export function getClickwrapClient(): ClickwrapClient {
  if (!client) {
    client = withInflightStatusCoalesce(createClient(clickwrapClientConfig(readEnvOverrides())))
  }
  return client
}

/** Test-only: drop the singleton so the next getClickwrapClient() rebuilds. */
export function resetClickwrapClientForTests(): void {
  client = null
}

export class ClickwrapGateError extends Error {
  readonly code: 'unsigned' | 'status-error'

  constructor(code: 'unsigned' | 'status-error', message: string) {
    super(message)
    this.name = 'ClickwrapGateError'
    this.code = code
  }
}

/**
 * Fail-closed re-check immediately before a mutative wallet action.
 * UI gating is UX only; this is the in-app last line (Legal still requires a
 * real wallet signature on the portal — bypassing the button does not create one).
 */
export async function requireSignedLatest(network: Network, account: string): Promise<void> {
  const trimmed = account.trim()
  if (!trimmed) {
    throw new ClickwrapGateError('unsigned', CLICKWRAP_UNSIGNED_MESSAGE)
  }
  let signedLatest: boolean
  try {
    const status = await getClickwrapClient().getSignatureStatus(
      BRIDGE_CLICKWRAP_PROPERTY,
      NETWORK_API_VALUES[network],
      trimmed,
    )
    signedLatest = Boolean(status.signed_latest)
  } catch (err) {
    const detail = err instanceof Error ? err.message : String(err)
    throw new ClickwrapGateError(
      'status-error',
      `${CLICKWRAP_STATUS_ERROR_MESSAGE} (${detail})`,
    )
  }
  if (!signedLatest) {
    throw new ClickwrapGateError('unsigned', CLICKWRAP_UNSIGNED_MESSAGE)
  }
}
