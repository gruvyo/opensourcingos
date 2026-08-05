import assert from 'node:assert/strict'
import test from 'node:test'

import { validateSupabaseEnv } from './verify-supabase-env.mjs'

const validEnv = {
  NEXT_PUBLIC_SUPABASE_URL: 'https://example.supabase.co',
  NEXT_PUBLIC_SUPABASE_ANON_KEY: 'sb_publishable_test-value',
}

test('accepts a browser-safe hosted configuration', () => {
  assert.deepEqual(validateSupabaseEnv(validEnv), [])
})

test('accepts an HTTP URL for local Supabase', () => {
  assert.deepEqual(validateSupabaseEnv({
    ...validEnv,
    NEXT_PUBLIC_SUPABASE_URL: 'http://127.0.0.1:54321',
  }), [])
})

test('requires both public environment variables', () => {
  assert.deepEqual(validateSupabaseEnv({}), [
    'NEXT_PUBLIC_SUPABASE_URL is required.',
    'NEXT_PUBLIC_SUPABASE_ANON_KEY is required.',
  ])
})

test('rejects malformed URLs and embedded credentials', () => {
  assert.deepEqual(validateSupabaseEnv({
    ...validEnv,
    NEXT_PUBLIC_SUPABASE_URL: 'not-a-url',
  }), ['NEXT_PUBLIC_SUPABASE_URL must be a valid URL.'])

  assert.deepEqual(validateSupabaseEnv({
    ...validEnv,
    NEXT_PUBLIC_SUPABASE_URL: 'https://user:password@example.supabase.co',
  }), ['NEXT_PUBLIC_SUPABASE_URL must not contain embedded credentials.'])
})

test('rejects secret, legacy, and placeholder keys without echoing them', () => {
  assert.deepEqual(validateSupabaseEnv({
    ...validEnv,
    NEXT_PUBLIC_SUPABASE_ANON_KEY: 'sb_secret_do-not-expose',
  }), ['NEXT_PUBLIC_SUPABASE_ANON_KEY must never contain a Supabase secret key.'])

  assert.deepEqual(validateSupabaseEnv({
    ...validEnv,
    NEXT_PUBLIC_SUPABASE_ANON_KEY: 'eyJhbGciOiJIUzI1NiJ9.legacy.signature',
  }), ['NEXT_PUBLIC_SUPABASE_ANON_KEY must use the browser-safe sb_publishable_ format.'])

  assert.deepEqual(validateSupabaseEnv({
    ...validEnv,
    NEXT_PUBLIC_SUPABASE_ANON_KEY: 'sb_publishable_YOUR_PUBLISHABLE_KEY',
  }), ['NEXT_PUBLIC_SUPABASE_ANON_KEY still contains the example placeholder.'])
})
