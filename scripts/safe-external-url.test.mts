import test from 'node:test'
import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import { safeExternalHttpUrl } from '../lib/safe-external-url.ts'

test('allows only absolute HTTP and HTTPS external links', () => {
  assert.equal(safeExternalHttpUrl('https://example.com/evidence'), 'https://example.com/evidence')
  assert.equal(safeExternalHttpUrl('HTTP://example.com'), 'http://example.com/')
  for (const value of ['javascript:alert(1)', 'data:text/html,hello', '//example.com', '/relative', 'not a url', '']) {
    assert.equal(safeExternalHttpUrl(value), null, `${value || 'empty value'} must not render as a link`)
  }
})

test('routes every supplier external link through the shared allowlist', async () => {
  const files = [
    'app/suppliers/[supplierId]/page.tsx',
    'components/supplier-certifications.tsx',
    'components/supplier-risk-register.tsx',
  ]
  for (const file of files) {
    const source = await readFile(new URL(`../${file}`, import.meta.url), 'utf8')
    assert.match(source, /<SafeExternalLink href=/, `${file} must use SafeExternalLink`)
  }
})
