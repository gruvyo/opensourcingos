import assert from 'node:assert/strict'
import test from 'node:test'
import { supplierPortfolioSegments } from '../lib/supplier-segmentation.ts'
import type { SupplierPortfolioValue } from '../lib/supplier-portfolio.ts'

function value(supplierId: string, overrides: Partial<SupplierPortfolioValue>): SupplierPortfolioValue {
  return {
    supplierId,
    awards: 0,
    spendAddressed: 0,
    spendShare: null,
    estimatedSavings: 0,
    executedSavings: 0,
    totalSavings: 0,
    savingsShare: null,
    realizedSavings: 0,
    realizationRate: null,
    ...overrides,
  }
}

const suppliers = [
  { id: 'a', supplierStatus: 'Active', riskRating: 'Low', preferred: true, diverse: false },
  { id: 'b', supplierStatus: 'Active', riskRating: 'High', preferred: false, diverse: true },
  { id: 'c', supplierStatus: null, riskRating: null, preferred: false, diverse: false },
]

const values = new Map([
  ['a', value('a', { awards: 2, spendAddressed: 800, executedSavings: 100, totalSavings: 100 })],
  ['b', value('b', { awards: 1, spendAddressed: 200, estimatedSavings: 50, totalSavings: 50 })],
])

test('segments preferred and standard suppliers without double counting portfolio shares', () => {
  const segments = supplierPortfolioSegments(suppliers, values, 'Preferred status')

  assert.deepEqual(segments.map(segment => ({
    label: segment.label,
    suppliers: segment.suppliers,
    awardedSuppliers: segment.awardedSuppliers,
    awards: segment.awards,
    spendShare: segment.spendShare,
    savingsShare: segment.savingsShare,
  })), [
    { label: 'Preferred', suppliers: 1, awardedSuppliers: 1, awards: 2, spendShare: 80, savingsShare: (100 / 150) * 100 },
    { label: 'Standard', suppliers: 2, awardedSuppliers: 1, awards: 1, spendShare: 20, savingsShare: (50 / 150) * 100 },
  ])
})

test('uses explicit fallback labels for missing relationship data', () => {
  assert.deepEqual(
    supplierPortfolioSegments(suppliers, values, 'Relationship risk').map(segment => segment.label),
    ['Low', 'High', 'Unrated'],
  )
  assert.deepEqual(
    supplierPortfolioSegments(suppliers, values, 'Supplier status').map(segment => segment.label),
    ['Active'],
  )
})

test('returns null shares when a filtered portfolio has no value', () => {
  const segments = supplierPortfolioSegments([suppliers[2]], new Map(), 'Diversity')
  assert.equal(segments[0].spendShare, null)
  assert.equal(segments[0].savingsShare, null)
})
