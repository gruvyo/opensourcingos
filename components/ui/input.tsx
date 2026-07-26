import { cn } from '@/lib/utils'
import type { InputHTMLAttributes, SelectHTMLAttributes } from 'react'

const base =
  'w-full rounded-md border border-[var(--border-strong)] bg-[var(--surface)] px-3 py-2 text-sm text-[var(--text)] transition-colors ' +
  'focus:border-[var(--brand)] focus:outline-none focus:ring-2 focus:ring-[var(--brand)]/30'

/** Text input primitive — token-driven, themes itself, visible focus ring. */
export function Input({ className, ...props }: InputHTMLAttributes<HTMLInputElement>) {
  return <input className={cn(base, 'placeholder:text-[var(--text-3)]', className)} {...props} />
}

/** Select primitive — same look as Input. Pass <option> children. */
export function Select({ className, children, ...props }: SelectHTMLAttributes<HTMLSelectElement>) {
  return (
    <select className={cn(base, className)} {...props}>
      {children}
    </select>
  )
}
