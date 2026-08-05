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
  TrendingUp,
} from 'lucide-react'
import { clsx } from 'clsx'
import { createClient } from '@/lib/supabase/client'
import { ThemeToggle } from './theme-toggle'

const navGroups = [
  {
    label: 'Portfolio',
    items: [
      { label: 'Overview', href: '/dashboard', icon: LayoutDashboard },
      { label: 'Projects', href: '/events', icon: Briefcase },
      { label: 'Savings', href: '/savings', icon: Calculator },
      { label: 'Realization', href: '/realization', icon: TrendingUp },
    ],
  },
  {
    label: 'Intelligence',
    items: [
      { label: 'Suppliers', href: '/suppliers', icon: Users },
      { label: 'Reports', href: '/reports', icon: BarChart3 },
    ],
  },
  {
    label: 'Workspace',
    items: [{ label: 'Settings', href: '/settings', icon: Settings }],
  },
]

export function Sidebar({ open, onClose }: { open: boolean; onClose: () => void }) {
  const pathname = usePathname()
  const router = useRouter()
  const supabase = createClient()
  const [userEmail, setUserEmail] = useState<string | null>(null)
  const [signOutError, setSignOutError] = useState<string | null>(null)

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

  // Signing out used to navigate to /login whether or not it worked. If the
  // call fails the SESSION IS STILL LIVE, and showing the login page while the
  // cookie is valid tells the user they are signed out when they are not --
  // which on a shared machine is somebody else's problem to discover.
  const handleLogout = async () => {
    setSignOutError(null)
    const { error } = await supabase.auth.signOut()
    if (error) { setSignOutError(error.message); return }
    router.push('/login')
    router.refresh()
  }

  const sidebarContent = (
    <>
      <div className="flex h-16 shrink-0 items-center gap-2 border-b border-[var(--nav-border)] px-5">
        <span className="text-lg font-semibold tracking-tight text-[var(--nav-text-strong)]">OpenSourcing</span>
        <div className="flex h-7 w-7 items-center justify-center rounded-md bg-gradient-to-br from-indigo-500 to-violet-500 text-sm font-bold text-white shadow-md shadow-indigo-950/50">
          OS
        </div>
      </div>

      <nav className="flex-1 overflow-y-auto overscroll-contain px-3 py-5">
        <div className="space-y-6">
          {navGroups.map(group => (
            <section key={group.label} aria-labelledby={`nav-${group.label.toLowerCase()}`}>
              <h2 id={`nav-${group.label.toLowerCase()}`} className="mb-2 px-3 text-[10px] font-semibold uppercase tracking-[0.18em] text-slate-500">
                {group.label}
              </h2>
              <ul className="space-y-1">
                {group.items.map((item) => {
                  const Icon = item.icon
                  const isActive = pathname === item.href || pathname.startsWith(item.href + '/')
                  return (
                    <li key={item.href}>
                      <Link
                        href={item.href}
                        onClick={onClose}
                        aria-current={isActive ? 'page' : undefined}
                        className={clsx(
                          'flex items-center gap-3 rounded-lg px-3 py-2.5 text-sm font-medium transition-all',
                          isActive
                            ? 'bg-gradient-to-r from-indigo-600 to-indigo-500 text-white shadow-md shadow-indigo-950/30'
                            : 'text-[var(--nav-text)] hover:bg-white/[0.06] hover:text-white',
                        )}
                      >
                        <Icon className="h-[18px] w-[18px]" aria-hidden="true" />
                        {item.label}
                      </Link>
                    </li>
                  )
                })}
              </ul>
            </section>
          ))}
        </div>
      </nav>

      <div className="shrink-0 border-t border-[var(--nav-border)] p-4">
        {userEmail && (
          <div className="mb-2 truncate px-3 text-xs text-slate-500">
            {userEmail}
          </div>
        )}
        <ThemeToggle inverted />
        <button
          type="button"
          onClick={handleLogout}
          className="mt-1 flex w-full items-center gap-2 rounded-lg px-3 py-2 text-sm font-medium text-slate-300 transition-colors hover:bg-white/10 hover:text-white"
        >
          <LogOut className="h-4 w-4" />
          Sign Out
        </button>
        {signOutError && (
          <p role="alert" className="mt-1 rounded-lg bg-red-50 px-3 py-2 text-xs text-red-700 dark:bg-red-900/30 dark:text-red-300">
            Sign out failed — <strong>you are still signed in</strong>. {signOutError}
          </p>
        )}
        <div className="mt-3 rounded-lg border border-[var(--nav-border)] bg-white/[0.04] px-3 py-2 text-xs text-slate-500">
          Public beta · Workspace isolated
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
          <aside id="mobile-navigation" className="absolute left-0 top-0 flex h-full w-60 flex-col overflow-hidden bg-[var(--nav-bg)]">
            {sidebarContent}
          </aside>
        </div>
      )}

      {/* Desktop fixed sidebar */}
      <aside className="hidden h-full min-h-0 w-60 flex-col border-r border-[var(--nav-border)] bg-[var(--nav-bg)] lg:flex">
        {sidebarContent}
      </aside>
    </>
  )
}
