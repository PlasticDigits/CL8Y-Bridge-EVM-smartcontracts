import { describe, expect, it } from 'vitest'
import { detectInAppBrowser } from './detectInAppBrowser'

function withUa(ua: string, run: () => void) {
  const original = navigator.userAgent
  Object.defineProperty(navigator, 'userAgent', { configurable: true, value: ua })
  try {
    run()
  } finally {
    Object.defineProperty(navigator, 'userAgent', { configurable: true, value: original })
  }
}

describe('detectInAppBrowser (GL-137)', () => {
  it('does not flag Android Chrome as an in-app browser', () => {
    withUa(
      'Mozilla/5.0 (Linux; Android 16; Pixel 9) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Mobile Safari/537.36',
      () => {
        expect(detectInAppBrowser()).toEqual({ isInAppBrowser: false, browserName: null })
      }
    )
  })

  it('flags Keplr in-app browser', () => {
    withUa('Mozilla/5.0 KeplrMobile', () => {
      expect(detectInAppBrowser()).toEqual({ isInAppBrowser: true, browserName: 'Keplr' })
    })
  })

  it('flags Android WebView (; wv)', () => {
    withUa(
      'Mozilla/5.0 (Linux; Android 13; Pixel 6; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/120.0.0.0 Mobile Safari/537.36',
      () => {
        expect(detectInAppBrowser().isInAppBrowser).toBe(true)
        expect(detectInAppBrowser().browserName).toBe('WebView')
      }
    )
  })
})
