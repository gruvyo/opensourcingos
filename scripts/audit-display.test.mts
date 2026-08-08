import assert from 'node:assert/strict'
import test from 'node:test'
import {
  auditActionLabel,
  auditChanges,
  auditEntityLabel,
  auditSubject,
  formatAuditTimestamp,
} from '../lib/audit-display.ts'

test('turns stored audit names into workspace language', () => {
  assert.equal(auditEntityLabel('organization_settings'), 'Workspace settings')
  assert.equal(auditEntityLabel('future_entity'), 'Future Entity')
  assert.equal(auditActionLabel('insert'), 'Added')
  assert.equal(auditActionLabel('update', 'project_classification_reset'), 'Reset')
})

test('uses the most useful record name as the subject', () => {
  assert.equal(auditSubject(null, { supplier_name: 'Acme Supply', id: '1' }), 'Acme Supply')
  assert.equal(auditSubject({ label: 'Legacy status' }, { label: 'Pipeline' }), 'Pipeline')
  assert.equal(auditSubject({ id: '1' }, { id: '1' }), null)
})

test('shows meaningful changes while excluding private and noisy fields', () => {
  const changes = auditChanges(
    { supplier_status: 'Active', preferred_flag: false, notes: 'private', updated_at: 'before' },
    { supplier_status: 'Inactive', preferred_flag: true, notes: 'more private', updated_at: 'after' },
  )
  assert.deepEqual(changes, [
    { field: 'supplier_status', label: 'Status', before: 'Active', after: 'Inactive' },
    { field: 'preferred_flag', label: 'Preferred supplier', before: 'Off', after: 'On' },
  ])
})

test('limits verbose audit records', () => {
  const changes = auditChanges(
    { currency_code: 'USD', locale: 'en-US', timezone: 'UTC', fiscal_year_start_month: 1, date_format: 'short' },
    { currency_code: 'CAD', locale: 'en-CA', timezone: 'America/Toronto', fiscal_year_start_month: 4, date_format: 'long' },
    2,
  )
  assert.equal(changes.length, 2)
})

test('formats instants in the workspace timezone and falls back safely', () => {
  assert.match(formatAuditTimestamp('2026-08-08T17:02:00Z', 'America/Chicago'), /Aug 8, 2026.*12:02 PM CDT/)
  assert.match(formatAuditTimestamp('2026-08-08T17:02:00Z', 'Invalid/Zone'), /Aug 8, 2026.*5:02 PM UTC/)
  assert.equal(formatAuditTimestamp('not-a-date'), '—')
})
