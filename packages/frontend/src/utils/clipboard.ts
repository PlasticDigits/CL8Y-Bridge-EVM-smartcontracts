/**
 * Clipboard helpers with Android Chrome fallbacks (INV-FE-WC-MOBILE-1).
 *
 * `navigator.clipboard.writeText` often fails in Android Chrome (insecure
 * context, missing permission, or WebView). Fall back to `execCommand('copy')`
 * then `window.prompt` so the user can long-press copy.
 */

export async function copyTextToClipboard(
  text: string,
  promptLabel = 'Copy'
): Promise<boolean> {
  try {
    if (typeof navigator !== 'undefined' && navigator.clipboard?.writeText) {
      await navigator.clipboard.writeText(text)
      return true
    }
  } catch {
    // fall through to execCommand / prompt
  }

  try {
    if (typeof document !== 'undefined' && typeof document.execCommand === 'function') {
      const ta = document.createElement('textarea')
      ta.value = text
      ta.setAttribute('readonly', '')
      ta.style.position = 'fixed'
      ta.style.left = '-9999px'
      document.body.appendChild(ta)
      ta.select()
      const ok = document.execCommand('copy')
      document.body.removeChild(ta)
      if (ok) return true
    }
  } catch {
    // fall through to prompt
  }

  if (typeof window !== 'undefined' && typeof window.prompt === 'function') {
    return window.prompt(promptLabel, text) !== null
  }
  return false
}
