import assert from 'node:assert/strict'
import test from 'node:test'
import { formatReportValue, reportColumnLabel, reportCsvMoney } from '../lib/report-format.ts'

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
})
