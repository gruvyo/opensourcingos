import { createClient } from '@/lib/supabase/server'
import { ReportsView } from '@/components/reports-view'

export default async function ReportsPage() {
  const supabase = await createClient()

  const [
    { data: events, error: eventsError },
    { data: savingsCalcs, error: savingsCalcsError },
  ] = await Promise.all([
    supabase.from('sourcing_events').select(`
      id, event_name, event_type, event_status, project_type, buyer_name,
      event_start_date, project_due_date, event_close_date, contract_start_date, contract_end_date,
      category:categories(category_name),
      business_unit:business_units(business_unit_name),
      incumbent_supplier:suppliers!sourcing_events_incumbent_supplier_id_fkey(supplier_name),
      awarded_supplier:suppliers!sourcing_events_awarded_supplier_id_fkey(supplier_name)
    `).order('created_at', { ascending: false }),
    supabase.from('savings_calculations').select(`
      id, calculation_name, savings_type, gross_savings_amount, savings_percentage,
      calculation_status, cost_reduction_amount, cost_avoidance_amount, net_savings_amount,
      savings_start_date, savings_end_date, event_id,
      event:sourcing_events(event_name, contract_start_date),
      baseline:baselines(baseline_name, baseline_type, hard_reduction_override,
                         hard_reduction_override_reason),
      award:awards(award_name)
    `).order('created_at', { ascending: false }),
  ])

  // A failed query here would render as an empty report, which is indistinguishable
  // from a genuinely empty portfolio. Say which one it is.
  const loadError = eventsError?.message || savingsCalcsError?.message || null

  return (
    <div className="p-8">
      <h1 className="text-2xl font-bold text-gray-900 dark:text-gray-100">Reports</h1>
      <p className="mt-1 text-sm text-gray-600 dark:text-gray-400">
        Procurement activity report — pipeline, savings, and project throughput
      </p>

      {loadError && (
        <div className="mt-6 rounded-lg bg-red-50 p-4 text-sm text-red-700 dark:bg-red-900/30 dark:text-red-300" role="alert">
          <strong>These figures are incomplete.</strong> A query failed: {loadError}. Do not report
          from this page until it loads cleanly.
        </div>
      )}

      <ReportsView events={events || []} savingsCalcs={savingsCalcs || []} />
    </div>
  )
}
