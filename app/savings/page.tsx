import { createClient } from '@/lib/supabase/server'
import Link from 'next/link'
import { formatCurrency, formatReduction, formatDate } from '@/lib/utils'
import { portfolioRollup, reportedSavings, classifyRealization, getFirst } from '@/lib/savings'
import { Calculator, ArrowRight } from 'lucide-react'
import { Card } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'

export default async function SavingsPage() {
  const supabase = await createClient()

  const [
    { data: savingsCalcs, error: savingsCalcsError },
    { data: events, error: eventsError },
  ] = await Promise.all([
    supabase.from('savings_calculations').select(`
      id, calculation_name, savings_type, gross_savings_amount, savings_percentage,
      calculation_status,
      cost_reduction_amount, cost_avoidance_amount,
      savings_start_date, savings_end_date,
      created_at, event_id,
      event:sourcing_events(event_name, contract_start_date),
      baseline:baselines(baseline_name),
      award:awards(award_name)
    `).order('created_at', { ascending: false }),
    supabase.from('sourcing_events').select('id, contract_start_date'),
  ])

  // A failed query here would render as "$0 savings", which is indistinguishable
  // from a genuinely empty portfolio. Say which one it is.
  const loadError = savingsCalcsError?.message || eventsError?.message || null

  const calcs = savingsCalcs || []
  const eventList = events || []
  const now = new Date()

  // Single source of truth for every headline/breakdown number.
  const rollup = portfolioRollup(calcs, eventList, { now })

  // The savings TYPE split comes from the two amount columns, never from the
  // derived savings_type label — a negotiation produces both legs, and the
  // label only records which one carried the deal. (See app/dashboard/page.tsx
  // for the same approach.)
  const typeSplit = [
    { name: 'Cost Reduction', value: rollup.totalCostReduction },
    { name: 'Cost Avoidance', value: rollup.totalCostAvoidance },
  ]

  // For per-row realized/accrued badges, use the SAME canonical rule.
  const contractStartByEventId = new Map<string, string | null>()
  for (const e of eventList) contractStartByEventId.set(e.id, e.contract_start_date ?? null)

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

      {/* Summary cards — 3 cards only */}
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-3">
        <Card className="p-6">
          <p className="text-sm font-medium text-[var(--text-3)]">Total Savings</p>
          <p className="mt-2 text-2xl font-bold text-[var(--text)]">{formatCurrency(rollup.totalSavings)}</p>
          <p className="mt-1 text-xs text-[var(--text-3)]">Gross savings across all calculations</p>
        </Card>
        <Card className="p-6">
          <p className="text-sm font-medium text-[var(--text-3)]">Cost Reduction</p>
          <p className="mt-2 text-2xl font-bold text-red-600 dark:text-red-400">{formatReduction(rollup.totalCostReduction)}</p>
          <p className="mt-1 text-xs text-[var(--text-3)]">Actual bottom-line reduction — price went down from what we were paying</p>
        </Card>
        <Card className="p-6">
          <p className="text-sm font-medium text-[var(--text-3)]">Cost Avoidance</p>
          <p className="mt-2 text-2xl font-bold text-amber-600 dark:text-amber-400">{formatCurrency(rollup.totalCostAvoidance)}</p>
          <p className="mt-1 text-xs text-[var(--text-3)]">Value not paid — negotiated below what supplier proposed</p>
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
              <th scope="col" className="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-[var(--text-3)]">Classification</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-[var(--border)]">
            {calcs.length === 0 ? (
              <tr>
                <td colSpan={9} className="px-4 py-12 text-center">
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
                const isRealized = classifyRealization(calc, contractStartByEventId, now) === 'Realized'
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
                    <td className="px-4 py-3 text-sm text-[var(--text-2)]">{calc.calculation_status}</td>
                    <td className="px-4 py-3">
                      <Badge tone={isRealized ? 'success' : 'info'}>
                        {isRealized ? 'Realized' : 'Accrued'}
                      </Badge>
                    </td>
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
