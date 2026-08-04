'use client'

import { Suspense, useState } from 'react'
import { useSearchParams } from 'next/navigation'
import { createClient } from '@/lib/supabase/client'
import { Card } from '@/components/ui/card'

/**
 * Sign in. Google only.
 *
 * The email and password form was removed on 2026-07-28 once Google was
 * proven working. It was never the intended path -- it asked people to invent
 * a password for a demo they would use twice -- and leaving it alongside
 * Google presented two doors where only one was meant. The Sign In / Sign Up
 * tabs went with it: with Google there is no distinction to make. Signing in
 * for the first time IS signing up, and the app says so rather than asking
 * anyone to choose.
 *
 * Everything below the button is doing one job: telling a first-time visitor
 * what will happen to them if they click it.
 */
export default function LoginPage() {
  return (
    <Suspense fallback={<LoginPageFallback />}>
      <LoginPageContent />
    </Suspense>
  )
}

function LoginPageContent() {
  const searchParams = useSearchParams()
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(() =>
    searchParams.get('error') === 'auth'
      ? 'That sign-in could not be completed. Please try again.'
      : null,
  )
  const supabase = createClient()

  const signInWithGoogle = async () => {
    setLoading(true)
    setError(null)
    const { error } = await supabase.auth.signInWithOAuth({
      provider: 'google',
      options: { redirectTo: `${window.location.origin}/auth/callback` },
    })
    // On success the browser is already navigating away, so only a failure
    // reaches this line.
    if (error) {
      setError(
        /provider is not enabled/i.test(error.message)
          ? 'Google sign-in is not switched on for this site yet.'
          : error.message,
      )
      setLoading(false)
    }
  }

  return (
    <main id="main-content" tabIndex={-1} className="flex min-h-screen items-center justify-center bg-[var(--bg)] px-4">
      <div className="w-full max-w-md">
        <div className="mb-8 flex items-center justify-center gap-2">
          <span className="text-3xl font-bold text-[var(--text)]">OpenSourcing</span>
          <div className="flex h-10 w-10 items-center justify-center rounded-lg bg-[var(--brand)] text-lg font-bold text-white">
            OS
          </div>
        </div>

        <Card className="p-8">
          <h1 className="text-center text-lg font-semibold text-[var(--text)]">
            Sign in to OpenSourcingOS
          </h1>
          <p className="mt-1 text-center text-sm text-[var(--text-2)]">
            Procurement savings, tracked properly.
          </p>

          <button
            type="button"
            onClick={signInWithGoogle}
            disabled={loading}
            className="mt-6 flex w-full items-center justify-center gap-3 rounded-md border border-[var(--border-strong)] bg-[var(--surface)] px-4 py-2.5 text-sm font-semibold text-[var(--text)] transition-colors hover:bg-[var(--surface-2)] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--brand)] disabled:cursor-not-allowed disabled:opacity-50"
          >
            {/* Google's mark, inline. A login screen that waits on a CDN is a
                login screen that sometimes does not appear. */}
            <svg className="h-4 w-4" viewBox="0 0 18 18" aria-hidden="true">
              <path fill="#4285F4" d="M17.64 9.2c0-.64-.06-1.25-.16-1.84H9v3.48h4.84a4.14 4.14 0 0 1-1.8 2.72v2.26h2.92c1.71-1.57 2.68-3.89 2.68-6.62Z" />
              <path fill="#34A853" d="M9 18c2.43 0 4.47-.8 5.96-2.18l-2.92-2.26c-.81.54-1.84.86-3.04.86-2.34 0-4.32-1.58-5.03-3.7H.96v2.33A9 9 0 0 0 9 18Z" />
              <path fill="#FBBC05" d="M3.97 10.72a5.41 5.41 0 0 1 0-3.44V4.95H.96a9 9 0 0 0 0 8.1l3.01-2.33Z" />
              <path fill="#EA4335" d="M9 3.58c1.32 0 2.5.45 3.44 1.35l2.58-2.59C13.46.89 11.43 0 9 0A9 9 0 0 0 .96 4.95l3.01 2.33C4.68 5.16 6.66 3.58 9 3.58Z" />
            </svg>
            {loading ? 'Please wait…' : 'Continue with Google'}
          </button>

          {error && (
            <div className="mt-4 rounded-md bg-[var(--danger-soft)] px-3 py-2.5 text-sm text-[var(--danger)]" role="alert">
              {error}
            </div>
          )}

          <div className="mt-6 border-t border-[var(--border)] pt-5">
            <p className="text-sm text-[var(--text-2)]">
              <strong className="text-[var(--text)]">First time here?</strong> There is nothing to
              sign up for. Continuing with Google creates your own private workspace, already filled
              with example projects so there is something to look at.
            </p>
            <p className="mt-3 text-xs text-[var(--text-3)]">
              Explore freely — edit figures, delete things, break whatever you like. Your workspace
              is yours alone, and nothing you change is visible to anyone else.
            </p>
          </div>
        </Card>

        {/* Google shows an "unverified app" warning for demos like this one.
            Saying so up front stops it reading as something being wrong. */}
        <p className="mt-4 text-center text-xs text-[var(--text-3)]">
          Google may warn that this app is unverified — expected while it is in preview.
          Choose <span className="font-medium">Advanced</span> →{' '}
          <span className="font-medium">Go to OpenSourcingOS</span> to continue.
        </p>

        <nav className="mt-5 flex flex-wrap items-center justify-center gap-x-3 gap-y-2 text-xs text-[var(--text-3)]" aria-label="Project and support links">
          <a
            href="https://opensourcingos.com"
            className="transition-colors hover:text-[var(--brand)] hover:underline focus-visible:rounded-sm focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--brand)]"
          >
            About the project
          </a>
          <span aria-hidden="true">·</span>
          <a
            href="https://github.com/gruvyo/opensourcingos"
            target="_blank"
            rel="noreferrer"
            className="transition-colors hover:text-[var(--brand)] hover:underline focus-visible:rounded-sm focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--brand)]"
          >
            View on GitHub
          </a>
          <span aria-hidden="true">·</span>
          <a
            href="mailto:hello@opensourcingos.com"
            className="transition-colors hover:text-[var(--brand)] hover:underline focus-visible:rounded-sm focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--brand)]"
          >
            Contact us
          </a>
        </nav>
      </div>
    </main>
  )
}

function LoginPageFallback() {
  return (
    <main id="main-content" tabIndex={-1} className="flex min-h-screen items-center justify-center bg-[var(--bg)] px-4">
      <p className="text-sm text-[var(--text-2)]">Loading sign in…</p>
    </main>
  )
}
