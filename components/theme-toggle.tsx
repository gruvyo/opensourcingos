'use client'

import { useSyncExternalStore } from 'react'
import { useTheme } from 'next-themes'
import { Sun, Moon } from 'lucide-react'
import { clsx } from 'clsx'

const subscribe = () => () => undefined

export function ThemeToggle({ inverted = false }: { inverted?: boolean }) {
  const { theme, setTheme } = useTheme()
  const mounted = useSyncExternalStore(subscribe, () => true, () => false)

  if (!mounted) {
    return <div className="h-8 w-8" />
  }

  const isDark = theme === 'dark'

  return (
    <button
      onClick={() => setTheme(isDark ? 'light' : 'dark')}
      className={clsx(
        'flex items-center gap-2 rounded-lg px-3 py-2 text-sm font-medium transition-colors',
        inverted
          ? 'text-slate-300 hover:bg-white/10 hover:text-white'
          : 'text-[var(--text-2)] hover:bg-[var(--surface-2)] hover:text-[var(--text)]',
      )}
      title={isDark ? 'Switch to light mode' : 'Switch to dark mode'}
    >
      {isDark ? <Sun className="h-4 w-4" /> : <Moon className="h-4 w-4" />}
      {isDark ? 'Light Mode' : 'Dark Mode'}
    </button>
  )
}
