/**
 * INV-FE-TOKEN-RANK-1 (GL-136) — economic-then-test Transfer picker ranking.
 */

import { describe, it, expect } from 'vitest'
import type { TokenOption } from '../types/tokenOption'
import type { TokenlistData } from '../services/tokenlist'
import {
  collectNoneconomicTokenIds,
  compareTransferTokenRank,
  defaultTransferTokenId,
  isNoneconomicBridgeToken,
  normalizeTokenId,
  rankTransferTokens,
} from './tokenEconomicRank'
import {
  LOCAL_FAUCET_TOKENS,
  LOCAL_NONECONOMIC_FAUCET_SYMBOLS,
  MAINNET_FAUCET_TOKENS,
  MAINNET_NONECONOMIC_SPL_MINTS,
  MAINNET_TDEC_EVM,
  MAINNET_TDEC_TERRA,
  MAINNET_TESTA_EVM,
  MAINNET_TESTA_TERRA,
  MAINNET_TESTB_EVM,
  MAINNET_TESTB_TERRA,
} from './faucetTokens'

const CL8Y_CW20 = 'terra16wtml2q66g82fdkx66tap0qjkahqwp4lwq3ngtygacg5q0kzycgqvhpax3'
const CL8Y_CB_EVM = '0xfBAa45A537cF07dC768c469FfaC4e88208B0098D'
const UNKNOWN_CW20 = 'terra1unknownregisteredasseteconomicxxxxxxxxxxxxxxxxxxxx'

const tokenlist: TokenlistData = {
  name: 't',
  version: '1',
  tokens: [
    { symbol: 'USTC', name: 'TerraClassicUSD', denom: 'uusd', type: 'native' },
    { symbol: 'LUNC', name: 'Luna', denom: 'uluna', type: 'native' },
    { symbol: 'CL8Y', name: 'CL8Y', address: CL8Y_CW20, type: 'cw20' },
    { symbol: 'CL8Y-cb', name: 'CL8Y-cb', address: CL8Y_CB_EVM, type: 'evm' },
  ],
}

function opt(
  id: string,
  symbol: string,
  extra: Partial<TokenOption> = {},
): TokenOption {
  return { id, symbol, tokenId: extra.tokenId ?? id, ...extra }
}

describe('normalizeTokenId', () => {
  it('lowercases and trims', () => {
    expect(normalizeTokenId(`  ${MAINNET_TESTA_EVM.bsc}  `)).toBe(MAINNET_TESTA_EVM.bsc.toLowerCase())
  })

  it('returns empty for missing', () => {
    expect(normalizeTokenId(undefined)).toBe('')
    expect(normalizeTokenId('')).toBe('')
  })
})

describe('isNoneconomicBridgeToken', () => {
  it('classifies mainnet Terra CW20s as noneconomic regardless of display symbol', () => {
    expect(isNoneconomicBridgeToken(opt(MAINNET_TESTA_TERRA, 'CL8Y'))).toBe(true)
    expect(isNoneconomicBridgeToken(opt(MAINNET_TESTB_TERRA, 'LUNC'))).toBe(true)
    expect(isNoneconomicBridgeToken(opt(MAINNET_TDEC_TERRA, 'tdec'))).toBe(true)
  })

  it('classifies mixed-case EVM aliases as noneconomic', () => {
    expect(
      isNoneconomicBridgeToken(
        opt('uluna', 'LUNC', { evmTokenAddress: MAINNET_TESTA_EVM.bsc }),
      ),
    ).toBe(true)
    expect(
      isNoneconomicBridgeToken(
        opt(MAINNET_TESTA_EVM.opbnb.toUpperCase(), 'testa'),
      ),
    ).toBe(true)
  })

  it('classifies canonical SPL mints as noneconomic', () => {
    expect(isNoneconomicBridgeToken(opt(MAINNET_NONECONOMIC_SPL_MINTS.testa, 'testa'))).toBe(true)
    expect(isNoneconomicBridgeToken(opt(MAINNET_NONECONOMIC_SPL_MINTS.testb, 'testb'))).toBe(true)
    expect(isNoneconomicBridgeToken(opt(MAINNET_NONECONOMIC_SPL_MINTS.tdec, 'tdec'))).toBe(true)
  })

  it('does not trust spoofed testa symbol on an economic mint', () => {
    expect(isNoneconomicBridgeToken(opt(CL8Y_CW20, 'testa'))).toBe(false)
    expect(isNoneconomicBridgeToken(opt('uluna', 'testa'))).toBe(false)
  })

  it('treats unknown registry ids as economic', () => {
    expect(isNoneconomicBridgeToken(opt(UNKNOWN_CW20, 'FAKECL8Y'))).toBe(false)
  })

  it('does not classify local tLUNC / synthetic SOL faucet rows as noneconomic', () => {
    const lunc = LOCAL_FAUCET_TOKENS.find((t) => t.symbol === 'lunc')
    const sol = LOCAL_FAUCET_TOKENS.find((t) => t.symbol === 'sol')
    for (const addr of Object.values({ ...lunc?.addresses, ...sol?.addresses })) {
      if (addr) {
        expect(isNoneconomicBridgeToken(opt(addr, 'LUNC'))).toBe(false)
      }
    }
  })

  it('classifies local QA tkna/tknb/tknc/kdec addresses when env is populated', () => {
    const localNoneconomic = LOCAL_FAUCET_TOKENS.filter((t) =>
      (LOCAL_NONECONOMIC_FAUCET_SYMBOLS as readonly string[]).includes(t.symbol),
    )
    const addrs = localNoneconomic.flatMap((t) => Object.values(t.addresses).filter(Boolean))
    for (const addr of addrs) {
      expect(isNoneconomicBridgeToken(opt(addr, 'CL8Y'))).toBe(true)
    }
  })
})

describe('rankTransferTokens', () => {
  it('mixed set: economic first (tokenlist order), then test (stable by symbol)', () => {
    const input = [
      opt(MAINNET_TESTA_TERRA, 'testa'),
      opt('uluna', 'LUNC'),
      opt(MAINNET_TESTB_TERRA, 'testb'),
      opt(CL8Y_CW20, 'CL8Y'),
    ]
    const ranked = rankTransferTokens(input, tokenlist)
    expect(ranked.map((t) => t.id)).toEqual([
      'uluna',
      CL8Y_CW20,
      MAINNET_TESTA_TERRA,
      MAINNET_TESTB_TERRA,
    ])
  })

  it('economic only: tokenlist order, no holes', () => {
    const input = [opt(CL8Y_CW20, 'CL8Y'), opt('uluna', 'LUNC'), opt('uusd', 'USTC')]
    const ranked = rankTransferTokens(input, tokenlist)
    expect(ranked.map((t) => t.id)).toEqual(['uusd', 'uluna', CL8Y_CW20])
  })

  it('test only: all remain; first item is a test token', () => {
    const input = [
      opt(MAINNET_TESTB_TERRA, 'testb'),
      opt(MAINNET_TESTA_TERRA, 'testa'),
      opt(MAINNET_TDEC_TERRA, 'tdec'),
    ]
    const ranked = rankTransferTokens(input, tokenlist)
    expect(ranked).toHaveLength(3)
    expect(isNoneconomicBridgeToken(ranked[0]!)).toBe(true)
    expect(ranked.map((t) => t.id).sort()).toEqual(
      [MAINNET_TESTA_TERRA, MAINNET_TESTB_TERRA, MAINNET_TDEC_TERRA].sort(),
    )
  })

  it('unknown registry id sorts with economic (top)', () => {
    const ranked = rankTransferTokens(
      [opt(MAINNET_TESTA_TERRA, 'testa'), opt(UNKNOWN_CW20, 'NEW')],
      tokenlist,
    )
    expect(ranked[0]!.id).toBe(UNKNOWN_CW20)
    expect(ranked[1]!.id).toBe(MAINNET_TESTA_TERRA)
  })

  it('spoof: test CW20 with symbol CL8Y still ranks last', () => {
    const ranked = rankTransferTokens(
      [opt(MAINNET_TESTA_TERRA, 'CL8Y'), opt('uluna', 'LUNC')],
      tokenlist,
    )
    expect(ranked.map((t) => t.id)).toEqual(['uluna', MAINNET_TESTA_TERRA])
  })

  it('spoof: CL8Y CW20 with symbol testa still ranks first', () => {
    const ranked = rankTransferTokens(
      [opt(MAINNET_TESTA_TERRA, 'testa'), opt(CL8Y_CW20, 'testa')],
      tokenlist,
    )
    expect(ranked.map((t) => t.id)).toEqual([CL8Y_CW20, MAINNET_TESTA_TERRA])
  })

  it('does not mutate input or swap identity fields', () => {
    const a = opt(MAINNET_TESTA_TERRA, 'testa', { evmTokenAddress: MAINNET_TESTA_EVM.bsc })
    const b = opt('uluna', 'LUNC', { evmTokenAddress: '0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266' })
    const input = [a, b]
    const snapshot = input.map((t) => ({ ...t }))
    const ranked = rankTransferTokens(input, tokenlist)
    expect(input.map((t) => t.id)).toEqual(snapshot.map((t) => t.id))
    expect(ranked.find((t) => t.id === a.id)?.evmTokenAddress).toBe(a.evmTokenAddress)
    expect(ranked.find((t) => t.id === b.id)?.evmTokenAddress).toBe(b.evmTokenAddress)
    expect(ranked[0]).toBe(b)
    expect(ranked[1]).toBe(a)
  })

  it('empty list stays empty', () => {
    expect(rankTransferTokens([], tokenlist)).toEqual([])
  })

  it('two loads of the same set produce the same order (insertion order ignored)', () => {
    const setA = [
      opt(MAINNET_TESTA_TERRA, 'testa'),
      opt('uluna', 'LUNC'),
      opt(CL8Y_CW20, 'CL8Y'),
    ]
    const setB = [
      opt(CL8Y_CW20, 'CL8Y'),
      opt(MAINNET_TESTA_TERRA, 'testa'),
      opt('uluna', 'LUNC'),
    ]
    expect(rankTransferTokens(setA, tokenlist).map((t) => t.id)).toEqual(
      rankTransferTokens(setB, tokenlist).map((t) => t.id),
    )
  })

  it('closed denylist: empty match would leave everything economic', () => {
    const onlyEconomic = [opt('uluna', 'LUNC'), opt('uusd', 'USTC')]
    expect(onlyEconomic.every((t) => !isNoneconomicBridgeToken(t))).toBe(true)
    expect(rankTransferTokens(onlyEconomic, tokenlist).map((t) => t.id)).toEqual(['uusd', 'uluna'])
  })
})

describe('defaultTransferTokenId', () => {
  const mixed = rankTransferTokens(
    [opt(MAINNET_TESTA_TERRA, 'testa'), opt('uluna', 'LUNC')],
    tokenlist,
  )

  it('empty current id selects first economic', () => {
    expect(defaultTransferTokenId(mixed, '')).toBe('uluna')
  })

  it('keeps an explicit still-valid test token', () => {
    expect(defaultTransferTokenId(mixed, MAINNET_TESTA_TERRA)).toBe(MAINNET_TESTA_TERRA)
  })

  it('jumps to first remaining when current id drops out of the filtered set', () => {
    const withoutTest = mixed.filter((t) => t.id !== MAINNET_TESTA_TERRA)
    expect(defaultTransferTokenId(withoutTest, MAINNET_TESTA_TERRA)).toBe('uluna')
  })

  it('test-only list defaults to first test token', () => {
    const testOnly = rankTransferTokens([opt(MAINNET_TESTA_TERRA, 'testa')], tokenlist)
    expect(defaultTransferTokenId(testOnly, '')).toBe(MAINNET_TESTA_TERRA)
  })

  it('empty tokens yields undefined', () => {
    expect(defaultTransferTokenId([], '')).toBeUndefined()
  })
})

describe('compareTransferTokenRank', () => {
  it('is a consistent comparator for Array.sort', () => {
    const a = opt('uluna', 'LUNC')
    const b = opt(MAINNET_TESTA_TERRA, 'testa')
    expect(compareTransferTokenRank(a, b, tokenlist)).toBeLessThan(0)
    expect(compareTransferTokenRank(b, a, tokenlist)).toBeGreaterThan(0)
    expect(compareTransferTokenRank(a, a, tokenlist)).toBe(0)
  })
})

describe('collectNoneconomicTokenIds catalog sync', () => {
  const ids = collectNoneconomicTokenIds()

  it('includes every non-empty MAINNET_FAUCET_TOKENS address', () => {
    for (const token of MAINNET_FAUCET_TOKENS) {
      for (const addr of Object.values(token.addresses)) {
        if (addr) expect(ids.has(addr.toLowerCase())).toBe(true)
      }
    }
  })

  it('includes hardcoded SPL mints even when faucet solana env is empty', () => {
    expect(ids.has(MAINNET_NONECONOMIC_SPL_MINTS.testa.toLowerCase())).toBe(true)
    expect(ids.has(MAINNET_NONECONOMIC_SPL_MINTS.testb.toLowerCase())).toBe(true)
    expect(ids.has(MAINNET_NONECONOMIC_SPL_MINTS.tdec.toLowerCase())).toBe(true)
  })

  it('includes local noneconomic faucet addresses and excludes lunc/sol', () => {
    for (const token of LOCAL_FAUCET_TOKENS) {
      for (const addr of Object.values(token.addresses)) {
        if (!addr) continue
        if (token.noneconomic === false) {
          expect(ids.has(addr.toLowerCase())).toBe(false)
        } else {
          expect(ids.has(addr.toLowerCase())).toBe(true)
        }
      }
    }
  })

  it('mainnet catalog is testa/testb/tdec; local noneconomic symbols stay in sync', () => {
    expect(MAINNET_FAUCET_TOKENS.map((t) => t.symbol)).toEqual(['testa', 'testb', 'tdec'])
    expect([...LOCAL_NONECONOMIC_FAUCET_SYMBOLS]).toEqual(['tkna', 'tknb', 'tknc', 'tdec'])
    expect(LOCAL_FAUCET_TOKENS.filter((t) => t.noneconomic === false).map((t) => t.symbol)).toEqual([
      'lunc',
      'sol',
    ])
  })

  it('exposes mainnet EVM aliases used by FaucetPanel', () => {
    expect(ids.has(MAINNET_TESTA_EVM.megaeth.toLowerCase())).toBe(true)
    expect(ids.has(MAINNET_TESTB_EVM.bsc.toLowerCase())).toBe(true)
    expect(ids.has(MAINNET_TDEC_EVM.opbnb.toLowerCase())).toBe(true)
  })
})
