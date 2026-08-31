/**
 * Terra Classic wallet availability detection
 */

import { ensureKeplrCompatibleProvider, isKeplrCompatibleInstalled } from '../../utils/keplrCompatible'

export function isStationInstalled(): boolean {
  return typeof window !== 'undefined' && 'station' in window
}

export function isKeplrInstalled(): boolean {
  if (typeof window === 'undefined') return false
  ensureKeplrCompatibleProvider()
  return isKeplrCompatibleInstalled()
}

export function isLeapInstalled(): boolean {
  return typeof window !== 'undefined' && !!window.leap
}

export function isCosmostationInstalled(): boolean {
  return typeof window !== 'undefined' && !!window.cosmostation
}
