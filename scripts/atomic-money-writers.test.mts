import assert from 'node:assert/strict'
import test from 'node:test'
import {
  addBaselineLineAtomically,
  completeSourcingProjectAtomically,
  deleteBaselineLineAtomically,
  replaceSavingsScheduleAtomically,
  selectBaselineAtomically,
  setOfferRoleAtomically,
  syncRealizationPeriodsAtomically,
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

test('project completion sends only lifecycle intent to the guarded RPC', async () => {
  const { client, calls } = recordingClient()
  await completeSourcingProjectAtomically(client, 'event-1', 'executed')
  await completeSourcingProjectAtomically(
    client, 'event-2', 'no_executed_savings', 'No commercial result was executed.',
  )
  assert.deepEqual(calls, [
    {
      name: 'complete_sourcing_project',
      args: { p_event_id: 'event-1', p_disposition: 'executed' },
    },
    {
      name: 'complete_sourcing_project',
      args: {
        p_event_id: 'event-2',
        p_disposition: 'no_executed_savings',
        p_reason: 'No commercial result was executed.',
      },
    },
  ])
  assert.equal(JSON.stringify(calls).includes('actor'), false)
  assert.equal(JSON.stringify(calls).includes('organization_id'), false)
})

test('baseline selection uses the single reviewed RPC and sends no actor or workspace', async () => {
  const { client, calls } = recordingClient()
  await selectBaselineAtomically(client, 'baseline-1')
  assert.deepEqual(calls, [{
    name: 'select_baseline',
    args: { p_baseline_id: 'baseline-1' },
  }])
})

test('baseline line mutations send values only through the two atomic APIs', async () => {
  const { client, calls } = recordingClient()
  const line = {
    scope_line_id: null,
    baseline_unit_price: 25,
    baseline_quantity: 4,
    baseline_extended_amount: 100,
    baseline_recurring_amount: 100,
    baseline_one_time_amount: 0,
    baseline_term_months: 12,
    annualized_baseline_amount: 100,
    normalized_quantity: 4,
    normalized_unit_price: 25,
    normalized_extended_amount: 100,
  }
  await addBaselineLineAtomically(client, 'baseline-1', line)
  await deleteBaselineLineAtomically(client, 'line-1')
  assert.deepEqual(calls, [
    {
      name: 'add_baseline_line',
      args: { p_baseline_id: 'baseline-1', p_line: line },
    },
    {
      name: 'delete_baseline_line',
      args: { p_baseline_line_id: 'line-1' },
    },
  ])
  assert.equal(JSON.stringify(calls).includes('organization_id'), false)
  assert.equal(JSON.stringify(calls).includes('created_by'), false)
  assert.equal(JSON.stringify(calls).includes('updated_by'), false)
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

test('realization sync sends only the project ID to the guarded RPC', async () => {
  const { client, calls } = recordingClient()
  await syncRealizationPeriodsAtomically(client, 'event-1')
  assert.deepEqual(calls, [{
    name: 'sync_realization_periods',
    args: { p_event_id: 'event-1' },
  }])
  assert.equal(JSON.stringify(calls).includes('organization_id'), false)
  assert.equal(JSON.stringify(calls).includes('savings_period_id'), false)
  assert.equal(JSON.stringify(calls).includes('created_by'), false)
})
