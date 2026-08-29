import { createClient } from '@/lib/supabase/server'
import { fetchPortfolioRows } from '@/lib/supabase/portfolio-query'
import Link from 'next/link'
import {
  DEFAULT_WORKSPACE_CURRENCY,
  DEFAULT_WORKSPACE_LOCALE,
  DEFAULT_WORKSPACE_TIMEZONE,
  workspaceFormatters,
} from '@/lib/workspace-settings'
import { portfolioRollup, reportedSavings, scheduleLifecycleRollup, getFirst, type SchedulePeriodRow } from '@/lib/savings'
import { Calculator, ArrowRight } from 'lucide-react'
import { Card } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { sourcingSavingsPopulation } from '@/lib/savings-population'

export default async function SavingsPage() {
  const supabase = await createClient()

  const [
    { data: savingsCalcs, error: savingsCalcsError },
    { data: events, error: eventsError },
    { data: periodRows, error: periodsError },
    { data: settings, error: settingsError },
  ] = await Promise.all([
    fetchPortfolioRows('Savings calculations', (from, to) => (
      supabase.from('savings_calculations').select(`
        id, calculation_name, savings_type, gross_savings_amount, savings_percentage,
        calculation_status,
        cost_reduction_amount, cost_avoidance_amount,
        savings_start_date, savings_end_date,
        created_at, event_id,
        event:sourcing_events(event_name, contract_start_date, project_type),
        baseline:baselines(baseline_name),
        award:awards(award_name)
      `, { count: 'exact' })
        .order('created_at', { ascending: false })
        .order('id', { ascending: false })
        .range(from, to)
    )),
    fetchPortfolioRows('Projects', (from, to) => (
      supabase.from('sourcing_events')
        .select('id, contract_start_date, project_type', { count: 'exact' })
        .order('id', { ascending: true })
        .range(from, to)
    )),
    fetchPortfolioRows('Savings periods', (from, to) => (
      supabase.from('savings_periods').select(`
        savings_calculation_id, period_number, period_month, period_year, period_months,
        baseline_amount, total_savings_amount,
        executed_baseline_amount, executed_total_savings_amount
      `, { count: 'exact' })
        .order('savings_calculation_id')
        .order('period_number')
        .range(from, to)
    )),
    supabase.from('organization_settings').select('timezone, currency_code, locale').maybeSingle(),
  ])

  // A failed query here would render as "$0 savings", which is indistinguishable
  // from a genuinely empty portfolio. Say which one it is.
  const loadError = savingsCalcsError?.message || eventsError?.message || periodsError?.message || settingsError?.message || null

  const eventList = events || []
  const population = sourcingSavingsPopulation(
    eventList,
    savingsCalcs || [],
    (periodRows || []) as Array<SchedulePeriodRow & { savings_calculation_id?: string | null }>,
  )
  const calcs = population.calculations
  const sourcingEvents = population.events
  const sourcingPeriodRows = population.periodRows
  const now = new Date()
  const { formatCurrency, formatReduction, formatDate } = workspaceFormatters(
    settings?.currency_code || DEFAULT_WORKSPACE_CURRENCY,
    settings?.locale || DEFAULT_WORKSPACE_LOCALE,
  )

  // Single source of truth for every headline/breakdown number.
  const rollup = portfolioRollup(calcs, sourcingEvents, {
    now,
    timeZone: settings?.timezone || DEFAULT_WORKSPACE_TIMEZONE,
  })
  const lifecycle = scheduleLifecycleRollup(
    calcs,
    sourcingPeriodRows,
    now,
  )

  // The savings TYPE split comes from the two amount columns, never from the
  // derived savings_type label — a negotiation produces both legs, and the
  // label only records which one carried the deal. (See app/dashboard/page.tsx
  // for the same approach.)
  const typeSplit = [
    { name: 'Cost Reduction', value: rollup.totalCostReduction },
    { name: 'Cost Avoidance', value: rollup.totalCostAvoidance },
  ]

  return (
    <div className="p-8">
      <div className="mb-6">
        <h1 className="text-2xl font-bold text-[var(--text)]">Savings</h1>
        <p className="mt-1 text-sm text-[var(--text-2)]">
          All savings across sourcing projects — cost reduction, cost avoidance, and total savings
        </p>
      </div>

      {loadError && (
        <div className="mb-6 rounded-lg bg-red-50 p-4 text-sm text-red-700 dark:bg-red-900/30 dark:text-red-300" role="alert">
          <strong>These figures are incomplete.</strong> A query failed: {loadError}. Do not report
          from this page until it loads cleanly.
        </div>
      )}

      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <Card className="p-6">
          <p className="text-sm font-medium text-[var(--text-3)]">Spend Addressed</p>
          <p className="mt-2 text-2xl font-bold text-[var(--text)]">{formatCurrency(lifecycle.spendAddressed)}</p>
          <p className="mt-1 text-xs text-[var(--text-3)]">Scheduled baseline spend where a hard baseline exists</p>
        </Card>
        <Card className="p-6">
          <p className="text-sm font-medium text-[var(--text-3)]">Estimated Pipeline</p>
          <p className="mt-2 text-2xl font-bold text-blue-600 dark:text-blue-400">{formatCurrency(lifecycle.estimatedPipeline)}</p>
          <p className="mt-1 text-xs text-[var(--text-3)]">{lifecycle.estimatedCount} scheduled estimate{lifecycle.estimatedCount === 1 ? '' : 's'} not yet executed</p>
        </Card>
        <Card className="p-6">
          <p className="text-sm font-medium text-[var(--text-3)]">Executed Savings</p>
          <p className="mt-2 text-2xl font-bold text-green-600 dark:text-green-400">{formatCurrency(lifecycle.executed)}</p>
          <p className="mt-1 text-xs text-[var(--text-3)]">Confirmed commercial results across {lifecycle.executedCount} schedule{lifecycle.executedCount === 1 ? '' : 's'}</p>
        </Card>
        <Card className="p-6">
          <p className="text-sm font-medium text-[var(--text-3)]">Accrued Executed</p>
          <p className="mt-2 text-2xl font-bold text-violet-600 dark:text-violet-400">{formatCurrency(lifecycle.accruedExecuted)}</p>
          <p className="mt-1 text-xs text-[var(--text-3)]">Executed savings scheduled through this month</p>
        </Card>
      </div>

      {/* The savings TYPE split comes from the two amount columns, never from the
          derived savings_type label — a negotiation produces both legs, and the
          label only records which one carried the deal. This keeps the split in
          agreement with the three cards above it. */}
      <Card className="mt-4 p-6">
        <h2 className="mb-4 text-sm font-semibold uppercase tracking-wider text-[var(--text-3)]">Savings by Type</h2>
        <div className="flex flex-wrap gap-3">
          {typeSplit.map(({ name, value }) => (
            <div key={name} className="rounded-lg bg-[var(--surface-2)] px-4 py-2">
              <span className="text-sm font-medium text-[var(--text-2)]">{name}</span>
              <span className="ml-2 text-sm font-bold text-[var(--text)]">{formatCurrency(value)}</span>
            </div>
          ))}
        </div>
        <p className="mt-3 text-xs text-[var(--text-3)]">
          Splits on the Cost Reduction and Cost Avoidance amounts, not on a project&apos;s
          label — a negotiation produces both legs.
        </p>
      </Card>

      {/* Calculations table */}
      <Card className="mt-6 overflow-x-auto">
        <div className="border-b border-[var(--border)] px-6 py-4">
          <h2 className="text-sm font-semibold text-[var(--text)]">All Savings Calculations</h2>
        </div>
        <table className="w-full min-w-[1000px]">
          <caption className="sr-only">All savings calculations</caption>
          <thead>
            <tr className="border-b border-[var(--border)] bg-[var(--surface-2)]">
              <th scope="col" className="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-[var(--text-3)]">Event</th>
              <th scope="col" className="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-[var(--text-3)]">Calculation</th>
              <th scope="col" className="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-[var(--text-3)]">Type</th>
              <th scope="col" className="px-4 py-3 text-right text-xs font-semibold uppercase tracking-wider text-[var(--text-3)]">Cost Reduction</th>
              <th scope="col" className="px-4 py-3 text-right text-xs font-semibold uppercase tracking-wider text-[var(--text-3)]">Cost Avoidance</th>
              <th scope="col" className="px-4 py-3 text-right text-xs font-semibold uppercase tracking-wider text-[var(--text-3)]">Total Savings</th>
              <th scope="col" className="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-[var(--text-3)]">Savings Period</th>
              <th scope="col" className="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-[var(--text-3)]">Status</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-[var(--border)]">
            {calcs.length === 0 ? (
              <tr>
                <td colSpan={8} className="px-4 py-12 text-center">
                  <Calculator className="mx-auto mb-2 h-8 w-8 text-[var(--text-3)]" />
                  <p className="text-sm text-[var(--text-3)]">No savings calculations yet</p>
                  <p className="mt-1 text-xs text-[var(--text-3)]">
                    Calculations are created inside each sourcing event&apos;s Calculations tab
                  </p>
                </td>
              </tr>
            ) : (
              calcs.map((calc) => {
                const event = getFirst<{ event_name: string; contract_start_date: string | null }>(calc.event)
                const totalForCalc = reportedSavings(calc)
                return (
                  <tr key={calc.id} className="hover:bg-[var(--surface-2)]">
                    <td className="px-4 py-3">
                      {event?.event_name ? (
                        <Link href={`/events/${calc.event_id}`} className="flex items-center gap-1 text-sm font-medium text-[var(--brand-ink)] hover:underline">
                          {event.event_name}
                          <ArrowRight className="h-3 w-3" />
                        </Link>
                      ) : <span className="text-sm text-[var(--text-3)]">—</span>}
                    </td>
                    <td className="px-4 py-3 text-sm text-[var(--text-2)]">{calc.calculation_name}</td>
                    <td className="px-4 py-3">
                      <Badge tone="neutral" className="rounded">
                        {calc.savings_type}
                      </Badge>
                    </td>
                    <td className="px-4 py-3 text-right text-sm font-medium text-red-600 dark:text-red-400">
                      {formatReduction(calc.cost_reduction_amount)}
                    </td>
                    <td className="px-4 py-3 text-right text-sm font-medium text-amber-600 dark:text-amber-400">
                      {formatCurrency(calc.cost_avoidance_amount)}
                    </td>
                    <td className="px-4 py-3 text-right text-sm font-bold text-green-600 dark:text-green-400">
                      {formatCurrency(totalForCalc)}
                    </td>
                    <td className="px-4 py-3 text-sm text-[var(--text-2)]">
                      {calc.savings_start_date ? `${formatDate(calc.savings_start_date)} → ${formatDate(calc.savings_end_date)}` : '—'}
                    </td>
                    <td className="px-4 py-3"><Badge tone={calc.calculation_status === 'executed' ? 'success' : 'info'} className="capitalize">{calc.calculation_status}</Badge></td>
                  </tr>
                )
              })
            )}
          </tbody>
        </table>
      </Card>
    </div>
  )
}
