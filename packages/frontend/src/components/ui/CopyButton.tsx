import { useState, useCallback } from 'react'
import { sounds } from '../../lib/sounds'
import { copyTextToClipboard } from '../../utils/clipboard'

export interface CopyButtonProps {
  text: string
  className?: string
  label?: string
  testId?: string
  showLabel?: boolean
}

export function CopyButton({ text, className = '', label = 'Copy', testId, showLabel = false }: CopyButtonProps) {
  const [copied, setCopied] = useState(false)
  const [failed, setFailed] = useState(false)

  const handleClick = useCallback(async () => {
    sounds.playButtonPress()
    const ok = await copyTextToClipboard(text, label)
    if (ok) {
      setFailed(false)
      setCopied(true)
      setTimeout(() => setCopied(false), 2000)
      return
    }
    setCopied(false)
    setFailed(true)
  }, [text, label])

  const aria = copied ? 'Copied' : failed ? `${label} failed — select the text below` : label

  return (
    <button
      type="button"
      onClick={handleClick}
      className={`p-1.5 rounded hover:bg-white/5 text-gray-400 hover:text-white transition-colors ${className}`}
      title={copied ? 'Copied!' : failed ? 'Copy failed — select the text to copy' : label}
      aria-label={aria}
      data-testid={testId}
      data-copy-failed={failed ? 'true' : undefined}
    >
      {copied ? (
        <svg className="w-4 h-4 text-green-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 13l4 4L19 7" />
        </svg>
      ) : (
        <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path
            strokeLinecap="round"
            strokeLinejoin="round"
            strokeWidth={2}
            d="M8 16H6a2 2 0 01-2-2V6a2 2 0 012-2h8a2 2 0 012 2v2m-6 12h8a2 2 0 002-2v-8a2 2 0 00-2-2h-8a2 2 0 00-2 2v8a2 2 0 002 2z"
          />
        </svg>
      )}
      {showLabel && <span>{copied ? 'Copied' : failed ? 'Copy failed' : label}</span>}
    </button>
  )
}
