import { describe, it, expect, vi, beforeEach } from 'vitest'
import { renderHook } from '@testing-library/react'
import { useAccount } from 'wagmi'
import { useWallet } from './useWallet'
import { useSolanaWallet } from './useSolanaWallet'
import { useBridgeClickwrapAccount } from './useBridgeClickwrapAccount'

vi.mock('wagmi', () => ({
  useAccount: vi.fn(() => ({ isConnected: false, address: undefined })),
}))

vi.mock('./useWallet', () => ({
  useWallet: vi.fn(() => ({ connected: false, address: undefined })),
}))

vi.mock('./useSolanaWallet', () => ({
  useSolanaWallet: vi.fn(() => ({ connected: false, address: undefined })),
}))

const mockUseAccount = vi.mocked(useAccount)
const mockUseWallet = vi.mocked(useWallet)
const mockUseSolanaWallet = vi.mocked(useSolanaWallet)

describe('useBridgeClickwrapAccount', () => {
  beforeEach(() => {
    mockUseAccount.mockReturnValue({
      isConnected: false,
      address: undefined,
    } as unknown as ReturnType<typeof useAccount>)
    mockUseWallet.mockReturnValue({
      connected: false,
      address: undefined,
    } as unknown as ReturnType<typeof useWallet>)
    mockUseSolanaWallet.mockReturnValue({
      connected: false,
      address: undefined,
    } as unknown as ReturnType<typeof useSolanaWallet>)
  })

  it('maps EVM address to Network EVM', () => {
    mockUseAccount.mockReturnValue({
      isConnected: true,
      address: '0xabc',
    } as unknown as ReturnType<typeof useAccount>)
    const { result } = renderHook(() => useBridgeClickwrapAccount('evm'))
    expect(result.current).toEqual({ network: 'EVM', account: '0xabc' })
  })

  it('maps Terra address to Network TerraClassic', () => {
    mockUseWallet.mockReturnValue({
      connected: true,
      address: 'terra1abc',
    } as unknown as ReturnType<typeof useWallet>)
    const { result } = renderHook(() => useBridgeClickwrapAccount('cosmos'))
    expect(result.current).toEqual({ network: 'TerraClassic', account: 'terra1abc' })
  })

  it('maps Solana address to Network Solana', () => {
    mockUseSolanaWallet.mockReturnValue({
      connected: true,
      address: 'SoL11111111111111111111111111111111111111112',
    } as unknown as ReturnType<typeof useSolanaWallet>)
    const { result } = renderHook(() => useBridgeClickwrapAccount('solana'))
    expect(result.current).toEqual({
      network: 'Solana',
      account: 'SoL11111111111111111111111111111111111111112',
    })
  })

  it('returns null account when the relevant wallet is disconnected', () => {
    mockUseAccount.mockReturnValue({
      isConnected: true,
      address: '0xabc',
    } as unknown as ReturnType<typeof useAccount>)
    const { result } = renderHook(() => useBridgeClickwrapAccount('cosmos'))
    expect(result.current.account).toBeNull()
    expect(result.current.network).toBe('TerraClassic')
  })
})
