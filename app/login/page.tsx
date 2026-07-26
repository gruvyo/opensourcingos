'use client'

import { useState } from 'react'
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
