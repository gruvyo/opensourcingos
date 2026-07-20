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
