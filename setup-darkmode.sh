#!/bin/bash

cd "/Users/torresus/Ω Local-NonSync/2026-07-19-open-sourcing-os/opensourcingos"

# Create theme provider component
cat > components/theme-provider.tsx << 'EOF'
'use client'

import { ThemeProvider as NextThemesProvider } from 'next-themes'

export function ThemeProvider({ children }: { children: React.ReactNode }) {
  return (
    <NextThemesProvider attribute="class" defaultTheme="light" enableSystem disableTransitionOnChange>
      {children}
    </NextThemesProvider>
  )
}
EOF

# Create theme toggle button component
cat > components/theme-toggle.tsx << 'EOF'
'use client'

import { useState, useEffect } from 'react'
import { useTheme } from 'next-themes'
import { Sun, Moon } from 'lucide-react'

export function ThemeToggle() {
  const { theme, setTheme } = useTheme()
  const [mounted, setMounted] = useState(false)

  useEffect(() => {
    setMounted(true)
  }, [])

  if (!mounted) {
    return <div className="h-8 w-8" />
  }

  const isDark = theme === 'dark'

  return (
    <button
      onClick={() => setTheme(isDark ? 'light' : 'dark')}
      className="flex items-center gap-2 rounded-lg px-3 py-2 text-sm font-medium text-gray-600 hover:bg-gray-100 hover:text-gray-900 dark:text-gray-400 dark:hover:bg-gray-800 dark:hover:text-gray-100"
      title={isDark ? 'Switch to light mode' : 'Switch to dark mode'}
    >
      {isDark ? <Sun className="h-4 w-4" /> : <Moon className="h-4 w-4" />}
      {isDark ? 'Light Mode' : 'Dark Mode'}
    </button>
  )
}
EOF

# Update layout.tsx to include theme provider
cat > app/layout.tsx << 'EOF'
import type { Metadata } from 'next'
import { Inter } from 'next/font/google'
import './globals.css'
import { AppShell } from '@/components/app-shell'
import { ThemeProvider } from '@/components/theme-provider'

const inter = Inter({ subsets: ['latin'] })

export const metadata: Metadata = {
  title: 'OpenSourcingOS',
  description: 'Procurement Value Tracker — Sourcing, Savings & Realization',
}

export default function RootLayout({
  children,
}: {
  children: React.ReactNode
}) {
  return (
    <html lang="en" suppressHydrationWarning>
      <body className={inter.className}>
        <ThemeProvider>
          <AppShell>{children}</AppShell>
        </ThemeProvider>
      </body>
    </html>
  )
}
EOF

# Update sidebar to include theme toggle
cat > components/sidebar.tsx << 'EOF'
'use client'

import Link from 'next/link'
import { usePathname, useRouter } from 'next/navigation'
import { useEffect, useState } from 'react'
import {
  LayoutDashboard,
  Calculator,
  TrendingUp,
  Users,
  FileText,
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
  { label: 'Sourcing Events', href: '/events', icon: Briefcase },
  { label: 'Savings Calculations', href: '/savings', icon: Calculator },
  { label: 'Realization', href: '/realization', icon: TrendingUp },
  { label: 'Suppliers', href: '/suppliers', icon: Users },
  { label: 'Contracts', href: '/contracts', icon: FileText },
  { label: 'Reports', href: '/reports', icon: BarChart3 },
  { label: 'Settings', href: '/settings', icon: Settings },
]

export function Sidebar() {
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

  const handleLogout = async () => {
    await supabase.auth.signOut()
    router.push('/login')
    router.refresh()
  }

  return (
    <aside className="flex h-screen w-64 flex-col border-r border-gray-200 bg-white dark:border-gray-800 dark:bg-gray-900">
      <div className="flex h-16 items-center gap-2 border-b border-gray-200 px-6 dark:border-gray-800">
        <span className="text-lg font-semibold text-gray-900 dark:text-gray-100">OpenSourcing</span>
        <div className="flex h-7 w-7 items-center justify-center rounded-md bg-indigo-600 text-sm text-white font-bold">
          OS
        </div>
      </div>

      <nav className="flex-1 overflow-y-auto px-3 py-4">
        <ul className="space-y-1">
          {navItems.map((item) => {
            const Icon = item.icon
            const isActive = pathname === item.href || pathname.startsWith(item.href + '/')

            return (
              <li key={item.href}>
                <Link
                  href={item.href}
                  className={clsx(
                    'flex items-center gap-3 rounded-lg px-3 py-2 text-sm font-medium transition-colors',
                    isActive
                      ? 'bg-indigo-50 text-indigo-700 dark:bg-indigo-900/50 dark:text-indigo-300'
                      : 'text-gray-600 hover:bg-gray-100 hover:text-gray-900 dark:text-gray-400 dark:hover:bg-gray-800 dark:hover:text-gray-100'
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

      <div className="border-t border-gray-200 p-4 dark:border-gray-800">
        {userEmail && (
          <div className="mb-2 truncate text-xs text-gray-500 dark:text-gray-400">
            {userEmail}
          </div>
        )}
        <ThemeToggle />
        <button
          onClick={handleLogout}
          className="mt-1 flex w-full items-center gap-2 rounded-lg px-3 py-2 text-sm font-medium text-gray-600 hover:bg-gray-100 hover:text-gray-900 dark:text-gray-400 dark:hover:bg-gray-800 dark:hover:text-gray-100"
        >
          <LogOut className="h-4 w-4" />
          Sign Out
        </button>
        <div className="mt-3 rounded-lg bg-gray-50 px-3 py-2 text-xs text-gray-500 dark:bg-gray-800 dark:text-gray-400">
          MVP • Beta Version
        </div>
      </div>
    </aside>
  )
}
EOF

# Update app-layout for dark mode
cat > components/app-layout.tsx << 'EOF'
import { Sidebar } from './sidebar'

export function AppLayout({ children }: { children: React.ReactNode }) {
  return (
    <div className="flex h-screen overflow-hidden bg-gray-50 dark:bg-gray-950">
      <Sidebar />
      <main className="flex-1 overflow-y-auto bg-gray-50 dark:bg-gray-950">
        {children}
      </main>
    </div>
  )
}
EOF

# Update globals.css with dark mode CSS overrides
cat > app/globals.css << 'EOF'
@import "tailwindcss";

@custom-variant dark (&:where(.dark, .dark *));

:root {
  --background: #ffffff;
  --foreground: #171717;
}

html {
  color: var(--foreground);
}

body {
  background: var(--background);
  color: var(--foreground);
  font-family: var(--font-inter), system-ui, -apple-system, sans-serif;
}

/* Ensure form inputs have dark, readable text */
input,
select,
textarea {
  color: #1f2937;
}

input::placeholder,
textarea::placeholder {
  color: #9ca3af;
}

/* Dark mode overrides — automatically adapts common Tailwind classes */
.dark {
  --background: #0a0a0a;
  --foreground: #fafafa;
}

.dark body {
  background: #0a0a0a;
  color: #fafafa;
}

.dark input,
.dark select,
.dark textarea {
  color: #e2e8f0;
  background-color: #1e293b;
  border-color: #334155;
}

.dark input::placeholder,
.dark textarea::placeholder {
  color: #64748b;
}

/* Auto-adapt common utility classes for dark mode */
.dark .bg-white { background-color: #1e293b !important; }
.dark .bg-gray-50 { background-color: #0f172a !important; }
.dark .bg-gray-100 { background-color: #1e293b !important; }
.dark .bg-gray-200 { background-color: #334155 !important; }

.dark .text-gray-900 { color: #f1f5f9 !important; }
.dark .text-gray-700 { color: #cbd5e1 !important; }
.dark .text-gray-600 { color: #94a3b8 !important; }
.dark .text-gray-500 { color: #64748b !important; }
.dark .text-gray-400 { color: #475569 !important; }

.dark .border-gray-200 { border-color: #334155 !important; }
.dark .border-gray-100 { border-color: #1e293b !important; }

.dark .hover\:bg-gray-50:hover { background-color: #1e293b !important; }
.dark .hover\:bg-gray-100:hover { background-color: #334155 !important; }
.dark .hover\:bg-gray-200:hover { background-color: #475569 !important; }

/* Keep colored elements visible in dark mode */
.dark .bg-indigo-50 { background-color: rgba(49, 46, 129, 0.3) !important; }
.dark .bg-indigo-100 { background-color: rgba(49, 46, 129, 0.4) !important; }
.dark .bg-green-50 { background-color: rgba(6, 78, 59, 0.3) !important; }
.dark .bg-green-100 { background-color: rgba(6, 78, 59, 0.4) !important; }
.dark .bg-red-50 { background-color: rgba(127, 29, 29, 0.3) !important; }
.dark .bg-red-100 { background-color: rgba(127, 29, 29, 0.4) !important; }
.dark .bg-amber-50 { background-color: rgba(120, 53, 15, 0.3) !important; }
.dark .bg-amber-100 { background-color: rgba(120, 53, 15, 0.4) !important; }
.dark .bg-blue-50 { background-color: rgba(30, 58, 138, 0.3) !important; }
.dark .bg-blue-100 { background-color: rgba(30, 58, 138, 0.4) !important; }
.dark .bg-purple-50 { background-color: rgba(76, 29, 149, 0.3) !important; }
.dark .bg-purple-100 { background-color: rgba(76, 29, 149, 0.4) !important; }
.dark .bg-emerald-50 { background-color: rgba(6, 78, 59, 0.3) !important; }
.dark .bg-emerald-100 { background-color: rgba(6, 78, 59, 0.4) !important; }
.dark .bg-orange-50 { background-color: rgba(124, 45, 18, 0.3) !important; }
.dark .bg-orange-100 { background-color: rgba(124, 45, 18, 0.4) !important; }

/* Text colors that should stay visible in dark mode */
.dark .text-indigo-600 { color: #818cf8 !important; }
.dark .text-indigo-700 { color: #a5b4fc !important; }
.dark .text-green-600 { color: #4ade80 !important; }
.dark .text-green-700 { color: #86efac !important; }
.dark .text-red-600 { color: #f87171 !important; }
.dark .text-red-700 { color: #fca5a5 !important; }
.dark .text-blue-600 { color: #60a5fa !important; }
.dark .text-blue-700 { color: #93c5fd !important; }
.dark .text-purple-600 { color: #c084fc !important; }
.dark .text-purple-700 { color: #d8b4fe !important; }
.dark .text-emerald-600 { color: #4ade80 !important; }
.dark .text-emerald-700 { color: #86efac !important; }
.dark .text-amber-600 { color: #fbbf24 !important; }
.dark .text-amber-700 { color: #fcd34d !important; }
.dark .text-orange-600 { color: #fb923c !important; }
.dark .text-orange-700 { color: #fdba74 !important; }

/* Badge/pill backgrounds in dark mode */
.dark .text-indigo-700.bg-indigo-100 { color: #a5b4fc !important; }
.dark .text-green-700.bg-green-100 { color: #86efac !important; }
.dark .text-red-700.bg-red-100 { color: #fca5a5 !important; }
.dark .text-amber-700.bg-amber-100 { color: #fcd34d !important; }
.dark .text-purple-700.bg-purple-100 { color: #d8b4fe !important; }
.dark .text-emerald-700.bg-emerald-100 { color: #86efac !important; }
.dark .text-blue-700.bg-blue-100 { color: #93c5fd !important; }
.dark .text-gray-700.bg-gray-100 { color: #cbd5e1 !important; }

/* Indigo buttons stay the same */
.dark .bg-indigo-600 { background-color: #4f46e5 !important; }
.dark .hover\:bg-indigo-700:hover { background-color: #4338ca !important; }
EOF

# Clear build cache
rm -rf .next

echo "DONE"
