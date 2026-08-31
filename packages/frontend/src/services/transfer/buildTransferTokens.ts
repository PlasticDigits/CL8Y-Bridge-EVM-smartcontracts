/**
 * Build token dropdown options for the transfer form (direction-aware).
 *
 * EVM source: waits for `token_dest_mapping` queries before showing the legacy
 * EVM-address fallback row — avoids glab #89 style hash mismatches when users
 * bridge before mappings resolve.
 *
 * After filter, options are ranked economic-then-test (INV-FE-TOKEN-RANK-1,
 * GL-136) so TransferForm's `transferTokens[0]` default is an economic token
 * when any exist. Sort is display-only — identity fields are unchanged.
 */

import { getAddress, type Address } from 'viem'
import type { TokenOption } from '../../types/tokenOption'
import { getTokenFromList, type TokenlistData } from '../tokenlist'
import { getTokenDisplaySymbol } from '../../utils/tokenLogos'
import { rankTransferTokens } from '../../utils/tokenEconomicRank'

type RegistryToken = {
  token: string
  is_native: boolean
  evm_token_address?: string
  terra_decimals: number
  evm_decimals?: number
  enabled: boolean
}

/** Decode registry bytes32 / hex token field to checksummed EVM address. */
function registryBytes32ToAddress(hex: string): Address {
  const clean = hex.replace(/^0x/, '').toLowerCase()
  if (!/^[0-9a-f]*$/.test(clean) || clean.length < 40) {
    return '0x0000000000000000000000000000000000000000' as Address
  }
  const addr = clean.length > 40 ? clean.slice(-40) : clean
  try {
    return getAddress(`0x${addr}`)
  } catch {
    return '0x0000000000000000000000000000000000000000' as Address
  }
}

export function buildTransferTokens(
  registryTokens: RegistryToken[] | undefined,
  isSourceTerra: boolean,
  isSourceSolana: boolean,
  fallbackConfig: { address: Address; symbol: string; decimals: number } | undefined,
  tokenlist: TokenlistData | null,
  /** When source is EVM: per-chain token address from Terra token_dest_mapping */
  sourceChainMappings?: Record<string, string>,
  /** When source is Terra or Solana: only tokens with a dest mapping on the selected chain */
  destChainMappings?: Record<string, string>,
  /**
   * When true, EVM source mappings are still loading — return no options yet
   * (do not show EVM-address fallback until queries settle).
   */
  evmTokenMappingsLoading?: boolean,
): TokenOption[] {
  const symbolFromList = (token: string) =>
    tokenlist ? getTokenFromList(tokenlist, token)?.symbol : null

  if (isSourceTerra || isSourceSolana) {
    if (!tokenlist) return []
    let enabledTokens = (registryTokens ?? []).filter((t) => t.enabled)
    if (destChainMappings && Object.keys(destChainMappings).length > 0) {
      enabledTokens = enabledTokens.filter((t) => t.token in destChainMappings)
    }
    const fromRegistry = enabledTokens.map((t) => ({
      id: t.token,
      symbol: symbolFromList(t.token) ?? getTokenDisplaySymbol(t.token),
      tokenId: t.token,
    }))
    return rankTransferTokens(fromRegistry, tokenlist)
  }

  if (!tokenlist) return []

  const isEvmSource = !isSourceTerra && !isSourceSolana
  if (isEvmSource && evmTokenMappingsLoading) {
    return []
  }

  if (sourceChainMappings && Object.keys(sourceChainMappings).length > 0) {
    const mapped = Object.entries(sourceChainMappings).map(([terraToken, evmAddr]) => {
      const reg = registryTokens?.find((t) => t.token === terraToken)
      return {
        id: terraToken,
        symbol: symbolFromList(terraToken) ?? getTokenDisplaySymbol(reg?.token ?? terraToken),
        tokenId: terraToken,
        evmTokenAddress: evmAddr,
      }
    })
    return rankTransferTokens(mapped, tokenlist)
  }

  const baseRegistry = (registryTokens ?? []).filter((t) => t.enabled && t.evm_token_address)
  if (baseRegistry.length > 0) {
    const fallbackMapped = baseRegistry.map((t) => ({
      id: t.token,
      symbol: symbolFromList(t.token) ?? getTokenDisplaySymbol(t.token),
      tokenId: t.token,
      evmTokenAddress: registryBytes32ToAddress(t.evm_token_address!),
    }))
    return rankTransferTokens(fallbackMapped, tokenlist)
  }

  if (fallbackConfig && !sourceChainMappings) {
    return rankTransferTokens(
      [{ id: fallbackConfig.address, symbol: fallbackConfig.symbol, tokenId: fallbackConfig.address }],
      tokenlist,
    )
  }
  return []
}
