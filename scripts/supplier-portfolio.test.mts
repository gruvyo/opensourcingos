import assert from 'node:assert/strict'
import test from 'node:test'
import { supplierPortfolioValues } from '../lib/supplier-portfolio.ts'

test('attributes spend and savings to awarded suppliers without double counting shares', () => {
  const values = supplierPortfolioValues(
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

  assert.equal(values.get('supplier-a')?.awards, 1)
  assert.equal(values.get('supplier-a')?.spendAddressed, 800)
  assert.equal(values.get('supplier-a')?.executedSavings, 200)
  assert.equal(values.get('supplier-a')?.estimatedSavings, 0)
  assert.equal(values.get('supplier-a')?.spendShare, 80)
  assert.equal(values.get('supplier-a')?.savingsShare, 80)
  assert.equal(values.has('supplier-c'), false)
})

test('keeps estimated and executed savings separate for one supplier', () => {
  const values = supplierPortfolioValues(
    [{ id: 'event-a', awardedSupplierId: 'supplier-a' }],
    [
      { id: 'estimated', event_id: 'event-a', calculation_status: 'estimated', baseline_total_amount: 100, gross_savings_amount: 10 },
      { id: 'executed', event_id: 'event-a', calculation_status: 'executed', baseline_total_amount: 200, gross_savings_amount: 20 },
    ],
    [],
  )

  assert.deepEqual(
    {
      estimated: values.get('supplier-a')?.estimatedSavings,
      executed: values.get('supplier-a')?.executedSavings,
      total: values.get('supplier-a')?.totalSavings,
    },
    { estimated: 10, executed: 20, total: 30 },
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

  assert.equal(withRealization.get('supplier-a')?.realizedSavings, 125)
  assert.equal(withRealization.get('supplier-a')?.realizationRate, 62.5)
  assert.equal(withRealization.get('supplier-b')?.realizationRate, null)
})
