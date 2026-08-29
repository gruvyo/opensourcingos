import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'
import { formatReportValue, reportColumnLabel, reportCsvCell, reportCsvMoney } from '../lib/report-format.ts'

test('formats report money with the workspace currency and locale', () => {
  assert.equal(formatReportValue(1234.5, 'currency', undefined, 'EUR', 'en-GB'), '€1,234.50')
  assert.equal(formatReportValue(-1234.5, 'reduction', undefined, 'EUR', 'en-GB'), '(€1,234.50)')
  assert.equal(formatReportValue('2026-08-28', 'date', undefined, 'EUR', 'en-GB'), '28 Aug 2026')
})

test('identifies the workspace currency in CSV money headers', () => {
  assert.equal(reportColumnLabel('Total Savings', 'currency', 'EUR'), 'Total Savings (EUR)')
  assert.equal(reportColumnLabel('Cost Reduction', 'reduction', 'EUR'), 'Cost Reduction (EUR)')
  assert.equal(reportColumnLabel('Projects', 'number', 'EUR'), 'Projects')
  assert.equal(reportCsvMoney(1234.5), '1234.50')
  assert.equal(reportCsvMoney(-1234.5), '-1234.50')
  assert.equal(reportCsvCell(-12.5, 'percent'), '"-12.5"')
  assert.equal(reportCsvCell('-12.5', 'percent'), '"-12.5"')
  assert.equal(reportCsvCell('=HYPERLINK("https://example.com")', 'text'), '"\'=HYPERLINK(""https://example.com"")"')
})

test('attention queue dates use the workspace formatter', () => {
  const source = readFileSync(new URL('../components/attention-queue.tsx', import.meta.url), 'utf8')
  assert.match(source, /useWorkspaceFormat\(\)/)
  assert.match(source, /formatDate\(item\.date\)/)
  assert.doesNotMatch(source, /new Intl\.DateTimeFormat\(['"]en-US['"]/)
  assert.doesNotMatch(source, /timeZone:\s*['"]UTC['"]/)
})
