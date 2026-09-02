import { describe, expect, it, vi } from 'vitest'
import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { Link, MemoryRouter, Outlet, Route, Routes } from 'react-router-dom'
import { useState } from 'react'
import { useDismissOnNavigate } from './useDismissOnNavigate'

function Shell() {
  const [open, setOpen] = useState(false)
  useDismissOnNavigate(() => setOpen(false))
  return (
    <>
      <button type="button" onClick={() => setOpen(true)}>
        Open
      </button>
      {open && (
        <button type="button" aria-label="Close wallet menu">
          Backdrop
        </button>
      )}
      <Link to="/history">History</Link>
      <Outlet />
    </>
  )
}

describe('useDismissOnNavigate (GL-137)', () => {
  it('closes a leftover overlay when the route changes while the shell stays mounted', async () => {
    const user = userEvent.setup()
    render(
      <MemoryRouter initialEntries={['/']}>
        <Routes>
          <Route element={<Shell />}>
            <Route path="/" element={<div>Home</div>} />
            <Route path="/history" element={<div>History page</div>} />
          </Route>
        </Routes>
      </MemoryRouter>
    )

    await user.click(screen.getByRole('button', { name: 'Open' }))
    expect(screen.getByRole('button', { name: 'Close wallet menu' })).toBeInTheDocument()
    await user.click(screen.getByRole('link', { name: 'History' }))
    expect(screen.queryByRole('button', { name: 'Close wallet menu' })).not.toBeInTheDocument()
    expect(screen.getByText('History page')).toBeInTheDocument()
  })

  it('invokes dismiss on the initial mount path (dropdown starts closed)', () => {
    const dismiss = vi.fn()
    function Probe() {
      useDismissOnNavigate(dismiss)
      return null
    }
    render(
      <MemoryRouter>
        <Probe />
      </MemoryRouter>
    )
    expect(dismiss).toHaveBeenCalledTimes(1)
  })
})
