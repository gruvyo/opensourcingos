'use client'

import { usePathname } from 'next/navigation'
import { AppLayout } from './app-layout'

export function AppShell({ children }: { children: React.ReactNode }) {
  const pathname = usePathname()
  const hideLayout = pathname === '/' || pathname === '/login'

  if (hideLayout) {
    return <>{children}</>
  }

  return <AppLayout>{children}</AppLayout>
}
