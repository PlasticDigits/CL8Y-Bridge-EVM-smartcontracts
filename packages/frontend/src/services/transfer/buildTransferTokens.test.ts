import { describe, it, expect } from 'vitest'
import { buildTransferTokens } from './buildTransferTokens'
import type { TokenlistData } from '../tokenlist'
import {
  MAINNET_TESTA_EVM,
  MAINNET_TESTA_TERRA,
  MAINNET_TESTB_TERRA,
} from '../../utils/faucetTokens'
import { defaultTransferTokenId, isNoneconomicBridgeToken } from '../../utils/tokenEconomicRank'

const CL8Y_CW20 = 'terra16wtml2q66g82fdkx66tap0qjkahqwp4lwq3ngtygacg5q0kzycgqvhpax3'
const UNKNOWN_CW20 = 'terra1unknownregisteredasseteconomicxxxxxxxxxxxxxxxxxxxx'

const tokenlist: TokenlistData = {
  name: 't',
  version: '1',
  tokens: [
    { symbol: 'USTC', name: 'TerraClassicUSD', denom: 'uusd', type: 'native' },
    { symbol: 'LUNC', name: 'Luna', denom: 'uluna', type: 'native' },
    { symbol: 'CL8Y', name: 'CL8Y', address: CL8Y_CW20, type: 'cw20' },
  ],
}

const registry = [
  {
    token: 'uluna',
    is_native: true,
    terra_decimals: 6,
    enabled: true,
  },
]

function row(
  token: string,
  extra: { enabled?: boolean; evm_token_address?: string; is_native?: boolean } = {},
) {
  return {
    token,
    is_native: extra.is_native ?? false,
    terra_decimals: 6,
    enabled: extra.enabled ?? true,
    evm_token_address: extra.evm_token_address,
  }
}

describe('buildTransferTokens', () => {
  it('returns empty while EVM token_dest_mapping queries are loading', () => {
    expect(
      buildTransferTokens(
        registry,
        false,
        false,
        { address: '0x5FbDB2315678afecb367f032d93F642f64180aa3', symbol: 'TK', decimals: 18 },
        tokenlist,
        undefined,
        undefined,
        true,
      ),
    ).toEqual([])
  })

  it('shows mapped Terra tokens after loading completes', () => {
    const opts = buildTransferTokens(
      registry,
      false,
      false,
      { address: '0x5FbDB2315678afecb367f032d93F642f64180aa3', symbol: 'TK', decimals: 18 },
      tokenlist,
      { uluna: '0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266' },
      undefined,
      false,
    )
    expect(opts.length).toBe(1)
    expect(opts[0]!.id).toBe('uluna')
  })

  it('does not use EVM-address fallback while loading even if fallbackConfig exists', () => {
    expect(
      buildTransferTokens(
        undefined,
        false,
        false,
        { address: '0x5FbDB2315678afecb367f032d93F642f64180aa3', symbol: 'TK', decimals: 18 },
        tokenlist,
        undefined,
        undefined,
        true,
      ),
    ).toEqual([])
  })

  it('Terra/Solana path: mixed set ranks economic then test; disabled excluded before sort', () => {
    const opts = buildTransferTokens(
      [
        row(MAINNET_TESTA_TERRA),
        row('uluna', { is_native: true }),
        row(MAINNET_TESTB_TERRA, { enabled: false }),
        row(CL8Y_CW20),
        row('disabled-econ', { enabled: false }),
      ],
      true,
      false,
      undefined,
      tokenlist,
    )
    expect(opts.map((t) => t.id)).toEqual(['uluna', CL8Y_CW20, MAINNET_TESTA_TERRA])
    expect(opts.some((t) => t.id === MAINNET_TESTB_TERRA)).toBe(false)
  })

  it('Terra path with dest filter still ranks the filtered set', () => {
    const opts = buildTransferTokens(
      [row(MAINNET_TESTA_TERRA), row('uluna', { is_native: true }), row(CL8Y_CW20)],
      true,
      false,
      undefined,
      tokenlist,
      undefined,
      { [MAINNET_TESTA_TERRA]: '1', uluna: '1' },
    )
    expect(opts.map((t) => t.id)).toEqual(['uluna', MAINNET_TESTA_TERRA])
  })

  it('EVM-source path ignores mapping insertion order', () => {
    const mappings = {
      [MAINNET_TESTA_TERRA]: MAINNET_TESTA_EVM.bsc,
      uluna: '0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266',
      [CL8Y_CW20]: '0xfBAa45A537cF07dC768c469FfaC4e88208B0098D',
    }
    const opts = buildTransferTokens(
      [row(MAINNET_TESTA_TERRA), row('uluna', { is_native: true }), row(CL8Y_CW20)],
      false,
      false,
      undefined,
      tokenlist,
      mappings,
      undefined,
      false,
    )
    expect(opts.map((t) => t.id)).toEqual(['uluna', CL8Y_CW20, MAINNET_TESTA_TERRA])
    expect(opts.find((t) => t.id === MAINNET_TESTA_TERRA)?.evmTokenAddress).toBe(MAINNET_TESTA_EVM.bsc)
    expect(opts.find((t) => t.id === 'uluna')?.evmTokenAddress).toBe(
      '0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266',
    )
  })

  it('EVM-source mixed-case 0x still classifies as test', () => {
    const opts = buildTransferTokens(
      [row('uluna', { is_native: true }), row(MAINNET_TESTA_TERRA)],
      false,
      false,
      undefined,
      tokenlist,
      {
        uluna: '0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266',
        [MAINNET_TESTA_TERRA]: MAINNET_TESTA_EVM.bsc.toUpperCase(),
      },
      undefined,
      false,
    )
    expect(opts[0]!.id).toBe('uluna')
    expect(isNoneconomicBridgeToken(opts[1]!)).toBe(true)
  })

  it('registry fallback path (evm_token_address) uses the same comparator', () => {
    const opts = buildTransferTokens(
      [
        row(MAINNET_TESTA_TERRA, { evm_token_address: MAINNET_TESTA_EVM.bsc }),
        row('uluna', { is_native: true, evm_token_address: '0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266' }),
      ],
      false,
      false,
      undefined,
      tokenlist,
      undefined,
      undefined,
      false,
    )
    expect(opts.map((t) => t.id)).toEqual(['uluna', MAINNET_TESTA_TERRA])
    expect(opts[0]!.evmTokenAddress?.toLowerCase()).toBe(
      '0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266'.toLowerCase(),
    )
  })

  it('unknown token on Terra path sorts with economic; default is that id when first', () => {
    const opts = buildTransferTokens(
      [row(MAINNET_TESTA_TERRA), row(UNKNOWN_CW20)],
      true,
      false,
      undefined,
      tokenlist,
    )
    expect(opts[0]!.id).toBe(UNKNOWN_CW20)
    expect(defaultTransferTokenId(opts, '')).toBe(UNKNOWN_CW20)
  })

  it('does not invent duplicate ids', () => {
    const opts = buildTransferTokens(
      [row('uluna', { is_native: true }), row(MAINNET_TESTA_TERRA)],
      true,
      false,
      undefined,
      tokenlist,
    )
    const ids = opts.map((t) => t.id)
    expect(new Set(ids).size).toBe(ids.length)
  })

  it('returns empty when tokenlist is missing (unchanged loading/gating)', () => {
    expect(buildTransferTokens(registry, true, false, undefined, null)).toEqual([])
    expect(buildTransferTokens(registry, false, false, undefined, null, { uluna: '0x1' })).toEqual([])
  })
})
