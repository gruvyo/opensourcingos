import assert from 'node:assert/strict'
import test from 'node:test'
import {
  replaceSavingsScheduleAtomically,
  selectBaselineAtomically,
  setOfferRoleAtomically,
} from '../lib/atomic-money-writers.ts'

function recordingClient() {
  const calls: Array<{ name: string; args: Record<string, unknown> }> = []
  return {
    calls,
    client: {
      rpc: async (name: string, args: Record<string, unknown>) => {
        calls.push({ name, args })
        return { data: null, error: null }
      },
    } as never,
  }
}

test('baseline selection uses the single reviewed RPC and sends no actor or workspace', async () => {
  const { client, calls } = recordingClient()
  await selectBaselineAtomically(client, 'baseline-1')
  assert.deepEqual(calls, [{
    name: 'select_baseline',
    args: { p_baseline_id: 'baseline-1' },
  }])
})

test('offer role changes use the single reviewed RPC, including an explicit unset', async () => {
  const { client, calls } = recordingClient()
  await setOfferRoleAtomically(client, 'offer-1', 'final')
  await setOfferRoleAtomically(client, 'offer-1', null)
  assert.deepEqual(calls, [
    { name: 'set_offer_role', args: { p_offer_id: 'offer-1', p_role: 'final' } },
    { name: 'set_offer_role', args: { p_offer_id: 'offer-1' } },
  ])
})

test('schedule replacement sends only calculation settings and period values', async () => {
  const { client, calls } = recordingClient()
  const periods = [{
    period_number: 1,
    period_month: 8,
    period_year: 2026,
    period_months: 1,
    baseline_amount: 100,
    opening_amount: 120,
    final_amount: 90,
    cost_reduction_amount: 10,
    cost_avoidance_amount: 20,
    total_savings_amount: 30,
    is_edited: false,
  }]
  await replaceSavingsScheduleAtomically(
    client, 'calculation-1', 8, 2026, 'monthly', periods,
  )
  assert.deepEqual(calls, [{
    name: 'replace_savings_schedule',
    args: {
      p_savings_calculation_id: 'calculation-1',
      p_schedule_start_month: 8,
      p_schedule_start_year: 2026,
      p_schedule_period_type: 'monthly',
      p_periods: periods,
    },
  }])
  assert.equal(JSON.stringify(calls).includes('organization_id'), false)
  assert.equal(JSON.stringify(calls).includes('created_by'), false)
  assert.equal(JSON.stringify(calls).includes('updated_by'), false)
})
