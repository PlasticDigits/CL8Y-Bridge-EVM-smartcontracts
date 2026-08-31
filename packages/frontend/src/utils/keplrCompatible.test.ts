import { describe, expect, it } from 'vitest'
import {
  ensureKeplrCompatibleProvider,
  getKeplrCompatibleProvider,
  isKeplrCompatibleInstalled,
} from './keplrCompatible'

type TestWin = {
  keplr?: { enable: (id: string) => Promise<void>; getOfflineSigner: (id: string) => unknown }
  trustwallet?: { cosmos?: { enable: (id: string) => Promise<void>; getOfflineSigner: (id: string) => unknown } }
}

describe('keplrCompatible (GL-137)', () => {
  it('returns undefined when neither keplr nor trust cosmos is present', () => {
    const win: TestWin = {}
    expect(getKeplrCompatibleProvider(win as never)).toBeUndefined()
    expect(isKeplrCompatibleInstalled(win as never)).toBe(false)
    expect(ensureKeplrCompatibleProvider(win as never)).toBe(false)
  })

  it('prefers window.keplr when present', () => {
    const keplr = { enable: async () => undefined, getOfflineSigner: () => ({}) }
    const win: TestWin = { keplr }
    expect(getKeplrCompatibleProvider(win as never)).toBe(keplr)
    expect(isKeplrCompatibleInstalled(win as never)).toBe(true)
    expect(ensureKeplrCompatibleProvider(win as never)).toBe(true)
  })

  it('aliases trustwallet.cosmos onto window.keplr when keplr is missing', () => {
    const cosmos = { enable: async () => undefined, getOfflineSigner: () => ({}) }
    const win: TestWin = { trustwallet: { cosmos } }
    expect(getKeplrCompatibleProvider(win as never)).toBe(cosmos)
    expect(ensureKeplrCompatibleProvider(win as never)).toBe(true)
    expect(win.keplr).toBe(cosmos)
  })

  it('never overwrites an existing window.keplr', () => {
    const keplr = { enable: async () => undefined, getOfflineSigner: () => ({}) }
    const cosmos = { enable: async () => undefined, getOfflineSigner: () => ({}) }
    const win: TestWin = { keplr, trustwallet: { cosmos } }
    expect(ensureKeplrCompatibleProvider(win as never)).toBe(true)
    expect(win.keplr).toBe(keplr)
  })
})
