import assert from 'node:assert/strict'
import test from 'node:test'
import {
  addReportSavingsCalculation,
  emptyReportSavingsTotals,
  mergeReportSavingsTotals,
  reductionCoverage,
  reportReductionExport,
  reportReductionValue,
} from '../lib/report-savings.ts'

test('an all-null reduction population remains not applicable', () => {
  const totals = addReportSavingsCalculation(emptyReportSavingsTotals(), {
    calculation_status: 'estimated',
    cost_reduction_amount: null,
    cost_avoidance_amount: 25,
    gross_savings_amount: 25,
  })

  assert.equal(reductionCoverage(totals), 'none')
  assert.equal(reportReductionValue(totals), null)
  assert.equal(reportReductionExport(reportReductionValue(totals), reductionCoverage(totals)), 'n/a')
})

test('mixed groups report the known reduction subtotal as partial', () => {
  const known = addReportSavingsCalculation(emptyReportSavingsTotals(), {
    calculation_status: 'executed',
    cost_reduction_amount: 40,
    cost_avoidance_amount: 10,
    gross_savings_amount: 50,
  })
  const missing = addReportSavingsCalculation(emptyReportSavingsTotals(), {
    calculation_status: 'estimated',
    cost_reduction_amount: null,
    cost_avoidance_amount: 30,
    gross_savings_amount: 30,
  })
  const totals = mergeReportSavingsTotals(known, missing)

  assert.equal(reductionCoverage(totals), 'partial')
  assert.equal(reportReductionValue(totals), 40)
  assert.equal(reportReductionExport(reportReductionValue(totals), reductionCoverage(totals)), '40.00 (partial)')
  assert.deepEqual(
    { avoidance: totals.avoidance, total: totals.total, estimated: totals.estimated, executed: totals.executed },
    { avoidance: 40, total: 80, estimated: 30, executed: 50 },
  )
})

test('complete groups preserve exact negative reduction', () => {
  const totals = addReportSavingsCalculation(emptyReportSavingsTotals(), {
    calculation_status: 'executed',
    cost_reduction_amount: -12.5,
    cost_avoidance_amount: 20,
    gross_savings_amount: 7.5,
  })

  assert.equal(reductionCoverage(totals), 'complete')
  assert.equal(reportReductionValue(totals), -12.5)
  assert.equal(reportReductionExport(reportReductionValue(totals), reductionCoverage(totals)), '-12.50')
})

test('an event without any calculation remains a zero rather than n/a', () => {
  const totals = emptyReportSavingsTotals()
  assert.equal(reductionCoverage(totals), 'complete')
  assert.equal(reportReductionValue(totals), 0)
})
