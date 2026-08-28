import assert from 'node:assert/strict'
import test from 'node:test'
import { deriveRealization, reductionFromActualSpend } from '../lib/realization.ts'
import { realizationRollup } from '../lib/savings/index.ts'

test('compares realized reduction only with executed reduction', () => {
  const result = deriveRealization({
    projectedReduction: 100,
    projectedAvoidance: 50,
    realizedReduction: 80,
    realizedAvoidance: 50,
  })

  assert.deepEqual(result, {
    projectedTotal: 150,
    realizedTotal: 130,
    reductionLeakage: 20,
    status: 'Partially Realized',
  })
})

test('avoidance shortfall is progress, never leakage', () => {
  const result = deriveRealization({
    projectedReduction: 100,
    projectedAvoidance: 50,
    realizedReduction: 100,
    realizedAvoidance: 0,
  })

  assert.equal(result.reductionLeakage, 0)
  assert.equal(result.status, 'Partially Realized')
})

test('a missing expected leg remains in progress rather than becoming leakage', () => {
  const result = deriveRealization({
    projectedReduction: 100,
    projectedAvoidance: 50,
    realizedReduction: 100,
    realizedAvoidance: null,
  })

  assert.equal(result.realizedTotal, 100)
  assert.equal(result.reductionLeakage, 0)
  assert.equal(result.status, 'In Progress')
})

test('actual spend derives only the reduction leg', () => {
  assert.equal(reductionFromActualSpend(500, 425, 100), 75)
  assert.equal(reductionFromActualSpend(500, 425, null), null)
})

test('both fully achieved legs produce one additive realized total', () => {
  const result = deriveRealization({
    projectedReduction: 100,
    projectedAvoidance: 50,
    realizedReduction: 105,
    realizedAvoidance: 50,
  })

  assert.equal(result.realizedTotal, 155)
  assert.equal(result.reductionLeakage, 0)
  assert.equal(result.status, 'Realized')
})

test('portfolio realization consumers aggregate the per-leg source of truth', () => {
  const rollup = realizationRollup([{
    projected_savings: 999,
    projected_reduction_amount: 100,
    projected_avoidance_amount: 50,
    realized_savings: 999,
    realized_reduction_amount: 80,
    realized_avoidance_amount: 50,
    leakage_amount: 20,
  }])

  assert.equal(rollup.totalProjected, 150)
  assert.equal(rollup.totalRealized, 130)
  assert.equal(rollup.totalLeakage, 20)
  assert.equal(rollup.realizationRate, (130 / 150) * 100)
})
