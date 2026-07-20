import { createClient } from '@/lib/supabase/server'
import { ReportsView } from '@/components/reports-view'

export default async function ReportsPage() {
  const supabase = await createClient()

  const { data: events } = await supabase
    .from('sourcing_events')
    .select(`
      id, event_name, event_type, event_status,
      category:categories(category_name),
      business_unit:business_units(business_unit_name),
      incumbent_supplier:suppliers!sourcing_events_incumbent_supplier_id_fkey(supplier_name),
      awarded_supplier:suppliers!sourcing_events_awarded_supplier_id_fkey(supplier_name),
      contract_start_date, contract_end_date
    `)
    .order('created_at', { ascending: false })

  const { data: savingsCalcs } = await supabase
    .from('savings_calculations')
    .select(`
      id, calculation_name, savings_type, gross_savings_amount, savings_percentage,
      calculation_status, finance_validated, current_year_recognized_amount,
      event:sourcing_events(event_name),
      baseline:baselines(baseline_name),
      award:awards(award_name)
    `)
    .order('created_at', { ascending: false })

  return (
    <div className="p-8">
      <h1 className="text-2xl font-bold text-gray-900">Reports</h1>
      <p className="mt-1 text-sm text-gray-600">Export procurement data to CSV</p>
      <ReportsView events={events || []} savingsCalcs={savingsCalcs || []} />
    </div>
  )
}
