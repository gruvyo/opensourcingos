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
        'rounded-xl border border-[var(--border)] bg-[var(--surface)] shadow-[0_12px_34px_-28px_rgba(15,23,41,0.55)]',
        className,
      )}
      {...props}
    />
  )
}
