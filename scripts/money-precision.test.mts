import test from 'node:test'
import assert from 'node:assert/strict'
import {
  allocateMoney,
  fixedMoney,
  hasCentPrecision,
  moneyInputChanged,
  moneyToCents,
  roundMoney,
} from '../lib/money.ts'
import { generateSchedule, scheduleTotals } from '../lib/savings/index.ts'

test('money rounding matches PostgreSQL numeric half-away-from-zero behavior', () => {
  assert.equal(roundMoney(1.005), 1.01)
  assert.equal(roundMoney(-1.005), -1.01)
  assert.equal(moneyToCents(999_999.995), 100_000_000)
  assert.equal(fixedMoney(12), '12.00')
})

test('unchanged realization inputs do not issue destructive blur writes', () => {
  assert.equal(moneyInputChanged('', null), false)
  assert.equal(moneyInputChanged('100.00', 100), false)
  assert.equal(moneyInputChanged('100', 100), false)
  assert.equal(moneyInputChanged('', 100), true)
  assert.equal(moneyInputChanged('0', null), true)
  assert.equal(moneyInputChanged('not-money', null), true)
})

test('deterministic residual allocation preserves the exact cent total', () => {
  const raw = Array.from({ length: 7 }, () => 100 / 7)
  const allocated = allocateMoney(raw)

  assert.deepEqual(allocated.slice(0, 6), Array(6).fill(14.29))
  assert.equal(allocated[6], 14.26)
  assert.equal(allocated.reduce<number>((sum, value) => sum + moneyToCents(value ?? 0), 0), 10_000)
  assert.ok(allocated.every(value => value !== null && hasCentPrecision(value)))
})

test('allocation preserves null anchors and uses the requested residual row', () => {
  const allocated = allocateMoney([null, 10 / 3, 10 / 3, 10 / 3], { target: 10, sinkIndex: 2 })
  assert.deepEqual(allocated, [null, 3.33, 3.34, 3.33])
})

test('generated schedules store cents and reconcile every anchor and savings leg', () => {
  const rows = generateSchedule({
    startMonth: 1,
    startYear: 2027,
    periodType: 'monthly',
    periodCount: 7,
    dealMonths: 7,
  }, {
    baselinePerMonth: 100 / 7,
    openingPerMonth: 130 / 7,
    finalPerMonth: 80 / 7,
  })
  const totals = scheduleTotals(rows)

  assert.deepEqual(totals, {
    baseline: 100,
    opening: 130,
    final: 80,
    reduction: 20,
    avoidance: 30,
    total: 50,
    periodCount: 7,
    months: 7,
  })
  for (const row of rows) {
    const values = [row.baseline, row.opening, row.final, row.reduction, row.avoidance, row.total]
    assert.ok(values.every(value => value === null || hasCentPrecision(value)))
    assert.equal(moneyToCents(row.total), moneyToCents((row.reduction ?? 0) + row.avoidance))
  }
})
