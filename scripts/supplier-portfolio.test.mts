import assert from 'node:assert/strict'
import test from 'node:test'
import { supplierAttributionTotals, supplierPortfolioValues } from '../lib/supplier-portfolio.ts'
import { calculationLoadError } from '../lib/calculation-integrity.ts'

test('attributes spend and savings to awarded suppliers without double counting shares', () => {
  const result = supplierPortfolioValues(
    [
      { id: 'event-a', awardedSupplierId: 'supplier-a' },
      { id: 'event-b', awardedSupplierId: 'supplier-b' },
      { id: 'event-c', awardedSupplierId: null },
    ],
    [
      { id: 'a', event_id: 'event-a', calculation_status: 'executed', baseline_total_amount: 800, gross_savings_amount: 200 },
      { id: 'b', event_id: 'event-b', calculation_status: 'estimated', baseline_total_amount: 200, gross_savings_amount: 50 },
      { id: 'c', event_id: 'event-c', calculation_status: 'executed', baseline_total_amount: 500, gross_savings_amount: 100 },
    ],
    [],
  )
  const values = result.values

  assert.equal(values.get('supplier-a')?.awards, 1)
  assert.equal(values.get('supplier-a')?.spendAddressed, 800)
  assert.equal(values.get('supplier-a')?.executedSavings, 200)
  assert.equal(values.get('supplier-a')?.estimatedSavings, 0)
  assert.equal(values.get('supplier-a')?.spendShare, 80)
  assert.equal(values.get('supplier-a')?.savingsShare, 80)
  assert.equal(values.has('supplier-c'), false)
  assert.equal(result.dataQuality.duplicateCalculationEvents, 0)
})

test('keeps estimated and executed savings separate for one supplier', () => {
  const result = supplierPortfolioValues(
    [
      { id: 'event-a', awardedSupplierId: 'supplier-a' },
      { id: 'event-b', awardedSupplierId: 'supplier-a' },
    ],
    [
      { id: 'estimated', event_id: 'event-a', calculation_status: 'estimated', baseline_total_amount: 100, gross_savings_amount: 10 },
      { id: 'executed', event_id: 'event-b', calculation_status: 'executed', baseline_total_amount: 200, gross_savings_amount: 20 },
    ],
    [],
  )
  const values = result.values

  assert.deepEqual(
    {
      spendAddressed: values.get('supplier-a')?.spendAddressed,
      estimated: values.get('supplier-a')?.estimatedSavings,
      executed: values.get('supplier-a')?.executedSavings,
      total: values.get('supplier-a')?.totalSavings,
    },
    { spendAddressed: 300, estimated: 10, executed: 20, total: 30 },
  )
  assert.equal(result.dataQuality.duplicateCalculationEvents, 0)
})

test('uses the earliest calculation once and reports malformed duplicate projects', () => {
  const result = supplierPortfolioValues(
    [{ id: 'event-a', awardedSupplierId: 'supplier-a' }],
    [
      { id: 'later', event_id: 'event-a', created_at: '2026-02-01T00:00:00Z', calculation_status: 'executed', baseline_total_amount: 200, gross_savings_amount: 20 },
      { id: 'earlier', event_id: 'event-a', created_at: '2026-01-01T00:00:00Z', calculation_status: 'estimated', baseline_total_amount: 100, gross_savings_amount: 10 },
    ],
    [],
  )

  assert.deepEqual(
    {
      spendAddressed: result.values.get('supplier-a')?.spendAddressed,
      estimated: result.values.get('supplier-a')?.estimatedSavings,
      executed: result.values.get('supplier-a')?.executedSavings,
      total: result.values.get('supplier-a')?.totalSavings,
      duplicateEvents: result.dataQuality.duplicateCalculationEvents,
    },
    { spendAddressed: 100, estimated: 10, executed: 0, total: 10, duplicateEvents: 1 },
  )
})

test('derives realization only from linked periods and returns no rate without a projected amount', () => {
  const withRealization = supplierPortfolioValues(
    [
      { id: 'event-a', awardedSupplierId: 'supplier-a' },
      { id: 'event-b', awardedSupplierId: 'supplier-b' },
    ],
    [],
    [
      { event_id: 'event-a', projected_savings: 100, realized_savings: 75 },
      { event_id: 'event-a', projected_savings: 100, realized_savings: 50 },
      { event_id: 'event-b', projected_savings: 0, realized_savings: 0 },
    ],
  )

  assert.equal(withRealization.values.get('supplier-a')?.realizedSavings, 125)
  assert.equal(withRealization.values.get('supplier-a')?.realizationRate, 62.5)
  assert.equal(withRealization.values.get('supplier-b')?.realizationRate, null)
})

test('turns a forced savings-record read failure into a save-blocking message', () => {
  const message = calculationLoadError([
    { label: 'baselines', error: null },
    { label: 'supplier offers', error: null },
    { label: 'savings record', error: { message: 'forced read failure' } },
  ])

  assert.match(message || '', /savings record: forced read failure/)
  assert.match(message || '', /Saving is disabled/)
})

test('does not attribute the winner savings to a losing incumbent profile', () => {
  const events = [
    { id: 'lost-deal', awardedSupplierId: 'winner' },
    { id: 'won-deal', awardedSupplierId: 'incumbent' },
  ]
  const calculations = [
    { id: 'lost', event_id: 'lost-deal', calculation_status: 'executed', gross_savings_amount: 900 },
    { id: 'won', event_id: 'won-deal', calculation_status: 'executed', gross_savings_amount: 125 },
  ]
  const realization = [
    { event_id: 'lost-deal', projected_savings: 900, realized_savings: 700 },
    { event_id: 'won-deal', projected_savings: 125, realized_savings: 100 },
  ]

  assert.deepEqual(
    supplierAttributionTotals('incumbent', events, calculations, realization),
    { negotiatedSavings: 125, realizedSavings: 100 },
  )
  assert.deepEqual(
    supplierAttributionTotals('winner', events, calculations, realization),
    { negotiatedSavings: 900, realizedSavings: 700 },
  )
})

test('supplier profile totals match the portfolio award attribution', () => {
  const events = [{ id: 'deal', awardedSupplierId: 'supplier-a' }]
  const calculations = [
    { id: 'calc', event_id: 'deal', calculation_status: 'estimated', gross_savings_amount: 42.25 },
  ]
  const realization = [{ event_id: 'deal', projected_savings: 42.25, realized_savings: 12.5 }]
  const portfolio = supplierPortfolioValues(events, calculations, realization)
    .values.get('supplier-a')

  assert.deepEqual(
    supplierAttributionTotals('supplier-a', events, calculations, realization),
    {
      negotiatedSavings: portfolio?.totalSavings,
      realizedSavings: portfolio?.realizedSavings,
    },
  )
})
