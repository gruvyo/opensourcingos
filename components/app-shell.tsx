'use client'

import { usePathname } from 'next/navigation'
import { AppLayout } from './app-layout'

const HIDE_LAYOUT_ROUTES = ['/login']

export function AppShell({ children }: { children: React.ReactNode }) {
  const pathname = usePathname()
  const hideLayout = HIDE_LAYOUT_ROUTES.some(route => pathname.startsWith(route))

  if (hideLayout) {
    return <>{children}</>
  }

  return <AppLayout>{children}</AppLayout>
}
