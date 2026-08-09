import assert from 'node:assert/strict'
import test from 'node:test'
import { buildAttentionQueue } from '../lib/attention-queue.ts'

test('separates overdue and upcoming active project deadlines', () => {
  const queue = buildAttentionQueue([
    { id: 'late', name: 'Late project', status: 'In Market', dueDate: '2026-08-07' },
    { id: 'today', name: 'Today project', status: 'Negotiation', dueDate: '2026-08-08' },
    { id: 'soon', name: 'Soon project', status: 'Pipeline', dueDate: '2026-09-07' },
    { id: 'later', name: 'Later project', status: 'Pipeline', dueDate: '2026-09-08' },
    { id: 'done', name: 'Done project', status: 'Complete', dueDate: '2026-08-01' },
  ], [], '2026-08-08')

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
  assert.deepEqual(queue.items[0].reasons, ['High risk', 'Review overdue'])
  assert.equal(queue.items.some(item => item.title === 'Missing setup'), false)
  assert.equal(queue.items.some(item => item.title === 'Inactive risk'), false)
})

test('sorts overdue projects before supplier alerts and upcoming deadlines', () => {
  const queue = buildAttentionQueue(
    [
      { id: 'soon', name: 'Soon', status: 'Pipeline', dueDate: '2026-08-10' },
      { id: 'late', name: 'Late', status: 'Pipeline', dueDate: '2026-08-01' },
    ],
    [{ id: 'risk', name: 'Risk', status: 'Active', risk: 'High', nextReviewDate: null }],
    '2026-08-08',
  )

  assert.deepEqual(queue.items.map(item => item.id), ['project:late', 'supplier:risk', 'project:soon'])
})
