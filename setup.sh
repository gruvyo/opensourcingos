#!/bin/bash

# Create .env.local
cat > .env.local << 'EOF'
NEXT_PUBLIC_SUPABASE_URL=https://qjtactdcfeuseuqaxfaa.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFqdGFjdGRjZmV1c2V1cWF4ZmFhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQ0ODUwODQsImV4cCI6MjEwMDA2MTA4NH0.UjqDvYeMfeZH3uPfRlIm4YPKyODb7uadsphTYj95_bY
EOF

# Create lib/supabase
mkdir -p lib/supabase

cat > lib/supabase/client.ts << 'EOF'
import { createBrowserClient } from '@supabase/ssr'

export function createClient() {
  return createBrowserClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!
  )
}
EOF

cat > lib/supabase/server.ts << 'EOF'
import { createServerClient } from '@supabase/ssr'
import { cookies } from 'next/headers'

export async function createClient() {
  const cookieStore = await cookies()

  return createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll() {
          return cookieStore.getAll()
        },
        setAll(cookiesToSet) {
          try {
            cookiesToSet.forEach(({ name, value, options }) =>
              cookieStore.set(name, value, options)
            )
          } catch {
          }
        },
      },
    }
  )
}
EOF

# Create middleware.ts
cat > middleware.ts << 'EOF'
import { createServerClient } from '@supabase/ssr'
import { NextResponse, type NextRequest } from 'next/server'

export async function updateSession(request: NextRequest) {
  let supabaseResponse = NextResponse.next({ request })

  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll() {
          return request.cookies.getAll()
        },
        setAll(cookiesToSet) {
          cookiesToSet.forEach(({ name, value }) =>
            request.cookies.set(name, value)
          )
          supabaseResponse = NextResponse.next({ request })
          cookiesToSet.forEach(({ name, value, options }) =>
            supabaseResponse.cookies.set(name, value, options)
          )
        },
      },
    }
  )

  await supabase.auth.getUser()
  return supabaseResponse
}

export async function middleware(request: NextRequest) {
  return await updateSession(request)
}

export const config = {
  matcher: [
    '/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp)$).*)',
  ],
}
EOF

# Create components
mkdir -p components

cat > components/sidebar.tsx << 'EOF'
'use client'

import Link from 'next/link'
import { usePathname } from 'next/navigation'
import {
  LayoutDashboard,
  Calculator,
  TrendingUp,
  Users,
  FileText,
  BarChart3,
  Settings,
  Briefcase,
} from 'lucide-react'
import { clsx } from 'clsx'

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

  return (
    <aside className="flex h-screen w-64 flex-col border-r border-gray-200 bg-white">
      <div className="flex h-16 items-center gap-2 border-b border-gray-200 px-6">
        <div className="flex h-8 w-8 items-center justify-center rounded-lg bg-indigo-600 text-white font-bold">
          OS
        </div>
        <span className="text-lg font-semibold text-gray-900">OpenSourcingOS</span>
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
                      ? 'bg-indigo-50 text-indigo-700'
                      : 'text-gray-600 hover:bg-gray-100 hover:text-gray-900'
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

      <div className="border-t border-gray-200 p-4">
        <div className="rounded-lg bg-gray-50 px-3 py-2 text-xs text-gray-500">
          MVP • Beta Version
        </div>
      </div>
    </aside>
  )
}
EOF

cat > components/app-layout.tsx << 'EOF'
import { Sidebar } from './sidebar'

export function AppLayout({ children }: { children: React.ReactNode }) {
  return (
    <div className="flex h-screen overflow-hidden">
      <Sidebar />
      <main className="flex-1 overflow-y-auto bg-gray-50">
        {children}
      </main>
    </div>
  )
}
EOF

# Overwrite app/layout.tsx
cat > app/layout.tsx << 'EOF'
import type { Metadata } from 'next'
import { Inter } from 'next/font/google'
import './globals.css'
import { AppLayout } from '@/components/app-layout'

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
    <html lang="en">
      <body className={inter.className}>
        <AppLayout>{children}</AppLayout>
      </body>
    </html>
  )
}
EOF

# Overwrite app/page.tsx
cat > app/page.tsx << 'EOF'
import { redirect } from 'next/navigation'

export default function Home() {
  redirect('/dashboard')
}
EOF

# Create all page folders
mkdir -p app/dashboard app/events app/savings app/realization app/suppliers app/contracts app/reports app/settings

cat > app/dashboard/page.tsx << 'EOF'
export default function DashboardPage() {
  return (
    <div className="p-8">
      <h1 className="text-2xl font-bold text-gray-900">Dashboard</h1>
      <p className="mt-2 text-gray-600">
        Welcome to OpenSourcingOS. Your procurement value tracker is being set up.
      </p>
      <div className="mt-8 grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <div className="rounded-lg border border-gray-200 bg-white p-6 shadow-sm">
          <p className="text-sm font-medium text-gray-500">Total Savings</p>
          <p className="mt-2 text-3xl font-bold text-gray-900">$0</p>
        </div>
        <div className="rounded-lg border border-gray-200 bg-white p-6 shadow-sm">
          <p className="text-sm font-medium text-gray-500">Active Events</p>
          <p className="mt-2 text-3xl font-bold text-gray-900">0</p>
        </div>
        <div className="rounded-lg border border-gray-200 bg-white p-6 shadow-sm">
          <p className="text-sm font-medium text-gray-500">Pipeline Value</p>
          <p className="mt-2 text-3xl font-bold text-gray-900">$0</p>
        </div>
        <div className="rounded-lg border border-gray-200 bg-white p-6 shadow-sm">
          <p className="text-sm font-medium text-gray-500">Realized Savings</p>
          <p className="mt-2 text-3xl font-bold text-gray-900">$0</p>
        </div>
      </div>
    </div>
  )
}
EOF

cat > app/events/page.tsx << 'EOF'
export default function EventsPage() {
  return (
    <div className="p-8">
      <h1 className="text-2xl font-bold text-gray-900">Sourcing Events</h1>
      <p className="mt-2 text-gray-600">Sourcing events will appear here.</p>
    </div>
  )
}
EOF

cat > app/savings/page.tsx << 'EOF'
export default function SavingsPage() {
  return (
    <div className="p-8">
      <h1 className="text-2xl font-bold text-gray-900">Savings Calculations</h1>
      <p className="mt-2 text-gray-600">Savings calculations will appear here.</p>
    </div>
  )
}
EOF

cat > app/realization/page.tsx << 'EOF'
export default function RealizationPage() {
  return (
    <div className="p-8">
      <h1 className="text-2xl font-bold text-gray-900">Realization</h1>
      <p className="mt-2 text-gray-600">Realization tracking will appear here.</p>
    </div>
  )
}
EOF

cat > app/suppliers/page.tsx << 'EOF'
export default function SuppliersPage() {
  return (
    <div className="p-8">
      <h1 className="text-2xl font-bold text-gray-900">Suppliers</h1>
      <p className="mt-2 text-gray-600">Supplier directory will appear here.</p>
    </div>
  )
}
EOF

cat > app/contracts/page.tsx << 'EOF'
export default function ContractsPage() {
  return (
    <div className="p-8">
      <h1 className="text-2xl font-bold text-gray-900">Contracts</h1>
      <p className="mt-2 text-gray-600">Contract records will appear here.</p>
    </div>
  )
}
EOF

cat > app/reports/page.tsx << 'EOF'
export default function ReportsPage() {
  return (
    <div className="p-8">
      <h1 className="text-2xl font-bold text-gray-900">Reports</h1>
      <p className="mt-2 text-gray-600">Reports and exports will appear here.</p>
    </div>
  )
}
EOF

cat > app/settings/page.tsx << 'EOF'
export default function SettingsPage() {
  return (
    <div className="p-8">
      <h1 className="text-2xl font-bold text-gray-900">Settings</h1>
      <p className="mt-2 text-gray-600">System settings will appear here.</p>
    </div>
  )
}
EOF

# Clean up
rm -f public/vercel.svg public/next.svg app/favicon.ico
rm -rf .next

echo "DONE"
