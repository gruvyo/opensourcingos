#!/bin/bash

cd "/Users/torresus/Ω Local-NonSync/2026-07-19-open-sourcing-os/opensourcingos"

# Create dynamic OpenGraph image (Next.js will auto-generate a PNG)
cat > app/opengraph-image.tsx << 'EOF'
import { ImageResponse } from 'next/og'

export const alt = 'OpenSourcingOS — Procurement Value Tracker'
export const size = { width: 1200, height: 630 }
export const contentType = 'image/png'

export default async function Image() {
  return new ImageResponse(
    (
      <div
        style={{
          width: '100%',
          height: '100%',
          display: 'flex',
          flexDirection: 'column',
          alignItems: 'center',
          justifyContent: 'center',
          background: 'linear-gradient(135deg, #0f172a 0%, #1e1b4b 50%, #312e81 100%)',
          fontFamily: 'system-ui, -apple-system, sans-serif',
        }}
      >
        {/* Logo */}
        <div
          style={{
            display: 'flex',
            alignItems: 'center',
            gap: '16px',
            marginBottom: '48px',
          }}
        >
          <span
            style={{
              fontSize: '80px',
              fontWeight: 700,
              color: '#f8fafc',
              letterSpacing: '-2px',
            }}
          >
            OpenSourcing
          </span>
          <div
            style={{
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              width: '72px',
              height: '72px',
              borderRadius: '14px',
              backgroundColor: '#4f46e5',
              fontSize: '36px',
              fontWeight: 700,
              color: '#ffffff',
            }}
          >
            OS
          </div>
        </div>

        {/* Tagline */}
        <div
          style={{
            fontSize: '36px',
            color: '#a5b4fc',
            marginBottom: '20px',
            fontWeight: 500,
          }}
        >
          Procurement Value Tracker
        </div>

        {/* Feature list */}
        <div
          style={{
            fontSize: '26px',
            color: '#94a3b8',
            display: 'flex',
            gap: '24px',
          }}
        >
          <span>Sourcing</span>
          <span style={{ color: '#4f46e5' }}>•</span>
          <span>Baselines</span>
          <span style={{ color: '#4f46e5' }}>•</span>
          <span>Offers</span>
          <span style={{ color: '#4f46e5' }}>•</span>
          <span>Savings</span>
          <span style={{ color: '#4f46e5' }}>•</span>
          <span>Realization</span>
        </div>
      </div>
    ),
    { ...size }
  )
}
EOF

# Update layout.tsx with full OpenGraph + Twitter metadata
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
  title: {
    default: 'OpenSourcingOS — Procurement Value Tracker',
    template: '%s | OpenSourcingOS',
  },
  description: 'Track sourcing events, baselines, supplier offers, savings calculations, and realization — all in one procurement value management platform.',
  keywords: [
    'procurement',
    'sourcing',
    'savings tracker',
    'cost avoidance',
    'baseline modeling',
    'should-cost',
    'offer comparison',
    'realization tracking',
    'procurement value',
    'CPSM',
  ],
  authors: [{ name: 'OpenSourcingOS' }],
  creator: 'OpenSourcingOS',
  openGraph: {
    type: 'website',
    locale: 'en_US',
    url: siteUrl,
    siteName: 'OpenSourcingOS',
    title: 'OpenSourcingOS — Procurement Value Tracker',
    description: 'Track sourcing events, baselines, supplier offers, savings calculations, and realization — all in one procurement value management platform.',
    images: [
      {
        url: '/opengraph-image',
        width: 1200,
        height: 630,
        alt: 'OpenSourcingOS — Procurement Value Tracker',
      },
    ],
  },
  twitter: {
    card: 'summary_large_image',
    title: 'OpenSourcingOS — Procurement Value Tracker',
    description: 'Track sourcing events, baselines, supplier offers, savings calculations, and realization — all in one procurement value management platform.',
    images: ['/opengraph-image'],
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

# Clear build cache
rm -rf .next

echo "DONE"
