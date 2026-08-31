/**
 * Shared faucet / noneconomic test-token catalog.
 *
 * Source of truth for Settings → Faucet rows **and** Transfer picker ranking
 * (INV-FE-TOKEN-RANK-1, GL-136). Add a newly deployed faucet mint here so it
 * both appears in the faucet panel and sorts to the bottom of the Transfer
 * token picker.
 *
 * Local `lunc` (tLUNC) and `sol` (synthetic SOL) are faucet-claimable but
 * remain **economic** in the Transfer picker (`noneconomic: false`).
 *
 * Docs: docs/FRONTEND_BRIDGE_INVARIANTS.md
 * Skill: skills/agent-frontend-token-rank.md
 * Issue: https://gitlab.com/PlasticDigits/cl8y-bridge-monorepo/-/issues/136
 */

function viteString(key: string): string {
  const env = (import.meta as ImportMeta & { env?: Record<string, string | undefined> }).env
  const value = env?.[key]
  return typeof value === 'string' ? value.trim() : ''
}

export interface FaucetTokenConfig {
  symbol: string
  label: string
  addresses: Record<string, string>
  decimals: Record<string, number>
  /**
   * When false, faucet-claimable but ranked as economic in the Transfer picker
   * (local tLUNC / synthetic SOL). Default: noneconomic (bottom group).
   */
  noneconomic?: boolean
}

/** Mainnet testa Terra CW20 — ranking denylist. */
export const MAINNET_TESTA_TERRA =
  'terra16ahm9hn5teayt2as384zf3uudgqvmmwahqfh0v9e3kaslhu30l8q38ftvh'
/** Mainnet testb Terra CW20 — ranking denylist. */
export const MAINNET_TESTB_TERRA =
  'terra1vqfe2ake427depchntwwl6dvyfgxpu5qdlqzfjuznxvw6pqza0hqalc9g3'
/** Mainnet tdec Terra CW20 — ranking denylist. */
export const MAINNET_TDEC_TERRA =
  'terra1pa7jxtjcu3clmv0v8n2tfrtlfepneyv8pxa7zmhz50kj8unuv0zq37apvv'

export const MAINNET_TESTA_EVM = {
  bsc: '0x3557bfd147b35C2647EAFC05c8BE757ce84D5B1c',
  opbnb: '0xF073d5685594F465a66EA54516f0D2f76b6cc6F3',
  megaeth: '0x7deF34032CC5D06bA84A8889bdCA7ee153127B23',
} as const

export const MAINNET_TESTB_EVM = {
  bsc: '0x39c4a8d50Cdd20131eC91B3ACcc6352123F68B52',
  opbnb: '0xe1EaAC9be88D5fb89C944B46Bdc48fad2d47185e',
  megaeth: '0xE19442D99Aa2209b08d69c518444C4C1DAfeEDb1',
} as const

export const MAINNET_TDEC_EVM = {
  bsc: '0xe159c7a58d694fafba82221905d5a49e7f314330',
  opbnb: '0x6d66d16e6cb29351aee1960ba1c395c0fb1392dd',
  megaeth: '0x840b1515f586c2ea31d55C91B355AFf36eA7af54',
} as const

/**
 * Canonical mainnet SPL mints for testa / testb / tdec.
 * Always included in the ranking denylist even when `VITE_SOLANA_*_MINT` is unset,
 * so Solana-source picker rows still sort last. Faucet panel Solana rows still
 * require env (or these values if env is set) — see MAINNET_FAUCET_TOKENS.
 *
 * Addresses: docs/solana-mainnet-test-tokens-checklist.md
 */
export const MAINNET_NONECONOMIC_SPL_MINTS = {
  testa: '6XjWBbRJW5uhd8csCiDivXGPF42yYoyDARtxEtX3oP7E',
  testb: 'EvAWhkKQzX8om5VDWjg8oEvCw9jhGGKsn3rdrNXmQScX',
  tdec: '765GMcrKxfevfBhnJmZDhdyHDon2nTwGemcgqJApNBR',
} as const

/** Local QA faucet symbols that rank as noneconomic (not lunc / sol). */
export const LOCAL_NONECONOMIC_FAUCET_SYMBOLS = ['tkna', 'tknb', 'tknc', 'tdec'] as const

export const MAINNET_FAUCET_TOKENS: FaucetTokenConfig[] = [
  {
    symbol: 'testa',
    label: 'Test A (testa-cb)',
    addresses: {
      bsc: MAINNET_TESTA_EVM.bsc,
      opbnb: MAINNET_TESTA_EVM.opbnb,
      megaeth: MAINNET_TESTA_EVM.megaeth,
      terra: MAINNET_TESTA_TERRA,
      solana: viteString('VITE_SOLANA_TESTA_MINT') || '',
    },
    decimals: { bsc: 18, opbnb: 18, megaeth: 18, terra: 18, solana: 9 },
  },
  {
    symbol: 'testb',
    label: 'Test B (testb-cb)',
    addresses: {
      bsc: MAINNET_TESTB_EVM.bsc,
      opbnb: MAINNET_TESTB_EVM.opbnb,
      megaeth: MAINNET_TESTB_EVM.megaeth,
      terra: MAINNET_TESTB_TERRA,
      solana: viteString('VITE_SOLANA_TESTB_MINT') || '',
    },
    decimals: { bsc: 18, opbnb: 18, megaeth: 18, terra: 18, solana: 9 },
  },
  {
    symbol: 'tdec',
    label: 'Test Dec (tdec-cb)',
    addresses: {
      bsc: MAINNET_TDEC_EVM.bsc,
      opbnb: MAINNET_TDEC_EVM.opbnb,
      megaeth: MAINNET_TDEC_EVM.megaeth,
      terra: MAINNET_TDEC_TERRA,
      solana: viteString('VITE_SOLANA_TDEC_MINT') || '',
    },
    decimals: { bsc: 18, opbnb: 12, megaeth: 12, terra: 6, solana: 6 },
  },
]

export const LOCAL_FAUCET_TOKENS: FaucetTokenConfig[] = [
  {
    symbol: 'tkna',
    label: 'Token A (TKNA)',
    addresses: {
      anvil: viteString('VITE_ANVIL_TOKEN_A'),
      anvil1: viteString('VITE_ANVIL1_TOKEN_A'),
      localterra: viteString('VITE_TERRA_TOKEN_A'),
      'solana-localnet': viteString('VITE_SOLANA_TOKEN_A'),
    },
    decimals: { anvil: 18, anvil1: 18, localterra: 6, 'solana-localnet': 9 },
  },
  {
    symbol: 'tknb',
    label: 'Token B (TKNB)',
    addresses: {
      anvil: viteString('VITE_ANVIL_TOKEN_B'),
      anvil1: viteString('VITE_ANVIL1_TOKEN_B'),
      localterra: viteString('VITE_TERRA_TOKEN_B'),
      'solana-localnet': viteString('VITE_SOLANA_TOKEN_B'),
    },
    decimals: { anvil: 18, anvil1: 18, localterra: 6, 'solana-localnet': 9 },
  },
  {
    symbol: 'tknc',
    label: 'Token C (TKNC)',
    addresses: {
      anvil: viteString('VITE_ANVIL_TOKEN_C'),
      anvil1: viteString('VITE_ANVIL1_TOKEN_C'),
      localterra: viteString('VITE_TERRA_TOKEN_C'),
      'solana-localnet': viteString('VITE_SOLANA_TOKEN_C'),
    },
    decimals: { anvil: 18, anvil1: 18, localterra: 6, 'solana-localnet': 9 },
  },
  {
    symbol: 'tdec',
    label: 'Test Dec (KDEC)',
    addresses: {
      anvil: viteString('VITE_ANVIL_KDEC'),
      anvil1: viteString('VITE_ANVIL1_KDEC'),
      localterra: viteString('VITE_TERRA_KDEC'),
      'solana-localnet': viteString('VITE_SOLANA_KDEC'),
    },
    decimals: { anvil: 18, anvil1: 12, localterra: 6, 'solana-localnet': 9 },
  },
  {
    symbol: 'lunc',
    label: 'LUNC (tLUNC)',
    addresses: {
      anvil: viteString('VITE_ANVIL_LUNC'),
      anvil1: viteString('VITE_ANVIL1_LUNC'),
      localterra: '',
      'solana-localnet': viteString('VITE_SOLANA_LUNC'),
    },
    decimals: { anvil: 18, anvil1: 18, localterra: 6, 'solana-localnet': 6 },
    noneconomic: false,
  },
  {
    symbol: 'sol',
    label: 'Synthetic SOL',
    addresses: {
      anvil: viteString('VITE_ANVIL_SOL'),
      anvil1: viteString('VITE_ANVIL1_SOL'),
      localterra: viteString('VITE_TERRA_SOL'),
      'solana-localnet': viteString('VITE_SOLANA_WSOL'),
    },
    decimals: { anvil: 9, anvil1: 9, localterra: 9, 'solana-localnet': 9 },
    noneconomic: false,
  },
]
