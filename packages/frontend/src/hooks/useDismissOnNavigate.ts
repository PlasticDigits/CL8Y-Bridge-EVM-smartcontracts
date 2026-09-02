import { useEffect, useRef } from 'react'
import { useLocation } from 'react-router-dom'

/**
 * INV-FE-WC-MOBILE-1: drop full-screen `fixed inset-0` wallet-menu backdrops
 * when the route changes. Header Connect stays mounted in Layout, so unmount
 * cleanup does not run on History / Verify / Settings navigation.
 */
export function useDismissOnNavigate(dismiss: () => void): void {
  const { pathname } = useLocation()
  const dismissRef = useRef(dismiss)
  dismissRef.current = dismiss

  useEffect(() => {
    dismissRef.current()
  }, [pathname])
}
