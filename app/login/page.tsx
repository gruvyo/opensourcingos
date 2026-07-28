'use client'

import { useState, useEffect } from 'react'
import { useRouter } from 'next/navigation'
import { createClient } from '@/lib/supabase/client'
import { Card } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { clsx } from 'clsx'

export default function LoginPage() {
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [mode, setMode] = useState<'signin' | 'signup'>('signin')
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const router = useRouter()
  const supabase = createClient()

  // /auth/callback bounces a failed code exchange back here with ?error=.
  // Without this the redirect would look like an ordinary visit to the login
  // page and the reason for it would be lost.
  //
  // Read from window rather than useSearchParams deliberately: this page is
  // statically prerendered, and useSearchParams would force a Suspense
  // boundary around it for the sake of a one-shot message.
  // Only a known CODE is honoured, and the wording is ours. The URL never gets
  // to choose what this page says -- see the comment in app/auth/callback.
  useEffect(() => {
    if (new URLSearchParams(window.location.search).get('error') === 'auth') {
      setError('That sign-in link could not be completed. Please sign in again.')
    }
  }, [])

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    setLoading(true)
    setError(null)

    if (mode === 'signin') {
      const { error } = await supabase.auth.signInWithPassword({ email, password })
      if (error) {
        setError(error.message)
        setLoading(false)
      } else {
        router.push('/dashboard')
        router.refresh()
      }
    } else {
      const { error } = await supabase.auth.signUp({ email, password })
      if (error) {
        setError(error.message)
        setLoading(false)
      } else {
        router.push('/dashboard')
        router.refresh()
      }
    }
  }

  /**
   * Google is the primary way in. It means a tester never invents a password
   * for a demo, and their name and email arrive verified rather than typed.
   *
   * Email and password are kept below the divider deliberately: removing them
   * before Google is confirmed working in this environment would lock everyone
   * out, including whoever needs to fix it. Retire them once Google is proven.
   */
  const signInWithGoogle = async () => {
    setLoading(true)
    setError(null)
    const { error } = await supabase.auth.signInWithOAuth({
      provider: 'google',
      // /auth/callback exchanges the code and bounces failures back here.
      options: { redirectTo: `${window.location.origin}/auth/callback` },
    })
    // On success the browser is already navigating away, so only a failure
    // ever gets this far.
    if (error) {
      setError(
        /provider is not enabled/i.test(error.message)
          ? 'Google sign-in is not switched on for this site yet. Use email and password below.'
          : error.message,
      )
      setLoading(false)
    }
  }

  const tabClass = (active: boolean) =>
    clsx(
      'flex-1 rounded-md py-2 text-sm font-medium transition-colors',
      active
        ? 'bg-[var(--brand)] text-[var(--on-brand)]'
        : 'bg-[var(--surface-2)] text-[var(--text-2)] hover:text-[var(--text)]',
    )

  return (
    <div className="flex min-h-screen items-center justify-center bg-[var(--bg)] px-4">
      <div className="w-full max-w-md">
        <div className="mb-8 flex items-center justify-center gap-2">
          <span className="text-3xl font-bold text-[var(--text)]">OpenSourcing</span>
          <div className="flex h-10 w-10 items-center justify-center rounded-lg bg-[var(--brand)] text-lg text-white font-bold">
            OS
          </div>
        </div>

        <Card className="p-8">
          <button
            onClick={signInWithGoogle}
            disabled={loading}
            className="flex w-full items-center justify-center gap-3 rounded-md border border-[var(--border-strong)] bg-[var(--surface)] px-4 py-2.5 text-sm font-semibold text-[var(--text)] transition-colors hover:bg-[var(--surface-2)] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--brand)] disabled:cursor-not-allowed disabled:opacity-50"
          >
            {/* Google's mark. Inline so the page has no external requests —
                a login screen that waits on a CDN is a login screen that
                sometimes does not appear. */}
            <svg className="h-4 w-4" viewBox="0 0 18 18" aria-hidden="true">
              <path fill="#4285F4" d="M17.64 9.2c0-.64-.06-1.25-.16-1.84H9v3.48h4.84a4.14 4.14 0 0 1-1.8 2.72v2.26h2.92c1.71-1.57 2.68-3.89 2.68-6.62Z" />
              <path fill="#34A853" d="M9 18c2.43 0 4.47-.8 5.96-2.18l-2.92-2.26c-.81.54-1.84.86-3.04.86-2.34 0-4.32-1.58-5.03-3.7H.96v2.33A9 9 0 0 0 9 18Z" />
              <path fill="#FBBC05" d="M3.97 10.72a5.41 5.41 0 0 1 0-3.44V4.95H.96a9 9 0 0 0 0 8.1l3.01-2.33Z" />
              <path fill="#EA4335" d="M9 3.58c1.32 0 2.5.45 3.44 1.35l2.58-2.59C13.46.89 11.43 0 9 0A9 9 0 0 0 .96 4.95l3.01 2.33C4.68 5.16 6.66 3.58 9 3.58Z" />
            </svg>
            {loading ? 'Please wait…' : 'Continue with Google'}
          </button>

          <p className="mt-3 text-center text-xs text-[var(--text-3)]">
            New here? Signing in with Google creates your own private workspace, pre-loaded with
            example projects to explore. Nothing you change affects anyone else.
          </p>

          <div className="my-6 flex items-center gap-3">
            <span className="h-px flex-1 bg-[var(--border)]" />
            <span className="text-xs text-[var(--text-3)]">or use email</span>
            <span className="h-px flex-1 bg-[var(--border)]" />
          </div>

          <div className="mb-6 flex gap-2">
            <button onClick={() => { setMode('signin'); setError(null) }} className={tabClass(mode === 'signin')}>
              Sign In
            </button>
            <button onClick={() => { setMode('signup'); setError(null) }} className={tabClass(mode === 'signup')}>
              Sign Up
            </button>
          </div>

          <form onSubmit={handleSubmit} className="space-y-4">
            <div className="space-y-1.5">
              <label htmlFor="email" className="block text-sm font-medium text-[var(--text-2)]">Email</label>
              <Input
                id="email"
                type="email"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                required
                autoComplete="email"
              />
            </div>
            <div className="space-y-1.5">
              <label htmlFor="password" className="block text-sm font-medium text-[var(--text-2)]">Password</label>
              <Input
                id="password"
                type="password"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                required
                minLength={6}
                autoComplete={mode === 'signin' ? 'current-password' : 'new-password'}
              />
              <p className="text-xs text-[var(--text-3)]">Minimum 6 characters</p>
            </div>

            {error && (
              <div className="rounded-md bg-[var(--danger-soft)] px-3 py-2.5 text-sm text-[var(--danger)]" role="alert">
                {error}
              </div>
            )}

            <Button type="submit" disabled={loading} className="w-full">
              {loading ? 'Please wait…' : mode === 'signin' ? 'Sign In' : 'Create Account'}
            </Button>
          </form>
        </Card>
      </div>
    </div>
  )
}
