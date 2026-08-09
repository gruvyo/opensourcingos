import assert from 'node:assert/strict'
import test from 'node:test'
import { supplierGovernanceSummaries } from '../lib/supplier-governance-report.ts'

test('uses the latest scored review without averaging historical scores', () => {
  const summaries = supplierGovernanceSummaries([
    { id: 'review-1', supplier_id: 'supplier-1', review_date: '2026-01-15', created_at: '2026-01-15T12:00:00Z', overall_score: 5, next_review_date: '2026-07-15' },
    { id: 'review-2', supplier_id: 'supplier-1', review_date: '2026-07-15', created_at: '2026-07-15T12:00:00Z', overall_score: 2, next_review_date: '2027-01-15' },
  ], [])

  assert.deepEqual(summaries.get('supplier-1'), {
    latestReviewDate: '2026-07-15',
    latestOverallScore: 2,
    performanceNextReviewDate: '2027-01-15',
    unresolvedRisks: 0,
    criticalRisks: 0,
    highRisks: 0,
    mediumRisks: 0,
    lowRisks: 0,
  })
})

test('counts unresolved risks by severity and excludes resolved issues', () => {
  const summaries = supplierGovernanceSummaries([], [
    { supplier_id: 'supplier-1', severity: 'Critical', risk_status: 'Open' },
    { supplier_id: 'supplier-1', severity: 'High', risk_status: 'Monitoring' },
    { supplier_id: 'supplier-1', severity: 'Medium', risk_status: 'Open' },
    { supplier_id: 'supplier-1', severity: 'Low', risk_status: 'Resolved' },
  ])

  const summary = summaries.get('supplier-1')
  assert.equal(summary?.unresolvedRisks, 3)
  assert.equal(summary?.criticalRisks, 1)
  assert.equal(summary?.highRisks, 1)
  assert.equal(summary?.mediumRisks, 1)
  assert.equal(summary?.lowRisks, 0)
})

test('keeps suppliers absent until they have review or risk activity', () => {
  const summaries = supplierGovernanceSummaries([], [])
  assert.equal(summaries.size, 0)
})
