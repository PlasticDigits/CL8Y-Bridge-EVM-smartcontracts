/**
 * Transfer token picker ranking: economic tokens first, known noneconomic
 * faucet tokens last (INV-FE-TOKEN-RANK-1, GL-136).
 *
 * Classification is a closed denylist of canonical ids (Terra denom/CW20,
 * EVM address, SPL mint) — never display `symbol`. Unknown registered tokens
 * default to the economic (top) group so a newly listed real asset is not buried.
 *
 * Display order only. Does not change which tokens are offered, mappings,
 * decimals, fees, or hash encoding.
 *
 * Docs: docs/FRONTEND_BRIDGE_INVARIANTS.md
 * Skill: skills/agent-frontend-token-rank.md
 * Catalog: ./faucetTokens.ts (shared with Settings → Faucet)
 * Issue: https://gitlab.com/PlasticDigits/cl8y-bridge-monorepo/-/issues/136
 */

import type { TokenOption } from '../types/tokenOption'
import type { TokenlistData } from '../services/tokenlist'
import {
  LOCAL_FAUCET_TOKENS,
  MAINNET_FAUCET_TOKENS,
  MAINNET_NONECONOMIC_SPL_MINTS,
  type FaucetTokenConfig,
} from './faucetTokens'

export function normalizeTokenId(id: string | undefined | null): string {
  if (!id) return ''
  return id.trim().toLowerCase()
}

function addId(set: Set<string>, value: string | undefined): void {
  const normalized = normalizeTokenId(value)
  if (normalized) set.add(normalized)
}

function addCatalogAddresses(set: Set<string>, token: FaucetTokenConfig): void {
  if (token.noneconomic === false) return
  for (const addr of Object.values(token.addresses)) {
    addId(set, addr)
  }
}

/** Closed noneconomic id set (lowercase). Built once from the shared faucet catalog. */
export function collectNoneconomicTokenIds(): Set<string> {
  const ids = new Set<string>()
  for (const token of MAINNET_FAUCET_TOKENS) {
    addCatalogAddresses(ids, token)
  }
  for (const mint of Object.values(MAINNET_NONECONOMIC_SPL_MINTS)) {
    addId(ids, mint)
  }
  for (const token of LOCAL_FAUCET_TOKENS) {
    addCatalogAddresses(ids, token)
  }
  return ids
}

let cachedNoneconomicIds: Set<string> | null = null

function noneconomicIds(): Set<string> {
  if (!cachedNoneconomicIds) {
    cachedNoneconomicIds = collectNoneconomicTokenIds()
  }
  return cachedNoneconomicIds
}

/**
 * True when any of id / tokenId / evmTokenAddress matches the noneconomic denylist.
 * Display symbol is ignored (spoofed `symbol: 'CL8Y'` on a test mint still ranks last).
 */
export function isNoneconomicBridgeToken(
  option: Pick<TokenOption, 'id' | 'tokenId'> & { evmTokenAddress?: string },
): boolean {
  const ids = noneconomicIds()
  const candidates = [option.id, option.tokenId, option.evmTokenAddress]
  return candidates.some((candidate) => {
    const normalized = normalizeTokenId(candidate)
    return normalized.length > 0 && ids.has(normalized)
  })
}

function tokenlistIndex(token: TokenOption, tokenlist: TokenlistData | null): number {
  if (!tokenlist?.tokens?.length) return Number.POSITIVE_INFINITY
  const keys = [token.id, token.tokenId, token.evmTokenAddress]
    .map(normalizeTokenId)
    .filter((k) => k.length > 0)
  const idx = tokenlist.tokens.findIndex((entry) => {
    const denom = normalizeTokenId(entry.denom)
    const address = normalizeTokenId(entry.address)
    return (denom && keys.includes(denom)) || (address && keys.includes(address))
  })
  return idx === -1 ? Number.POSITIVE_INFINITY : idx
}

export function compareTransferTokenRank(
  a: TokenOption,
  b: TokenOption,
  tokenlist: TokenlistData | null,
): number {
  const aTest = isNoneconomicBridgeToken(a) ? 1 : 0
  const bTest = isNoneconomicBridgeToken(b) ? 1 : 0
  if (aTest !== bTest) return aTest - bTest
  const aList = tokenlistIndex(a, tokenlist)
  const bList = tokenlistIndex(b, tokenlist)
  if (aList !== bList) return aList - bList
  const bySymbol = (a.symbol ?? '').localeCompare(b.symbol ?? '')
  if (bySymbol !== 0) return bySymbol
  return a.id.localeCompare(b.id)
}

/**
 * Stable economic-then-test sort. Does not mutate `tokens`. Does not add/remove
 * rows or swap identity fields (`id` / `tokenId` / `evmTokenAddress`).
 */
export function rankTransferTokens(
  tokens: readonly TokenOption[],
  tokenlist: TokenlistData | null,
): TokenOption[] {
  return tokens.slice().sort((a, b) => compareTransferTokenRank(a, b, tokenlist))
}

/**
 * Auto-select helper for TransferForm: keep an explicit still-valid id;
 * otherwise pick the first ranked token (economic if any exist).
 */
export function defaultTransferTokenId(
  tokens: readonly TokenOption[],
  currentId: string,
): string | undefined {
  if (tokens.length === 0) return undefined
  if (currentId && tokens.some((t) => t.id === currentId)) return currentId
  return tokens[0]?.id
}
