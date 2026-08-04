import type { Metadata } from 'next'
import './globals.css'
import { AppShell } from '@/components/app-shell'
import { ThemeProvider } from '@/components/theme-provider'

const siteUrl = 'https://opensourcingos.com'
const siteTitle = 'OpenSourcingOS — Procurement Savings, Tracked Properly'
const siteDescription = 'Open-source procurement value tracking for sourcing projects, baselines, supplier offers, savings schedules, fiscal-year reporting, and realization.'

export const metadata: Metadata = {
  metadataBase: new URL(siteUrl),
  title: siteTitle,
  description: siteDescription,
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
    title: siteTitle,
    description: siteDescription,
    images: [
      {
        url: '/og-image.png',
        width: 1280,
        height: 640,
        alt: 'OpenSourcingOS — Procurement savings, tracked properly',
      },
    ],
  },
  twitter: {
    card: 'summary_large_image',
    title: siteTitle,
    description: siteDescription,
    images: ['/og-image.png'],
  },
}

export default function RootLayout({
  children,
}: {
  children: React.ReactNode
}) {
  return (
    <html lang="en" suppressHydrationWarning>
      <body>
        <a href="#main-content" className="skip-link">Skip to main content</a>
        <ThemeProvider>
          <AppShell>{children}</AppShell>
        </ThemeProvider>
      </body>
    </html>
  )
}
