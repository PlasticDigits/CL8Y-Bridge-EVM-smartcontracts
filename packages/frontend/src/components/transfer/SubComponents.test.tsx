/**
 * Transfer Sub-Component Tests
 *
 * Tests for SourceChainSelector, DestChainSelector, AmountInput,
 * RecipientInput, FeeBreakdown, SwapDirectionButton.
 */

import { describe, it, expect, vi } from 'vitest'
import { render, screen, fireEvent } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { SourceChainSelector } from './SourceChainSelector'

vi.mock('../../hooks/useTokenList', () => ({
  useTokenList: () => ({ data: null }),
}))

vi.mock('../../hooks/useTokenDisplayInfo', () => ({
  useTerraTokenDisplayInfo: () => ({ displayLabel: 'LUNC', symbol: 'LUNC', addressForBlockie: undefined, hasLogo: true }),
  useEvmTokenDisplayInfo: () => ({ displayLabel: '', symbol: '', hasLogo: false }),
  useTokenOptionsDisplayMap: () => ({}),
}))

import { DestChainSelector } from './DestChainSelector'
import { AmountInput } from './AmountInput'
import { RecipientInput } from './RecipientInput'
import { FeeBreakdown } from './FeeBreakdown'
import { SwapDirectionButton } from './SwapDirectionButton'
import { TokenSelect } from './TokenSelect'

const mockChains = [
  { id: 'ethereum', name: 'Ethereum', chainId: 1, type: 'evm' as const, icon: '⟠', rpcUrl: '', explorerUrl: '', nativeCurrency: { name: 'Ether', symbol: 'ETH', decimals: 18 } },
  { id: 'bsc', name: 'BNB Chain', chainId: 56, type: 'evm' as const, icon: '⬡', rpcUrl: '', explorerUrl: '', nativeCurrency: { name: 'BNB', symbol: 'BNB', decimals: 18 } },
]

describe('SourceChainSelector', () => {
  it('should render with label "From"', () => {
    render(<SourceChainSelector chains={mockChains} value="ethereum" onChange={() => {}} />)
    expect(screen.getByText('From')).toBeInTheDocument()
  })

  it('should render chain options', async () => {
    const user = userEvent.setup()
    render(<SourceChainSelector chains={mockChains} value="ethereum" onChange={() => {}} />)
    expect(screen.getByText(/Ethereum/)).toBeInTheDocument()
    await user.click(screen.getByRole('combobox'))
    expect(screen.getByText(/BNB Chain/)).toBeInTheDocument()
  })

  it('should call onChange when selection changes', async () => {
    const user = userEvent.setup()
    const onChange = vi.fn()
    render(<SourceChainSelector chains={mockChains} value="ethereum" onChange={onChange} />)
    await user.click(screen.getByRole('combobox'))
    await user.click(screen.getByRole('option', { name: /BNB Chain/ }))
    expect(onChange).toHaveBeenCalledWith('bsc')
  })

  it('should show balance when provided', () => {
    render(<SourceChainSelector chains={mockChains} value="ethereum" onChange={() => {}} balance="100.5" balanceLabel="ETH" />)
    expect(screen.getByText('Balance: 100.5 ETH')).toBeInTheDocument()
  })
})

describe('DestChainSelector', () => {
  it('should render with label "To"', () => {
    render(<DestChainSelector chains={mockChains} value="bsc" onChange={() => {}} />)
    expect(screen.getByText('To')).toBeInTheDocument()
  })
})

describe('AmountInput', () => {
  it('should render with Amount label', () => {
    render(<AmountInput value="" onChange={() => {}} />)
    expect(screen.getByText('Amount')).toBeInTheDocument()
  })

  it('should show MAX button when onMax provided', () => {
    render(<AmountInput value="" onChange={() => {}} onMax={() => {}} />)
    expect(screen.getByText('MAX')).toBeInTheDocument()
  })

  it('should not show MAX button when onMax not provided', () => {
    render(<AmountInput value="" onChange={() => {}} />)
    expect(screen.queryByText('MAX')).not.toBeInTheDocument()
  })

  it('should call onMax when MAX clicked', () => {
    const onMax = vi.fn()
    render(<AmountInput value="" onChange={() => {}} onMax={onMax} />)
    fireEvent.click(screen.getByText('MAX'))
    expect(onMax).toHaveBeenCalledOnce()
  })

  it('should accept numeric input', async () => {
    const onChange = vi.fn()
    render(<AmountInput value="" onChange={onChange} />)
    const input = screen.getByPlaceholderText('0.0')
    await userEvent.setup().type(input, '5')
    expect(onChange).toHaveBeenCalled()
  })

  it('should show token symbol', () => {
    render(<AmountInput value="" onChange={() => {}} symbol="LUNC" />)
    expect(screen.getAllByText('LUNC').length).toBeGreaterThan(0)
  })

  it('should show token dropdown when multiple tokens provided', async () => {
    const user = userEvent.setup()
    const tokens = [
      { id: 'uluna', symbol: 'LUNC', tokenId: 'uluna' },
      { id: 'uusd', symbol: 'USTC', tokenId: 'uusd' },
    ]
    const onTokenChange = vi.fn()
    render(
      <AmountInput
        value=""
        onChange={() => {}}
        tokens={tokens}
        selectedTokenId="uluna"
        onTokenChange={onTokenChange}
      />
    )
    expect(screen.getAllByText('LUNC').length).toBeGreaterThan(0)
    const tokenButton = screen.getByRole('combobox', { name: 'Select token' })
    await user.click(tokenButton)
    expect(screen.getByRole('option', { name: /LUNC/ })).toBeInTheDocument()
    expect(screen.getByRole('option', { name: /USTC/ })).toBeInTheDocument()
  })
})

describe('TokenSelect ranking (INV-FE-TOKEN-RANK-1)', () => {
  const testa = 'terra16ahm9hn5teayt2as384zf3uudgqvmmwahqfh0v9e3kaslhu30l8q38ftvh'
  const rankedTokens = [
    { id: 'uluna', symbol: 'LUNC', tokenId: 'uluna' },
    { id: 'terra16wtml2q66g82fdkx66tap0qjkahqwp4lwq3ngtygacg5q0kzycgqvhpax3', symbol: 'CL8Y', tokenId: 'terra16wtml2q66g82fdkx66tap0qjkahqwp4lwq3ngtygacg5q0kzycgqvhpax3' },
    { id: testa, symbol: 'testa', tokenId: testa },
  ]

  it('listbox option order matches the tokens prop (no re-sort)', async () => {
    const user = userEvent.setup()
    render(
      <TokenSelect tokens={rankedTokens} value="uluna" onChange={() => {}} />,
    )
    await user.click(screen.getByRole('combobox', { name: 'Select token' }))
    const options = screen.getAllByRole('option')
    expect(options.map((o) => o.getAttribute('data-tokenid'))).toEqual(rankedTokens.map((t) => t.id))
  })

  it('selecting a bottom-group test token emits that id, not the first economic id', async () => {
    const user = userEvent.setup()
    const onChange = vi.fn()
    render(
      <TokenSelect tokens={rankedTokens} value="uluna" onChange={onChange} />,
    )
    await user.click(screen.getByRole('combobox', { name: 'Select token' }))
    await user.click(screen.getByRole('option', { name: /testa/i }))
    expect(onChange).toHaveBeenCalledWith(testa)
  })

  it('spoofed CL8Y label on a test id still submits the test id (data-tokenid)', async () => {
    const user = userEvent.setup()
    const onChange = vi.fn()
    const spoofed = [
      { id: 'uluna', symbol: 'LUNC', tokenId: 'uluna' },
      { id: testa, symbol: 'CL8Y', tokenId: testa },
    ]
    render(<TokenSelect tokens={spoofed} value="uluna" onChange={onChange} />)
    await user.click(screen.getByRole('combobox', { name: 'Select token' }))
    const testOption = screen.getAllByRole('option').find((o) => o.getAttribute('data-tokenid') === testa)
    expect(testOption).toBeTruthy()
    await user.click(testOption!)
    expect(onChange).toHaveBeenCalledWith(testa)
  })

  it('renders HTML in the symbol as text (no markup injection)', async () => {
    const user = userEvent.setup()
    const xss = '<img src=x onerror=alert(1)>'
    render(
      <TokenSelect
        tokens={[
          { id: 'uluna', symbol: 'LUNC', tokenId: 'uluna' },
          { id: testa, symbol: xss, tokenId: testa },
        ]}
        value="uluna"
        onChange={() => {}}
      />,
    )
    await user.click(screen.getByRole('combobox', { name: 'Select token' }))
    expect(screen.getByText(xss)).toBeInTheDocument()
    expect(document.querySelector('li img[src="x"]')).toBeNull()
  })

  it('does not open a dropdown for a single-token list', () => {
    render(
      <TokenSelect
        tokens={[{ id: 'uluna', symbol: 'LUNC', tokenId: 'uluna' }]}
        value="uluna"
        onChange={() => {}}
      />,
    )
    expect(screen.queryByRole('listbox')).not.toBeInTheDocument()
    fireEvent.click(screen.getByRole('combobox', { name: 'Select token' }))
    expect(screen.queryByRole('listbox')).not.toBeInTheDocument()
  })
})

describe('RecipientInput', () => {
  it('should show terra placeholder for evm-to-terra direction', () => {
    render(<RecipientInput value="" onChange={() => {}} direction="evm-to-terra" />)
    expect(screen.getByPlaceholderText('terra1...')).toBeInTheDocument()
  })

  it('should show 0x placeholder for terra-to-evm direction', () => {
    render(<RecipientInput value="" onChange={() => {}} direction="terra-to-evm" />)
    expect(screen.getByPlaceholderText('0x...')).toBeInTheDocument()
  })

  it('should show 0x placeholder for evm-to-evm direction', () => {
    render(<RecipientInput value="" onChange={() => {}} direction="evm-to-evm" />)
    expect(screen.getByPlaceholderText('0x...')).toBeInTheDocument()
  })

  it('should show validation error for invalid EVM address', () => {
    render(<RecipientInput value="not-valid" onChange={() => {}} direction="terra-to-evm" />)
    expect(screen.getByText('Invalid address')).toBeInTheDocument()
  })

  it('should show validation error for invalid EVM address in evm-to-evm direction', () => {
    render(<RecipientInput value="not-valid" onChange={() => {}} direction="evm-to-evm" />)
    expect(screen.getByText('Invalid address')).toBeInTheDocument()
  })

  it('should not show error for empty value', () => {
    render(<RecipientInput value="" onChange={() => {}} direction="terra-to-evm" />)
    expect(screen.queryByText('Invalid address')).not.toBeInTheDocument()
  })

  it('should show autofill button when onAutofill is provided', () => {
    render(
      <RecipientInput value="" onChange={() => {}} direction="terra-to-evm" onAutofill={() => {}} />
    )
    expect(screen.getByText('Autofill with connected wallet')).toBeInTheDocument()
  })

  it('should not show autofill button when onAutofill is not provided', () => {
    render(<RecipientInput value="" onChange={() => {}} direction="terra-to-evm" />)
    expect(screen.queryByText('Autofill with connected wallet')).not.toBeInTheDocument()
  })
})

describe('FeeBreakdown', () => {
  it('should show bridge fee percentage', () => {
    render(<FeeBreakdown receiveAmount="99.7" />)
    expect(screen.getByText('Bridge Fee')).toBeInTheDocument()
    expect(screen.getByText('0.5%')).toBeInTheDocument()
  })

  it('should show estimated time', () => {
    render(<FeeBreakdown receiveAmount="99.7" />)
    expect(screen.getByText('Estimated Time')).toBeInTheDocument()
  })

  it('should show receive amount with symbol', () => {
    render(<FeeBreakdown receiveAmount="99.7" symbol="LUNC" />)
    expect(screen.getByText('99.7')).toBeInTheDocument()
    expect(screen.getByText('LUNC')).toBeInTheDocument()
  })
})

describe('SwapDirectionButton', () => {
  it('should render a button', () => {
    render(<SwapDirectionButton onClick={() => {}} />)
    const button = screen.getByRole('button')
    expect(button).toBeInTheDocument()
  })

  it('should call onClick when clicked', () => {
    const onClick = vi.fn()
    render(<SwapDirectionButton onClick={onClick} />)
    fireEvent.click(screen.getByRole('button'))
    expect(onClick).toHaveBeenCalledOnce()
  })

  it('should be disabled when disabled prop is true', () => {
    render(<SwapDirectionButton onClick={() => {}} disabled />)
    expect(screen.getByRole('button')).toBeDisabled()
  })
})
