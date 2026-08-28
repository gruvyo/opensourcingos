import type { SupabaseClient } from '@supabase/supabase-js'
import type { Database, Json } from '@/lib/database.types'

type Client = SupabaseClient<Database>

export type SchedulePeriodWrite = {
  period_number: number
  period_month: number
  period_year: number
  period_months: number
  baseline_amount: number | null
  opening_amount: number | null
  final_amount: number
  cost_reduction_amount: number | null
  cost_avoidance_amount: number
  total_savings_amount: number
  is_edited: boolean
  notes?: string | null
}

export function completeSourcingProjectAtomically(
  client: Client,
  eventId: string,
  disposition: 'executed' | 'no_executed_savings',
  reason?: string,
) {
  return client.rpc('complete_sourcing_project', reason === undefined
    ? { p_event_id: eventId, p_disposition: disposition }
    : { p_event_id: eventId, p_disposition: disposition, p_reason: reason })
}

export function selectBaselineAtomically(client: Client, baselineId: string) {
  return client.rpc('select_baseline', { p_baseline_id: baselineId })
}

export function setOfferRoleAtomically(
  client: Client,
  offerId: string,
  role: 'opening' | 'final' | null,
) {
  return client.rpc('set_offer_role', role === null
    ? { p_offer_id: offerId }
    : { p_offer_id: offerId, p_role: role })
}

export function replaceSavingsScheduleAtomically(
  client: Client,
  calculationId: string,
  startMonth: number,
  startYear: number,
  periodType: 'monthly' | 'annual' | 'one_time',
  periods: SchedulePeriodWrite[],
) {
  return client.rpc('replace_savings_schedule', {
    p_savings_calculation_id: calculationId,
    p_schedule_start_month: startMonth,
    p_schedule_start_year: startYear,
    p_schedule_period_type: periodType,
    p_periods: periods as Json,
  })
}

export function syncRealizationPeriodsAtomically(client: Client, eventId: string) {
  return client.rpc('sync_realization_periods', { p_event_id: eventId })
}
