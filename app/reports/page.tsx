import { createClient } from '@/lib/supabase/server'
import { fetchPortfolioRows } from '@/lib/supabase/portfolio-query'
import { ReportsView } from '@/components/reports-view'

export default async function ReportsPage() {
  const supabase = await createClient()

  const [
    { data: events, error: eventsError },
    { data: savingsCalcs, error: savingsCalcsError },
  ] = await Promise.all([
    fetchPortfolioRows('Projects', (from, to) => (
      supabase.from('sourcing_events').select(`
        id, event_name, event_type, event_status, project_type, buyer_name,
        event_start_date, project_due_date, event_close_date, contract_start_date, contract_end_date,
        category:categories(category_name),
        business_unit:business_units(business_unit_name),
        incumbent_supplier:suppliers!sourcing_events_incumbent_supplier_id_fkey(supplier_name),
        awarded_supplier:suppliers!sourcing_events_awarded_supplier_id_fkey(supplier_name)
      `, { count: 'exact' })
        .order('created_at', { ascending: false })
        .order('id', { ascending: false })
        .range(from, to)
    )),
    fetchPortfolioRows('Savings calculations', (from, to) => (
      supabase.from('savings_calculations').select(`
        id, event_id, gross_savings_amount, cost_reduction_amount, cost_avoidance_amount
      `, { count: 'exact' })
        .order('created_at', { ascending: false })
        .order('id', { ascending: false })
        .range(from, to)
    )),
  ])

  // A failed query here would render as an empty report, which is indistinguishable
  // from a genuinely empty portfolio. Say which one it is.
  const loadError = eventsError?.message || savingsCalcsError?.message || null

  return (
    <div className="mx-auto w-full max-w-[1600px] p-4 sm:p-6 lg:p-8">
      <p className="text-xs font-semibold uppercase tracking-[0.18em] text-[var(--brand-ink)]">
        Portfolio intelligence
      </p>
      <h1 className="mt-1 text-2xl font-bold tracking-tight text-[var(--text)] sm:text-3xl">Reports</h1>
      <p className="mt-1 text-sm text-[var(--text-2)]">
        Choose a report, narrow the portfolio, and export the exact rows on screen.
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
