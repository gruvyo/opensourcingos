import { createClient } from '@/lib/supabase/server'
import { ReportsView } from '@/components/reports-view'

function getFirst(obj: any): any {
  if (!obj) return null
  if (Array.isArray(obj)) return obj[0] || null
  return obj
}

export default async function ReportsPage() {
  const supabase = await createClient()

  const [
    { data: events },
    { data: savingsCalcs },
  ] = await Promise.all([
    supabase.from('sourcing_events').select(`
      id, event_name, event_type, event_status, project_type, buyer_name,
      event_start_date, event_close_date, contract_start_date, contract_end_date,
      category:categories(category_name),
      business_unit:business_units(business_unit_name),
      incumbent_supplier:suppliers!sourcing_events_incumbent_supplier_id_fkey(supplier_name),
      awarded_supplier:suppliers!sourcing_events_awarded_supplier_id_fkey(supplier_name)
    `).order('created_at', { ascending: false }),
    supabase.from('savings_calculations').select(`
      id, calculation_name, savings_type, gross_savings_amount, savings_percentage,
      calculation_status, finance_validated, current_year_recognized_amount,
      cost_reduction_amount, cost_avoidance_amount, net_savings_amount, event_id,
      event:sourcing_events(event_name, contract_start_date),
      baseline:baselines(baseline_name),
      award:awards(award_name)
    `).order('created_at', { ascending: false }),
  ])

  // Build event map for savings lookups
  const eventMap = new Map<string, any>()
  for (const e of events || []) {
    eventMap.set(e.id, e)
  }

  // Enrich savings calcs with contract_start_date from event
  const enrichedCalcs = (savingsCalcs || []).map((c: any) => {
    const event = eventMap.get(c.event_id)
    return { ...c, contract_start_date: event?.contract_start_date || null }
  })

  return (
    <div className="p-8">
      <h1 className="text-2xl font-bold text-gray-900 dark:text-gray-100">Reports</h1>
      <p className="mt-1 text-sm text-gray-600 dark:text-gray-400">
        Procurement activity report — pipeline, savings, and project throughput
      </p>
      <ReportsView events={events || []} savingsCalcs={enrichedCalcs} />
    </div>
  )
}