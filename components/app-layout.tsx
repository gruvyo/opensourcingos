'use client'

import { useState } from 'react'
import { Sidebar } from './sidebar'

export function AppLayout({ children }: { children: React.ReactNode }) {
  const [sidebarOpen, setSidebarOpen] = useState(false)

  return (
    <div className="flex min-h-screen bg-[var(--bg)]">
      {/* Mobile backdrop overlay */}
      {sidebarOpen && (
        <div
          className="fixed inset-0 z-30 bg-black/50 lg:hidden"
          onClick={() => setSidebarOpen(false)}
        />
      )}

      <Sidebar open={sidebarOpen} onClose={() => setSidebarOpen(false)} />

      <div className="flex min-w-0 flex-1 flex-col">
        {/* Mobile top bar */}
        <div className="sticky top-0 z-20 flex h-14 items-center gap-3 border-b border-white/10 bg-[var(--nav-bg)] px-4 text-white lg:hidden">
          <button
            type="button"
            onClick={() => setSidebarOpen(true)}
            className="rounded-lg p-1.5 text-slate-300 transition-colors hover:bg-white/10 hover:text-white"
            aria-label="Open menu"
            aria-expanded={sidebarOpen}
            aria-controls="mobile-navigation"
          >
            <svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
              <line x1="4" x2="20" y1="6" y2="6"/>
              <line x1="4" x2="20" y1="12" y2="12"/>
              <line x1="4" x2="20" y1="18" y2="18"/>
            </svg>
          </button>
          <div className="flex items-center gap-2">
            <span className="text-base font-semibold text-white">OpenSourcing</span>
            <div className="flex h-6 w-6 items-center justify-center rounded-md bg-gradient-to-br from-indigo-500 to-violet-500 text-xs font-bold text-white shadow-sm shadow-indigo-950/40">
              OS
            </div>
          </div>
        </div>

        {/* Main content */}
        <main id="main-content" tabIndex={-1} className="app-canvas min-w-0 flex-1">
          {children}
        </main>
      </div>
    </div>
  )
}
