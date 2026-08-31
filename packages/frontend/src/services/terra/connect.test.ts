import { describe, expect, it } from 'vitest'
import { WalletName, WalletType } from '@goblinhunt/cosmes/wallet'
import { remapTerraConnectError } from './connect'

describe('remapTerraConnectError (GL-137)', () => {
  it('maps extension missing-Keplr errors to install-the-extension copy', () => {
    const err = remapTerraConnectError(
      WalletName.KEPLR,
      WalletType.EXTENSION,
      new Error('Keplr is not installed')
    )
    expect(err.message).toBe('Keplr wallet is not installed. Please install the Keplr extension.')
  })

  it('does not remap WalletConnect failures that mention Keplr to an extension dead-end', () => {
    const err = remapTerraConnectError(
      WalletName.KEPLR,
      WalletType.WALLETCONNECT,
      new Error('Keplr WalletConnect session timed out')
    )
    expect(err.message).toContain('Keplr WalletConnect session timed out')
    expect(err.message).not.toMatch(/install the Keplr extension/i)
  })

  it('does not remap Station WalletConnect errors to install-the-extension copy', () => {
    const err = remapTerraConnectError(
      WalletName.STATION,
      WalletType.WALLETCONNECT,
      new Error('Station relay error')
    )
    expect(err.message).toContain('Station relay error')
    expect(err.message).not.toMatch(/install the Station extension/i)
  })

  it('still maps user-rejected for both connection types', () => {
    const wc = remapTerraConnectError(
      WalletName.KEPLR,
      WalletType.WALLETCONNECT,
      new Error('User rejected the request')
    )
    const ext = remapTerraConnectError(
      WalletName.KEPLR,
      WalletType.EXTENSION,
      new Error('User rejected the request')
    )
    expect(wc.message).toBe('Connection rejected by user')
    expect(ext.message).toBe('Connection rejected by user')
  })
})
