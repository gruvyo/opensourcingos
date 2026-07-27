'use client'

import Link from 'next/link'
import { usePathname, useRouter } from 'next/navigation'
import { useEffect, useState } from 'react'
import {
  LayoutDashboard,
  Calculator,
  Users,
  BarChart3,
  Settings,
  Briefcase,
  LogOut,
} from 'lucide-react'
import { clsx } from 'clsx'
import { createClient } from '@/lib/supabase/client'
import { ThemeToggle } from './theme-toggle'

const navItems = [
  { label: 'Dashboard', href: '/dashboard', icon: LayoutDashboard },
  { label: 'Projects', href: '/events', icon: Briefcase },
  { label: 'Savings', href: '/savings', icon: Calculator },
  { label: 'Suppliers', href: '/suppliers', icon: Users },
  { label: 'Reports', href: '/reports', icon: BarChart3 },
  { label: 'Settings', href: '/settings', icon: Settings },
]

export function Sidebar({ open, onClose }: { open: boolean; onClose: () => void }) {
  const pathname = usePathname()
  const router = useRouter()
  const supabase = createClient()
  const [userEmail, setUserEmail] = useState<string | null>(null)

  useEffect(() => {
    const getUser = async () => {
      const { data: { user } } = await supabase.auth.getUser()
      if (user) setUserEmail(user.email ?? null)
    }
    getUser()
  }, [supabase])

  // Lock body scroll when drawer is open + close on Escape
  useEffect(() => {
    if (!open) return
    document.body.style.overflow = 'hidden'
    const handleEsc = (e: KeyboardEvent) => {
      if (e.key === 'Escape') onClose()
    }
    document.addEventListener('keydown', handleEsc)
    return () => {
      document.body.style.overflow = ''
      document.removeEventListener('keydown', handleEsc)
    }
  }, [open, onClose])

  const handleLogout = async () => {
    await supabase.auth.signOut()
    router.push('/login')
    router.refresh()
  }

  const sidebarContent = (
    <>
      <div className="flex h-16 shrink-0 items-center gap-2 border-b border-[var(--border)] px-6">
        <span className="text-lg font-semibold text-[var(--text)]">OpenSourcing</span>
        <div className="flex h-7 w-7 items-center justify-center rounded-md bg-[var(--brand)] text-sm text-white font-bold">
          OS
        </div>
      </div>

      <nav className="flex-1 overflow-y-auto overscroll-contain px-3 py-4">
        <ul className="space-y-1">
          {navItems.map((item) => {
            const Icon = item.icon
            const isActive = pathname === item.href || pathname.startsWith(item.href + '/')
            return (
              <li key={item.href}>
                <Link
                  href={item.href}
                  onClick={onClose}
                  className={clsx(
                    'flex items-center gap-3 rounded-lg px-3 py-2 text-sm font-medium transition-colors',
                    isActive
                      ? 'bg-[var(--brand-soft)] text-[var(--brand-ink)]'
                      : 'text-[var(--text-2)] hover:bg-[var(--surface-2)] hover:text-[var(--text)]'
                  )}
                >
                  <Icon className="h-5 w-5" />
                  {item.label}
                </Link>
              </li>
            )
          })}
        </ul>
      </nav>

      <div className="shrink-0 border-t border-[var(--border)] p-4">
        {userEmail && (
          <div className="mb-2 truncate text-xs text-[var(--text-3)]">
            {userEmail}
          </div>
        )}
        <ThemeToggle />
        <button
          onClick={handleLogout}
          className="mt-1 flex w-full items-center gap-2 rounded-lg px-3 py-2 text-sm font-medium text-[var(--text-2)] transition-colors hover:bg-[var(--surface-2)] hover:text-[var(--text)]"
        >
          <LogOut className="h-4 w-4" />
          Sign Out
        </button>
        <div className="mt-3 rounded-lg bg-[var(--surface-2)] px-3 py-2 text-xs text-[var(--text-3)]">
          MVP • Beta Version
        </div>
      </div>
    </>
  )

  return (
    <>
      {/* Mobile slide-out drawer */}
      {open && (
        <div className="fixed inset-0 z-50 lg:hidden">
          <div
            className="absolute inset-0 bg-black/50"
            onClick={onClose}
          />
          <aside className="absolute left-0 top-0 flex h-full w-64 flex-col overflow-hidden bg-[var(--surface)]">
            {sidebarContent}
          </aside>
        </div>
      )}

      {/* Desktop fixed sidebar */}
      <aside className="hidden lg:flex h-screen w-64 flex-col border-r border-[var(--border)] bg-[var(--surface)]">
        {sidebarContent}
      </aside>
    </>
  )
}
