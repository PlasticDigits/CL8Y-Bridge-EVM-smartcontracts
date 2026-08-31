import { describe, it, expect, vi, afterEach } from 'vitest'
import {
  DEFAULT_API_BASE_URL,
  DEFAULT_TERMS_BASE_URL,
} from '@plasticdigits/cl8y-clickwrap'
import {
  BRIDGE_CLICKWRAP_APP_NAME,
  BRIDGE_CLICKWRAP_PROPERTY,
  bridgeChainKindFromConfigType,
  clickwrapClientConfig,
  clickwrapNetworkForChainKind,
  resolveClickwrapBaseUrl,
  sameOriginClickwrapRedirectUri,
} from './clickwrap'

describe('clickwrap helpers (INV-FE-CLICKWRAP-1)', () => {
  it('uses the production bridge property and constant app name', () => {
    expect(BRIDGE_CLICKWRAP_PROPERTY).toBe('bridge.cl8y.com')
    expect(BRIDGE_CLICKWRAP_APP_NAME).toBe('CL8Y Bridge')
  })

  it('maps chain kinds to SDK networks', () => {
    expect(clickwrapNetworkForChainKind('evm')).toBe('EVM')
    expect(clickwrapNetworkForChainKind('cosmos')).toBe('TerraClassic')
    expect(clickwrapNetworkForChainKind('solana')).toBe('Solana')
  })

  it('maps config types with EVM default', () => {
    expect(bridgeChainKindFromConfigType('cosmos')).toBe('cosmos')
    expect(bridgeChainKindFromConfigType('solana')).toBe('solana')
    expect(bridgeChainKindFromConfigType('evm')).toBe('evm')
    expect(bridgeChainKindFromConfigType(undefined)).toBe('evm')
  })

  it('builds redirect_uri from the current page href only', () => {
    expect(sameOriginClickwrapRedirectUri('https://bridge.cl8y.com/transfer/0xabc')).toBe(
      'https://bridge.cl8y.com/transfer/0xabc',
    )
    expect(sameOriginClickwrapRedirectUri('http://localhost:3000/')).toBe('http://localhost:3000/')
  })

  it('rejects non-http(s) and credentialed redirect URIs', () => {
    expect(() => sameOriginClickwrapRedirectUri('javascript:alert(1)')).toThrow(/http\(s\)/)
    expect(() => sameOriginClickwrapRedirectUri('data:text/html,hi')).toThrow(/http\(s\)/)
    expect(() => sameOriginClickwrapRedirectUri('//evil.example/phish')).toThrow(/http\(s\)/)
    expect(() =>
      sameOriginClickwrapRedirectUri('https://user:pass@bridge.cl8y.com/'),
    ).toThrow(/credentials/)
  })

  it('does not treat query-string signed=1 as a redirect source', () => {
    const href = 'https://bridge.cl8y.com/?signed=1'
    expect(sameOriginClickwrapRedirectUri(href)).toBe(href)
  })

  it('uses SDK HTTPS defaults when overrides are empty', () => {
    const cfg = clickwrapClientConfig({ isProd: true })
    expect(cfg.apiBaseUrl).toBe(DEFAULT_API_BASE_URL.replace(/\/$/, ''))
    expect(cfg.termsBaseUrl).toBe(DEFAULT_TERMS_BASE_URL.replace(/\/$/, ''))
  })

  it('allows https overrides', () => {
    expect(
      resolveClickwrapBaseUrl('https://api.staging.example/', DEFAULT_API_BASE_URL, true),
    ).toBe('https://api.staging.example')
  })

  it('ignores http overrides in production', () => {
    const spy = vi.spyOn(console, 'error').mockImplementation(() => {})
    expect(resolveClickwrapBaseUrl('http://evil.example', DEFAULT_API_BASE_URL, true)).toBe(
      DEFAULT_API_BASE_URL.replace(/\/$/, ''),
    )
    spy.mockRestore()
  })

  it('allows http overrides outside production (local Legal)', () => {
    expect(resolveClickwrapBaseUrl('http://127.0.0.1:8080', DEFAULT_API_BASE_URL, false)).toBe(
      'http://127.0.0.1:8080',
    )
  })
})

afterEach(() => {
  vi.restoreAllMocks()
})
