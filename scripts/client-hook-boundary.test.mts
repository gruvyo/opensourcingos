import assert from 'node:assert/strict'
import { readdir, readFile } from 'node:fs/promises'
import path from 'node:path'
import test from 'node:test'

/**
 * A server component that calls a client-only hook builds green and then throws
 * on every request: "Attempted to call useX() from the server but useX is on
 * the client." That is how /dashboard went down in production — dashboard-stats
 * and fiscal-year-panel were switched from the pure lib/utils formatters to the
 * useWorkspaceFormat() context hook without gaining a 'use client' directive.
 *
 * Neither the build, the type checker, nor the linter catches it, so it is
 * checked here instead. The rule is simple: a file that calls one of these
 * hooks is a client component and must say so on its first line.
 */
const CLIENT_ONLY_HOOKS = [
  // React
  'useState', 'useEffect', 'useLayoutEffect', 'useContext', 'useReducer',
  'useCallback', 'useMemo', 'useRef', 'useTransition', 'useOptimistic',
  'useDeferredValue', 'useImperativeHandle', 'useSyncExternalStore',
  'useFormStatus', 'useActionState',
  // next/navigation
  'useRouter', 'useSearchParams', 'usePathname', 'useSelectedLayoutSegment',
  // ours
  'useWorkspaceFormat',
]

const ROOT = new URL('../', import.meta.url)

async function sourceFiles(dir: string, out: string[] = []): Promise<string[]> {
  const entries = await readdir(new URL(dir, ROOT), { withFileTypes: true })
  for (const entry of entries) {
    const rel = path.join(dir, entry.name)
    if (entry.isDirectory()) {
      if (entry.name !== 'node_modules' && entry.name !== '.next') await sourceFiles(rel, out)
    } else if (rel.endsWith('.ts') || rel.endsWith('.tsx')) {
      out.push(rel)
    }
  }
  return out
}

test('every file calling a client-only hook declares "use client"', async () => {
  const files = (await Promise.all(['app', 'components', 'lib'].map(d => sourceFiles(d)))).flat()

  // Guard the guard: if this ever scans nothing, the assertions below are vacuous.
  assert.ok(files.length > 20, `expected to scan the app, only found ${files.length} files`)

  const violations: string[] = []
  for (const file of files) {
    const source = await readFile(new URL(file, ROOT), 'utf8')
    const firstLine = source.split('\n').find(line => line.trim() !== '') ?? ''
    if (/^\s*['"]use client['"]/.test(firstLine)) continue

    const called = CLIENT_ONLY_HOOKS.filter(hook => new RegExp(`\\b${hook}\\s*\\(`).test(source))
    if (called.length > 0) violations.push(`${file} calls ${called.join(', ')}`)
  }

  assert.deepEqual(
    violations,
    [],
    `these files call a client-only hook without a 'use client' directive, which throws at ` +
      `request time on every render:\n  ${violations.join('\n  ')}`,
  )
})

test('the two components that took /dashboard down stay client components', async () => {
  for (const file of ['components/dashboard-stats.tsx', 'components/fiscal-year-panel.tsx']) {
    const source = await readFile(new URL(file, ROOT), 'utf8')
    assert.match(source, /^'use client'/, `${file} must remain a client component`)
    assert.match(source, /useWorkspaceFormat\(\)/, `${file} should still read workspace formatting`)
  }
})
