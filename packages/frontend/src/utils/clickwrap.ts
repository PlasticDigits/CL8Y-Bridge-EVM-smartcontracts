/**
 * CL8Y Legal clickwrap constants and pure helpers (GL-134, INV-FE-CLICKWRAP-1).
 *
 * Property is always the production hostname. Signing for cl8y.com (or any other
 * host) does not satisfy bridge.cl8y.com. Do not derive property from
 * window.location.hostname.
 */

import type { Network } from '@plasticdigits/cl8y-clickwrap'
import {
  DEFAULT_API_BASE_URL,
  DEFAULT_TERMS_BASE_URL,
} from '@plasticdigits/cl8y-clickwrap'

/** Production Legal property for every status/sign call. */
export const BRIDGE_CLICKWRAP_PROPERTY = 'bridge.cl8y.com'

/** Portal `app_name` query — constant, never user-controlled. */
export const BRIDGE_CLICKWRAP_APP_NAME = 'CL8Y Bridge'

export type BridgeChainKind = 'evm' | 'cosmos' | 'solana'

export const CLICKWRAP_UNSIGNED_MESSAGE =
  'Accept the latest CL8Y Terms & Conditions before this action.'

export const CLICKWRAP_STATUS_ERROR_MESSAGE =
  'Unable to verify CL8Y Terms acceptance. Mutative actions stay disabled until status can be confirmed.'

/**
 * Map a bridge chain type to the Legal SDK Network.
 * Terra Classic (cosmos) → TerraClassic; never Telegram (no wallet path).
 */
export function clickwrapNetworkForChainKind(kind: BridgeChainKind): Network {
  if (kind === 'cosmos') return 'TerraClassic'
  if (kind === 'solana') return 'Solana'
  return 'EVM'
}

export function bridgeChainKindFromConfigType(
  type: 'evm' | 'cosmos' | 'solana' | undefined,
): BridgeChainKind {
  if (type === 'cosmos' || type === 'solana') return type
  return 'evm'
}

/**
 * Build the portal `redirect_uri` from the current page only.
 *
 * INV-FE-CLICKWRAP-1: never accept attacker-controlled redirect URLs (query
 * params, localStorage, or env). Same-origin `window.location.href` is the
 * only input; the hosted portal still enforces VITE_REDIRECT_URI_ALLOWLIST.
 */
export function sameOriginClickwrapRedirectUri(href: string): string {
  const trimmed = href.trim()
  if (!/^https?:\/\//i.test(trimmed)) {
    throw new Error('clickwrap redirect_uri must be an absolute http(s) URL')
  }
  const url = new URL(trimmed)
  if (url.protocol !== 'http:' && url.protocol !== 'https:') {
    throw new Error('clickwrap redirect_uri must be http(s)')
  }
  if (url.username || url.password) {
    throw new Error('clickwrap redirect_uri must not include credentials')
  }
  return url.href
}

/**
 * Optional public API/portal base override. Production ignores `http:` overrides
 * (fail closed to the SDK HTTPS defaults).
 */
export function resolveClickwrapBaseUrl(
  override: string | undefined,
  fallback: string,
  isProd: boolean,
): string {
  const trimmed = override?.trim()
  if (!trimmed) return fallback.replace(/\/$/, '')
  const normalized = trimmed.replace(/\/$/, '')
  if (isProd && /^http:/i.test(normalized)) {
    console.error(
      `[clickwrap] ignoring insecure production override; using ${fallback}`,
    )
    return fallback.replace(/\/$/, '')
  }
  return normalized
}

export function clickwrapClientConfig(env: {
  apiOverride?: string
  termsOverride?: string
  isProd: boolean
}): { apiBaseUrl: string; termsBaseUrl: string } {
  return {
    apiBaseUrl: resolveClickwrapBaseUrl(
      env.apiOverride,
      DEFAULT_API_BASE_URL,
      env.isProd,
    ),
    termsBaseUrl: resolveClickwrapBaseUrl(
      env.termsOverride,
      DEFAULT_TERMS_BASE_URL,
      env.isProd,
    ),
  }
}
