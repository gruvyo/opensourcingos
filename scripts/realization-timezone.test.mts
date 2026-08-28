import test from 'node:test'
import assert from 'node:assert/strict'
import { classifyRealization, portfolioRollup, type SavingsCalcRow } from '../lib/savings/index.ts'

const calculation: SavingsCalcRow = {
  id: 'calculation',
  event_id: 'event',
  savings_start_date: '2026-08-28',
  gross_savings_amount: 100,
  cost_reduction_amount: 100,
  cost_avoidance_amount: 0,
}
const contractDates = new Map([['event', '2026-08-28']])
const instant = new Date('2026-08-28T00:30:00.000Z')

test('classifies a date-only start against today in a negative-offset workspace', () => {
  assert.equal(classifyRealization(calculation, contractDates, instant, 'America/Los_Angeles'), 'Accrued')
})

test('classifies the same instant in a positive-offset workspace without a UTC day shift', () => {
  assert.equal(classifyRealization(calculation, contractDates, instant, 'Pacific/Kiritimati'), 'Realized')
})

test('portfolio rollups use the workspace timezone for realized and accrued totals', () => {
  const events = [{ id: 'event', contract_start_date: '2026-08-28' }]
  const west = portfolioRollup([calculation], events, { now: instant, timeZone: 'America/Los_Angeles' })
  const east = portfolioRollup([calculation], events, { now: instant, timeZone: 'Pacific/Kiritimati' })
  assert.deepEqual({ realized: west.realized, accrued: west.accrued }, { realized: 0, accrued: 100 })
  assert.deepEqual({ realized: east.realized, accrued: east.accrued }, { realized: 100, accrued: 0 })
})
