import { describe, it, expect } from 'vitest'
import { render, screen } from '@testing-library/react'
import { CopyButton } from './CopyButton'

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
})
