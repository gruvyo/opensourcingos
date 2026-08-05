import { pathToFileURL } from 'node:url'

const URL_VARIABLE = 'NEXT_PUBLIC_SUPABASE_URL'
const KEY_VARIABLE = 'NEXT_PUBLIC_SUPABASE_ANON_KEY'

export function validateSupabaseEnv(env) {
  const errors = []
  const rawUrl = env[URL_VARIABLE]?.trim()
  const publicKey = env[KEY_VARIABLE]?.trim()

  if (!rawUrl) {
    errors.push(`${URL_VARIABLE} is required.`)
  } else {
    try {
      const url = new URL(rawUrl)

      if (!['http:', 'https:'].includes(url.protocol)) {
        errors.push(`${URL_VARIABLE} must use http:// or https://.`)
      }

      if (url.username || url.password) {
        errors.push(`${URL_VARIABLE} must not contain embedded credentials.`)
      }
    } catch {
      errors.push(`${URL_VARIABLE} must be a valid URL.`)
    }
  }

  if (!publicKey) {
    errors.push(`${KEY_VARIABLE} is required.`)
  } else if (publicKey.startsWith('sb_secret_')) {
    errors.push(`${KEY_VARIABLE} must never contain a Supabase secret key.`)
  } else if (!publicKey.startsWith('sb_publishable_')) {
    errors.push(`${KEY_VARIABLE} must use the browser-safe sb_publishable_ format.`)
  } else if (publicKey.includes('YOUR_PUBLISHABLE_KEY')) {
    errors.push(`${KEY_VARIABLE} still contains the example placeholder.`)
  }

  return errors
}

export function verifySupabaseEnv(env = process.env) {
  const errors = validateSupabaseEnv(env)

  if (errors.length > 0) {
    console.error('Supabase environment validation failed:')
    errors.forEach((error) => console.error(`- ${error}`))
    return false
  }

  console.log('Supabase public environment variables are valid.')
  return true
}

const entryPoint = process.argv[1] ? pathToFileURL(process.argv[1]).href : null

if (entryPoint === import.meta.url && !verifySupabaseEnv()) {
  process.exitCode = 1
}
