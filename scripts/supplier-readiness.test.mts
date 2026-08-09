import assert from 'node:assert/strict'
import test from 'node:test'
import { assessSupplierReadiness, dateKeyInTimeZone, matchesSupplierReadinessFilter } from '../lib/supplier-readiness.ts'

test('derives a stable ISO date key in the workspace timezone', () => {
  const instant = new Date('2026-08-09T02:00:00Z')
  assert.equal(dateKeyInTimeZone(instant, 'America/Chicago'), '2026-08-08')
  assert.equal(dateKeyInTimeZone(instant, 'UTC'), '2026-08-09')
  assert.equal(dateKeyInTimeZone(instant, 'Invalid/Zone'), '2026-08-09')
})

test('reports the three setup gaps independently', () => {
  assert.deepEqual(
    assessSupplierReadiness({ relationshipOwner: null, nextReviewDate: null, risk: null }, '2026-08-08'),
    {
      alerts: [],
      gaps: ['Missing owner', 'Missing review date', 'Unrated risk'],
      label: 'Missing owner; Missing review date; Unrated risk',
      priority: 1.7,
      state: 'incomplete',
    },
  )
})

test('flags high risk ahead of setup gaps', () => {
  const result = assessSupplierReadiness({ relationshipOwner: null, nextReviewDate: null, risk: 'High' }, '2026-08-08')
  assert.equal(result.state, 'attention')
  assert.equal(result.priority, 0)
  assert.deepEqual(result.alerts, ['High risk'])
  assert.deepEqual(result.gaps, ['Missing owner', 'Missing review date'])
  assert.equal(matchesSupplierReadinessFilter(result, 'Needs attention'), true)
  assert.equal(matchesSupplierReadinessFilter(result, 'Setup incomplete'), true)
  assert.equal(matchesSupplierReadinessFilter(result, 'Ready'), false)
})

test('treats a past review date as overdue but today as current', () => {
  const base = { relationshipOwner: 'Joe Torres', risk: 'Low' }
  assert.deepEqual(
    assessSupplierReadiness({ ...base, nextReviewDate: '2026-08-07' }, '2026-08-08').alerts,
    ['Review overdue'],
  )
  assert.equal(
    assessSupplierReadiness({ ...base, nextReviewDate: '2026-08-08' }, '2026-08-08').state,
    'ready',
  )
})

test('marks a governed relationship ready', () => {
  const result = assessSupplierReadiness({ relationshipOwner: 'Joe Torres', nextReviewDate: '2026-09-01', risk: 'Medium' }, '2026-08-08')
  assert.deepEqual(
    result,
    { alerts: [], gaps: [], label: 'Ready', priority: 3, state: 'ready' },
  )
  assert.equal(matchesSupplierReadinessFilter(result, 'Ready'), true)
  assert.equal(matchesSupplierReadinessFilter(result, 'Setup incomplete'), false)
})
