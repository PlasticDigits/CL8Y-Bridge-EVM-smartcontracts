/**
 * Resolve the Legal clickwrap account for the wallet that must sign a mutative action.
 */

import { useAccount } from 'wagmi'
import { useWallet } from './useWallet'
import { useSolanaWallet } from './useSolanaWallet'
import {
  clickwrapNetworkForChainKind,
  type BridgeChainKind,
} from '../utils/clickwrap'
import type { Network } from '@plasticdigits/cl8y-clickwrap'

export interface BridgeClickwrapAccount {
  network: Network
  account: string | null
}

export function useBridgeClickwrapAccount(chainKind: BridgeChainKind): BridgeClickwrapAccount {
  const { address: evmAddress, isConnected: isEvmConnected } = useAccount()
  const { address: terraAddress, connected: isTerraConnected } = useWallet()
  const { address: solanaAddress, connected: isSolanaConnected } = useSolanaWallet()
  const network = clickwrapNetworkForChainKind(chainKind)

  if (chainKind === 'cosmos') {
    return {
      network,
      account: isTerraConnected && terraAddress ? terraAddress : null,
    }
  }
  if (chainKind === 'solana') {
    return {
      network,
      account: isSolanaConnected && solanaAddress ? solanaAddress : null,
    }
  }
  return {
    network,
    account: isEvmConnected && evmAddress ? evmAddress : null,
  }
}
