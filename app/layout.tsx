import type { Metadata } from 'next'
import { Inter } from 'next/font/google'
import './globals.css'
import { AppShell } from '@/components/app-shell'
import { ThemeProvider } from '@/components/theme-provider'

const inter = Inter({ subsets: ['latin'] })

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
