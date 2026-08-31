import { describe, expect, it, vi } from 'vitest'
import { copyTextToClipboard } from './clipboard'

describe('copyTextToClipboard (GL-137)', () => {
  it('returns true when clipboard.writeText succeeds', async () => {
    Object.defineProperty(navigator, 'clipboard', {
      configurable: true,
      value: { writeText: vi.fn().mockResolvedValue(undefined) },
    })
    await expect(copyTextToClipboard('wc:abc@1')).resolves.toBe(true)
  })

  it('falls back to prompt when clipboard.writeText rejects', async () => {
    Object.defineProperty(navigator, 'clipboard', {
      configurable: true,
      value: { writeText: vi.fn().mockRejectedValue(new Error('denied')) },
    })
    Object.defineProperty(document, 'execCommand', {
      configurable: true,
      value: vi.fn().mockReturnValue(false),
    })
    window.prompt = vi.fn().mockReturnValue('wc:abc@1') as typeof window.prompt
    await expect(copyTextToClipboard('wc:abc@1', 'Copy pairing link')).resolves.toBe(true)
    expect(window.prompt).toHaveBeenCalledWith('Copy pairing link', 'wc:abc@1')
  })

  it('returns false when prompt is cancelled', async () => {
    Object.defineProperty(navigator, 'clipboard', {
      configurable: true,
      value: { writeText: vi.fn().mockRejectedValue(new Error('denied')) },
    })
    Object.defineProperty(document, 'execCommand', {
      configurable: true,
      value: vi.fn().mockReturnValue(false),
    })
    window.prompt = vi.fn().mockReturnValue(null) as typeof window.prompt
    await expect(copyTextToClipboard('wc:abc@1')).resolves.toBe(false)
  })
})
