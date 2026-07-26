import { createClient } from '@/lib/supabase/server'
import { DashboardStats } from '@/components/dashboard-stats'
import { SavingsByCategoryChart, EventsByStatusChart, SavingsByTypeChart, SavingsByYearChart } from '@/components/dashboard-charts'
import { portfolioRollup } from '@/lib/savings'
import { formatCurrency } from '@/lib/utils'
import { Card } from '@/components/ui/card'
import Link from 'next/link'

// Statuses that mean a project is no longer active. Centralized so "active
// count" and any future filter agree. (Was an inline literal before.)
const INACTIVE_STATUSES = ['Closed', 'Cancelled', 'Rejected', 'Complete']

function categoryName(event: any): string {
  const c = event?.category
  const first = Array.isArray(c) ? c[0] : c
  return first?.category_name || 'Uncategorized'
}

export default async function DashboardPage() {
  const supabase = await createClient()

  const [
    { data: events },
    { data: savingsCalcs },
  ] = await Promise.all([
    supabase.from('sourcing_events').select(`
      id, event_name, event_status, project_type, contract_start_date,
      category:categories!sourcing_events_category_id_fkey(category_name),
      business_unit:business_units(business_unit_name)
    `),
    supabase.from('savings_calculations').select(`
      id, savings_type, gross_savings_amount,
      cost_reduction_amount, cost_avoidance_amount,
      savings_start_date, savings_end_date, event_id
    `),
  ])

  const eventList = events || []

  // ALL savings figures come from the single source of truth (lib/savings).
  const rollup = portfolioRollup(savingsCalcs || [], eventList as any, { topCategories: 8 })

  // Active project count (project lifecycle, not a savings figure).
  const activeEvents = eventList.filter((e: any) => !INACTIVE_STATUSES.includes(e.event_status)).length

  // Events by Status — a count of projects, not money.
  const statusMap = new Map<string, number>()
  for (const event of eventList) {
    const s = (event as any).event_status
    statusMap.set(s, (statusMap.get(s) || 0) + 1)
  }
  const eventsByStatus = Array.from(statusMap.entries()).map(([name, value]) => ({ name, value }))

  return (
    <div className="p-8">
      <div className="mb-6">
        <h1 className="text-2xl font-bold text-gray-900 dark:text-gray-100">Dashboard</h1>
        <p className="mt-1 text-sm text-gray-600 dark:text-gray-400">
          Procurement value overview — savings, pipeline, and project activity
        </p>
      </div>

      <DashboardStats stats={{
        totalSavings: rollup.totalSavings,
        activeEvents,
        totalCostReduction: rollup.totalCostReduction,
        totalCostAvoidance: rollup.totalCostAvoidance,
      }} />

      {/* Savings by Year — full width */}
      <div className="mt-6">
        <SavingsByYearChart data={rollup.byYear} />
        {rollup.unscheduled > 0 && (
          <p className="mt-2 text-xs text-gray-500 dark:text-gray-400">
            {formatCurrency(rollup.unscheduled)} of savings isn&apos;t shown in the yearly view because
            those calculations have no savings-period dates set.
          </p>
        )}
      </div>

      <div className="mt-6 grid grid-cols-1 gap-6 lg:grid-cols-2">
        <SavingsByCategoryChart data={rollup.byCategory} />
        <EventsByStatusChart data={eventsByStatus} />
        <SavingsByTypeChart data={rollup.byType} />
      </div>

      <Card className="mt-6 p-6">
        <div className="mb-4 flex items-center justify-between">
          <h3 className="text-sm font-semibold uppercase tracking-wider text-[var(--text-3)]">Recent Projects</h3>
          <Link href="/events" className="text-sm font-medium text-[var(--brand-ink)] hover:underline">
            View all →
          </Link>
        </div>
        <div className="space-y-2">
          {eventList.slice(0, 5).map((event: any) => (
            <Link key={event.id} href={`/events/${event.id}`}
              className="flex items-center justify-between rounded-lg border border-[var(--border)] px-4 py-3 transition-colors hover:bg-[var(--surface-2)]">
              <div>
                <p className="text-sm font-medium text-[var(--text)]">{event.event_name}</p>
                <p className="text-xs text-[var(--text-3)]">{categoryName(event)}</p>
              </div>
              <span className="text-xs text-[var(--text-3)]">{event.event_status}</span>
            </Link>
          ))}
        </div>
      </Card>
    </div>
  )
}
