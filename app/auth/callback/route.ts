import { createClient } from '@/lib/supabase/server'
import { NextResponse } from 'next/server'

export async function GET(request: Request) {
  const { searchParams, origin } = new URL(request.url)
  const code = searchParams.get('code')

  if (!code) {
    // Reached without a code: not a sign-in attempt. Send them to sign in
    // rather than to a dashboard that row-level security will render empty.
    return NextResponse.redirect(`${origin}/login`)
  }

  const supabase = await createClient()
  const { error } = await supabase.auth.exchangeCodeForSession(code)

  // A failed exchange used to redirect to /dashboard anyway. With RLS in force
  // that renders as a portfolio with no rows in it -- a broken sign-in and an
  // empty database look identical, and the user has no way to tell which they
  // are looking at. Send them back to sign in, and say why.
  if (error) {
    // A CODE, never the message. Reflecting the provider's text into the URL
    // would let anyone craft /login?error=<anything> and have the sign-in page
    // render their words as if they were ours -- React escapes it, so it is not
    // XSS, but "your session expired, call this number" on a real login screen
    // is a good enough phishing page without needing script. The real message
    // stays in the server log where it is useful and cannot be forged.
    console.error('[auth/callback] code exchange failed:', error.message)
    return NextResponse.redirect(`${origin}/login?error=auth`)
  }

  return NextResponse.redirect(`${origin}/dashboard`)
}
