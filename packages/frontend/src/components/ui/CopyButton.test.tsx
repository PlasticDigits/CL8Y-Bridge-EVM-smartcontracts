import { describe, it, expect, vi } from 'vitest'
import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { CopyButton } from './CopyButton'

vi.mock('../../lib/sounds', () => ({
  sounds: { playButtonPress: vi.fn() },
}))

vi.mock('../../utils/clipboard', () => ({
  copyTextToClipboard: vi.fn(),
}))

import { copyTextToClipboard } from '../../utils/clipboard'

const mockCopy = vi.mocked(copyTextToClipboard)

describe('CopyButton', () => {
  it('renders with copy label', () => {
    render(<CopyButton text="test" />)
    const btn = screen.getByRole('button', { name: 'Copy' })
    expect(btn).toBeInTheDocument()
  })

  it('uses custom label when provided', () => {
    render(<CopyButton text="x" label="Copy address" />)
    expect(screen.getByRole('button', { name: 'Copy address' })).toBeInTheDocument()
  })

  it('renders visible label when showLabel is set', () => {
    render(<CopyButton text="x" label="Copy pairing link" showLabel />)
    expect(screen.getByRole('button', { name: 'Copy pairing link' })).toHaveTextContent('Copy pairing link')
  })

  it('shows Copy failed when clipboard helpers return false', async () => {
    mockCopy.mockResolvedValue(false)
    const user = userEvent.setup()
    render(<CopyButton text="wc:abc@1" label="Copy pairing link" showLabel testId="copy" />)
    await user.click(screen.getByTestId('copy'))
    expect(screen.getByTestId('copy')).toHaveAttribute('data-copy-failed', 'true')
    expect(screen.getByTestId('copy')).toHaveTextContent('Copy failed')
  })
})
