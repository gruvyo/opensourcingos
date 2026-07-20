#!/bin/bash

cd "/Users/torresus/Ω Local-NonSync/2026-07-19-open-sourcing-os/opensourcingos"

# Update theme provider to default to dark mode
cat > components/theme-provider.tsx << 'EOF'
'use client'

import { ThemeProvider as NextThemesProvider } from 'next-themes'

export function ThemeProvider({ children }: { children: React.ReactNode }) {
  return (
    <NextThemesProvider attribute="class" defaultTheme="dark" enableSystem={false} disableTransitionOnChange>
      {children}
    </NextThemesProvider>
  )
}
EOF

echo "DONE"
