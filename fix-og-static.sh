#!/bin/bash

cd "/Users/torresus/Ω Local-NonSync/2026-07-19-open-sourcing-os/opensourcingos"

# Create a static SVG OG image in the public folder
cat > public/og-image.svg << 'EOF'
<svg xmlns="http://www.w3.org/2000/svg" width="1200" height="630" viewBox="0 0 1200 630">
  <defs>
    <linearGradient id="bg" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" style="stop-color:#0f172a"/>
      <stop offset="50%" style="stop-color:#1e1b4b"/>
      <stop offset="100%" style="stop-color:#312e81"/>
    </linearGradient>
  </defs>
  <rect width="1200" height="630" fill="url(#bg)"/>
  
  <!-- Logo -->
  <text x="340" y="280" font-family="system-ui, -apple-system, sans-serif" font-size="80" font-weight="700" fill="#f8fafc" letter-spacing="-2">OpenSourcing</text>
  <rect x="800" y="210" width="72" height="72" rx="14" fill="#4f46e5"/>
  <text x="836" y="262" font-family="system-ui, -apple-system, sans-serif" font-size="36" font-weight="700" fill="white" text-anchor="middle">OS</text>
  
  <!-- Tagline -->
  <text x="600" y="370" font-family="system-ui, -apple-system, sans-serif" font-size="36" font-weight="500" fill="#a5b4fc" text-anchor="middle">Procurement Value Tracker</text>
  
  <!-- Features -->
  <text x="600" y="450" font-family="system-ui, -apple-system, sans-serif" font-size="26" fill="#94a3b8" text-anchor="middle">Sourcing • Baselines • Offers • Savings • Realization</text>
</svg>
EOF

# Remove the dynamic OG image route
rm -f app/opengraph-image.tsx

# Update layout to reference the static image
cat > app/layout.tsx << 'EOF'
import type { Metadata } from 'next'
import { Inter } from 'next/font/google'
import './globals.css'
import { AppShell } from '@/components/app-shell'
import { ThemeProvider } from '@/components/theme-provider'

const inter = Inter({ subsets: ['latin'] })

const siteUrl = 'https://opensourcingos-lac.vercel.app'

export const metadata: Metadata = {
  metadataBase: new URL(siteUrl),
  title: 'OpenSourcingOS — Procurement Value Tracker',
  description: 'Track sourcing events, baselines, supplier offers, savings, and realization in one procurement platform.',
  keywords: [
    'procurement', 'sourcing', 'savings tracker', 'cost avoidance',
    'baseline modeling', 'should-cost', 'offer comparison',
    'realization tracking', 'procurement value', 'CPSM',
  ],
  authors: [{ name: 'OpenSourcingOS' }],
  creator: 'OpenSourcingOS',
  openGraph: {
    type: 'website',
    locale: 'en_US',
    url: siteUrl,
    siteName: 'OpenSourcingOS',
    title: 'OpenSourcingOS — Procurement Value Tracker',
    description: 'Track sourcing events, baselines, supplier offers, savings, and realization in one procurement platform.',
    images: [
      {
        url: '/og-image.svg',
        width: 1200,
        height: 630,
        alt: 'OpenSourcingOS — Procurement Value Tracker',
      },
    ],
  },
  twitter: {
    card: 'summary_large_image',
    title: 'OpenSourcingOS — Procurement Value Tracker',
    description: 'Track sourcing events, baselines, supplier offers, savings, and realization in one procurement platform.',
    images: ['/og-image.svg'],
  },
  icons: {
    icon: [
      {
        url: 'data:image/svg+xml,<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><rect width="100" height="100" rx="20" fill="%234f46e5"/><text x="50" y="70" font-size="50" font-weight="bold" fill="white" text-anchor="middle" font-family="system-ui">OS</text></svg>',
      },
    ],
  },
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

rm -rf .next

echo "DONE"
