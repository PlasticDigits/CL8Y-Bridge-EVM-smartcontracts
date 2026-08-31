import { existsSync, readFileSync } from 'node:fs'
import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { describe, expect, it } from 'vitest'

const frontendRoot = resolve(dirname(fileURLToPath(import.meta.url)), '../../..')

function cosmesLockfileVersion(): string {
  const lock = JSON.parse(readFileSync(resolve(frontendRoot, 'package-lock.json'), 'utf8')) as {
    packages?: Record<string, { version?: string }>
  }
  const version = lock.packages?.['node_modules/@goblinhunt/cosmes']?.version
  if (!version) {
    throw new Error('Could not resolve @goblinhunt/cosmes version from package-lock.json')
  }
  return version
}

function readCosmes(relPath: string): string {
  return readFileSync(resolve(frontendRoot, 'node_modules/@goblinhunt/cosmes', relPath), 'utf8')
}

describe('cosmes QRCodeModal patch (GL-137)', () => {
  it('has a patch file for the locked cosmes version', () => {
    const version = cosmesLockfileVersion()
    const patchPath = resolve(frontendRoot, 'patches', `@goblinhunt+cosmes+${version}.patch`)
    expect(existsSync(patchPath)).toBe(true)
  })

  it('QRCodeModal delegates to the dApp pairing hook and does not auto-redirect', () => {
    const src = readCosmes('dist/wallet/walletconnect/QRCodeModal.js')
    expect(src).toContain('__CL8Y_WC_PAIRING_MODAL__')
    expect(src).toContain('GitLab #137')
    expect(src).toContain('Copy pairing link')
    expect(src).toContain('do not auto-redirect')
    expect(src).toContain('cl8yAllowedDeepLink')
    expect(src).toContain('isAllowedDeepLink')
    expect(src).not.toMatch(/if \(isMobile\(\)\) \{\s*\/\/ On mobile, redirect to mobile app/)
  })
})
