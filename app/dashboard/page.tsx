import { createClient } from '@/lib/supabase/server'
import { DashboardStats } from '@/components/dashboard-stats'
import { SavingsByCategoryChart, EventsByStatusChart, SavingsByTypeChart, SavingsByYearChart } from '@/components/dashboard-charts'
import { FiscalYearPanel } from '@/components/fiscal-year-panel'
import {
  portfolioRollup, portfolioByYear, toSchedulePeriods,
  type SchedulePeriod,
} from '@/lib/savings'
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

export default async function DashboardPage({
  searchParams,
}: {
  searchParams: Promise<{ [key: string]: string | string[] | undefined }>
}) {
  const supabase = await createClient()

  // The fiscal year lives in the URL, so a filtered dashboard is a link
  // someone can paste into an email and land on the same figures.
  const fyParam = (await searchParams).fy
  const fyRaw = Array.isArray(fyParam) ? fyParam[0] : fyParam
  const selectedYear = fyRaw && /^\d{4}$/.test(fyRaw) ? Number(fyRaw) : null

  const [
    { data: events, error: eventsError },
    { data: savingsCalcs, error: calcsError },
    { data: periodRows, error: periodsError },
  ] = await Promise.all([
    supabase.from('sourcing_events').select(`
      id, event_name, event_status, project_type, contract_start_date,
      category:categories!sourcing_events_category_id_fkey(category_name),
      business_unit:business_units(business_unit_name)
    `),
    supabase.from('savings_calculations').select(`
      id, savings_type, gross_savings_amount,
      cost_reduction_amount, cost_avoidance_amount,
      savings_start_date, savings_end_date, event_id,
      calculation_status
    `),
    supabase.from('savings_periods').select(`
      savings_calculation_id, period_number, period_month, period_year, period_months,
      baseline_amount, opening_amount, final_amount,
      cost_reduction_amount, cost_avoidance_amount, total_savings_amount
    `).order('period_number', { ascending: true }),
  ])

  // A failed query here would render as "no savings", which is indistinguishable
  // from a genuinely empty portfolio. Say which one it is.
  const loadError = eventsError?.message || calcsError?.message || periodsError?.message || null

  const eventList = events || []
  const calcList = savingsCalcs || []

  // ALL savings figures come from the single source of truth (lib/savings).
  const rollup = portfolioRollup(calcList, eventList as any, { topCategories: 8 })

  // Real schedule rows where a project has them; portfolioByYear synthesises
  // the rest from each calculation's own dates so one method covers everything.
  const periodsByCalcId = new Map<string, SchedulePeriod[]>()
  for (const r of periodRows || []) {
    const key = (r as any).savings_calculation_id
    if (!key) continue
    const list = periodsByCalcId.get(key) || []
    list.push(toSchedulePeriods([r as any])[0])
    periodsByCalcId.set(key, list)
  }
  const byYear = portfolioByYear(calcList, periodsByCalcId)

  // The savings TYPE split comes from the two amount columns, never from the
  // derived savings_type label — a negotiation produces both legs, and the
  // label only records which one carried the deal. Scoped to the selected
  // fiscal year when there is one, so it agrees with the table above it.
  const scoped = selectedYear === null ? null : byYear.years.find(y => y.year === selectedYear) ?? null
  const typeSplit = [
    { name: 'Cost Reduction', value: scoped ? (scoped.reduction ?? 0) : rollup.totalCostReduction },
    { name: 'Cost Avoidance', value: scoped ? scoped.avoidance : rollup.totalCostAvoidance },
  ]

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
        <h1 className="text-2xl font-bold text-[var(--text)]">Dashboard</h1>
        <p className="mt-1 text-sm text-[var(--text-2)]">
          Procurement value overview — savings, pipeline, and project activity
        </p>
      </div>

      {loadError && (
        <div className="mb-6 rounded-lg bg-red-50 p-4 text-sm text-red-700 dark:bg-red-900/30 dark:text-red-300" role="alert">
          <strong>These figures are incomplete.</strong> A query failed: {loadError}. Do not report
          from this page until it loads cleanly.
        </div>
      )}

      <DashboardStats stats={{
        totalSavings: rollup.totalSavings,
        activeEvents,
        totalCostReduction: rollup.totalCostReduction,
        totalCostAvoidance: rollup.totalCostAvoidance,
        booked: rollup.booked,
        forecast: rollup.forecast,
        bookedCount: rollup.bookedCount,
        forecastCount: rollup.forecastCount,
      }} />

      {/* The fiscal-year report — the figure the CFO asks for. */}
      <div className="mt-6">
        <FiscalYearPanel data={byYear} selectedYear={selectedYear} basePath="/dashboard" />
      </div>

      <div className="mt-6">
        <SavingsByYearChart data={byYear.years} selectedYear={selectedYear} />
      </div>

      <div className="mt-6 grid grid-cols-1 gap-6 lg:grid-cols-2">
        <SavingsByCategoryChart data={rollup.byCategory} />
        <EventsByStatusChart data={eventsByStatus} />
        <SavingsByTypeChart data={typeSplit} />
      </div>
      <p className="mt-2 text-xs text-[var(--text-3)]">
        Savings by Type splits on the Cost Reduction and Cost Avoidance amounts
        {selectedYear !== null && <> for <strong>FY{selectedYear}</strong></>}, not on a project&apos;s
        label — a negotiation produces both legs. Category and Status cover <strong>all years</strong>
        {selectedYear !== null && ' and are not affected by the fiscal-year filter'}.
      </p>

      <Card className="mt-6 p-6">
        <div className="mb-4 flex items-center justify-between">
          <h3 className="text-sm font-semibold uppercase tracking-wider text-[var(--text-3)]">Recent Projects</h3>
          <Link href="/events" className="text-sm font-medium text-[var(--brand-ink)] hover:underline">
            View all →
          </Link>
        </div>
        <div className="space-y-2">
          {eventList.length === 0 && (
            <p className="py-6 text-center text-sm text-[var(--text-3)]">
              No projects yet.{' '}
              <Link href="/events/new" className="font-medium text-[var(--brand-ink)] hover:underline">
                Create the first one
              </Link>
              .
            </p>
          )}
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
