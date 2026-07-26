import { cn } from '@/lib/utils'
import type { HTMLAttributes } from 'react'

/**
 * Card — the standard surface primitive. Token-driven, so it themes itself
 * (light/dark) with no per-instance `dark:` classes. Replaces the copy-pasted
 * `rounded-lg border border-gray-200 bg-white ... dark:...` string.
 */
export function Card({ className, ...props }: HTMLAttributes<HTMLDivElement>) {
  return (
    <div
      className={cn(
        'rounded-lg border border-[var(--border)] bg-[var(--surface)] shadow-sm',
        className,
      )}
      {...props}
    />
  )
}
