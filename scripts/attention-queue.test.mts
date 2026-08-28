import assert from 'node:assert/strict'
import test from 'node:test'
import { buildAttentionQueue } from '../lib/attention-queue.ts'

const terminalStatuses = [
  { label: 'Complete', project_type: 'Sourcing', is_terminal: true },
  { label: 'Cancelled', project_type: 'Sourcing', is_terminal: true },
]

test('separates overdue and upcoming active project deadlines', () => {
  const queue = buildAttentionQueue([
    { id: 'late', name: 'Late project', status: 'In Market', projectType: 'Sourcing', dueDate: '2026-08-07' },
    { id: 'today', name: 'Today project', status: 'Negotiation', projectType: 'Sourcing', dueDate: '2026-08-08' },
    { id: 'soon', name: 'Soon project', status: 'Pipeline', projectType: 'Sourcing', dueDate: '2026-09-07' },
    { id: 'later', name: 'Later project', status: 'Pipeline', projectType: 'Sourcing', dueDate: '2026-09-08' },
    { id: 'done', name: 'Done project', status: 'Complete', projectType: 'Sourcing', dueDate: '2026-08-01' },
  ], [], '2026-08-08', terminalStatuses)

  assert.equal(queue.overdueProjects, 1)
  assert.equal(queue.dueSoonProjects, 2)
  assert.deepEqual(queue.items.map(item => item.id), ['project:late', 'project:today', 'project:soon'])
  assert.deepEqual(queue.items[1].reasons, ['Due today'])
})

test('combines supplier alerts into one actionable row', () => {
  const queue = buildAttentionQueue([], [
    { id: 'both', name: 'High and late', status: 'Active', risk: 'High', nextReviewDate: '2026-08-01' },
    { id: 'late', name: 'Review late', status: 'Active', risk: 'Low', nextReviewDate: '2026-08-02' },
    { id: 'setup', name: 'Missing setup', status: 'Active', risk: null, nextReviewDate: null },
    { id: 'inactive', name: 'Inactive risk', status: 'Inactive', risk: 'High', nextReviewDate: null },
  ], '2026-08-08')

  assert.equal(queue.supplierAttention, 2)
  assert.deepEqual(queue.items[0].reasons, ['High risk', 'Relationship review overdue'])
  assert.equal(queue.items.some(item => item.title === 'Missing setup'), false)
  assert.equal(queue.items.some(item => item.title === 'Inactive risk'), false)
})

test('keeps relationship and performance review plans distinct', () => {
  const queue = buildAttentionQueue([], [
    {
      id: 'reviews',
      name: 'Two review plans',
      status: 'Active',
      risk: 'Low',
      nextReviewDate: '2026-08-02',
      performanceNextReviewDate: '2026-08-01',
    },
  ], '2026-08-08')

  assert.equal(queue.supplierAttention, 1)
  assert.deepEqual(queue.items[0].reasons, [
    'Relationship review overdue',
    'Performance review overdue',
  ])
  assert.equal(queue.items[0].date, '2026-08-01')
})

test('sorts overdue projects before supplier alerts and upcoming deadlines', () => {
  const queue = buildAttentionQueue(
    [
      { id: 'soon', name: 'Soon', status: 'Pipeline', projectType: 'Sourcing', dueDate: '2026-08-10' },
      { id: 'late', name: 'Late', status: 'Pipeline', projectType: 'Sourcing', dueDate: '2026-08-01' },
    ],
    [{ id: 'risk', name: 'Risk', status: 'Active', risk: 'High', nextReviewDate: null }],
    '2026-08-08',
  )

  assert.deepEqual(queue.items.map(item => item.id), ['project:late', 'supplier:risk', 'project:soon'])
})

test('surfaces unresolved structured risk issues without changing the relationship rating', () => {
  const queue = buildAttentionQueue([], [
    {
      id: 'structured',
      name: 'Structured risk supplier',
      status: 'Active',
      risk: 'Low',
      nextReviewDate: null,
      criticalRiskIssues: 1,
      highRiskIssues: 2,
    },
  ], '2026-08-08')

  assert.equal(queue.supplierAttention, 1)
  assert.deepEqual(queue.items[0].reasons, [
    '1 unresolved critical risk issue',
    '2 unresolved high risk issues',
  ])
  assert.equal(queue.items[0].priority, 0.5)
})
