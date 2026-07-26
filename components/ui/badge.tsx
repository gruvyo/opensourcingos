import { cn } from '@/lib/utils'
import type { HTMLAttributes } from 'react'

export type BadgeTone = 'brand' | 'success' | 'warning' | 'danger' | 'info' | 'neutral'

const tones: Record<BadgeTone, string> = {
  brand: 'bg-[var(--brand-soft)] text-[var(--brand-ink)]',
  success: 'bg-[var(--success-soft)] text-[var(--success)]',
  warning: 'bg-[var(--warning-soft)] text-[var(--warning)]',
  danger: 'bg-[var(--danger-soft)] text-[var(--danger)]',
  info: 'bg-[var(--info-soft)] text-[var(--info)]',
  neutral: 'bg-[var(--surface-2)] text-[var(--text-2)]',
}

/**
 * Badge — status pill primitive. `tone` carries meaning (semantic colour),
 * kept separate from the indigo brand accent.
 */
export function Badge({
  tone = 'neutral',
  className,
  ...props
}: HTMLAttributes<HTMLSpanElement> & { tone?: BadgeTone }) {
  return (
    <span
      className={cn(
        'inline-flex items-center gap-1.5 rounded-full px-2.5 py-0.5 text-xs font-semibold',
        tones[tone],
        className,
      )}
      {...props}
    />
  )
}
