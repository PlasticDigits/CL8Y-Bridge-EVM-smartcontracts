import { describe, expect, it, vi } from 'vitest'
import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { WalletMenuBackdrop } from './WalletMenuBackdrop'

describe('WalletMenuBackdrop (GL-137)', () => {
  it('portals a z-40 catcher to document.body so it cannot stack inside the header', async () => {
    const onClose = vi.fn()
    const user = userEvent.setup()
    render(<WalletMenuBackdrop onClose={onClose} />)
    const backdrop = screen.getByTestId('wallet-menu-backdrop')
    expect(backdrop.parentElement).toBe(document.body)
    expect(backdrop.className).toContain('z-40')
    expect(backdrop).toHaveAttribute('aria-label', 'Close wallet menu')
    await user.click(backdrop)
    expect(onClose).toHaveBeenCalled()
  })
})
