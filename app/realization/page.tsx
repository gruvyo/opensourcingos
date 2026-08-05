import { createClient } from '@/lib/supabase/server'
import { fetchPortfolioRows } from '@/lib/supabase/portfolio-query'
import Link from 'next/link'
import { formatCurrency, formatDate } from '@/lib/utils'
import { realizationRollup, getFirst } from '@/lib/savings'
import { Card } from '@/components/ui/card'
import { TrendingUp, ArrowRight } from 'lucide-react'
import type { Tables } from '@/lib/database.types'

type EventRelation = Pick<Tables<'sourcing_events'>, 'id' | 'event_name'>
type RealizationPeriod = Pick<
  Tables<'realization_periods'>,
  | 'id'
  | 'period_name'
  | 'period_start_date'
  | 'period_end_date'
  | 'baseline_amount'
  | 'projected_savings'
  | 'actual_amount'
  | 'realized_savings'
  | 'leakage_amount'
  | 'realization_status'
  | 'finance_validated'
  | 'event_id'
> & {
  event: EventRelation | EventRelation[] | null
}

// Dark-safe status pills for realization periods.
const STATUS_PILL: Record<string, string> = {
  'Pending': 'bg-[var(--surface-2)] text-[var(--text-2)]',
  'In Progress': 'bg-blue-100 text-blue-700 dark:bg-blue-500/15 dark:text-blue-300',
  'Realized': 'bg-green-100 text-green-700 dark:bg-green-500/15 dark:text-green-300',
  'Partially Realized': 'bg-amber-100 text-amber-700 dark:bg-amber-500/15 dark:text-amber-300',
  'Not Realized': 'bg-red-100 text-red-700 dark:bg-red-500/15 dark:text-red-300',
  'Leaked': 'bg-red-100 text-red-700 dark:bg-red-500/15 dark:text-red-300',
}

export default async function RealizationPage() {
  const supabase = await createClient()

  const { data: periods, error: periodsError } = await fetchPortfolioRows(
    'Realization periods',
    (from, to) => (
      supabase
        .from('realization_periods')
        .select(`
          id, period_name, period_start_date, period_end_date,
          baseline_amount, projected_savings, actual_amount,
          realized_savings, leakage_amount, realization_status,
          finance_validated, event_id,
          event:sourcing_events(id, event_name)
        `, { count: 'exact' })
        .order('period_start_date', { ascending: true })
        .order('id', { ascending: true })
        .range(from, to)
    ),
  )

  const rows = (periods || []) as RealizationPeriod[]
  const rollup = realizationRollup(rows)

  return (
    <div className="p-8">
      <div className="mb-6">
        <h1 className="text-2xl font-bold text-[var(--text)]">Realization</h1>
        <p className="mt-1 text-sm text-[var(--text-2)]">
          Actual savings landing vs. projected — across all sourcing projects
        </p>
      </div>

      {periodsError ? (
        <div className="mb-6 rounded-lg bg-red-50 p-4 text-sm text-red-700 dark:bg-red-900/30 dark:text-red-300" role="alert">
          <strong>These figures are incomplete.</strong> A query failed: {periodsError.message}. Do not report
          from this page until it loads cleanly.
        </div>
      ) : null}

      {/* Summary */}
      <div className="grid grid-cols-2 gap-4 lg:grid-cols-4">
        <Card className="p-6">
          <p className="text-sm font-medium text-[var(--text-3)]">Projected Savings</p>
          <p className="mt-2 text-2xl font-bold text-[var(--text)]">{formatCurrency(rollup.totalProjected)}</p>
        </Card>
        <Card className="p-6">
          <p className="text-sm font-medium text-[var(--text-3)]">Realized Savings</p>
          <p className="mt-2 text-2xl font-bold text-green-600 dark:text-green-400">{formatCurrency(rollup.totalRealized)}</p>
        </Card>
        <Card className="p-6">
          <p className="text-sm font-medium text-[var(--text-3)]">Leakage</p>
          <p className="mt-2 text-2xl font-bold text-red-600 dark:text-red-400">{formatCurrency(rollup.totalLeakage)}</p>
        </Card>
        <Card className="p-6">
          <p className="text-sm font-medium text-[var(--text-3)]">Realization Rate</p>
          <p className="mt-2 text-2xl font-bold text-indigo-600 dark:text-indigo-400">{rollup.realizationRate.toFixed(1)}%</p>
          <p className="mt-1 text-xs text-[var(--text-3)]">Realized ÷ projected</p>
        </Card>
      </div>

      {/* Periods table */}
      <div className="mt-6 overflow-x-auto rounded-lg border border-[var(--border)] bg-[var(--surface)] shadow-sm">
        <div className="border-b border-[var(--border)] px-6 py-4">
          <h2 className="text-sm font-semibold text-[var(--text)]">Realization Periods</h2>
        </div>
        <table className="w-full min-w-[900px]">
          <caption className="sr-only">Savings realization periods across projects</caption>
          <thead>
            <tr className="border-b border-[var(--border)] bg-[var(--surface-2)] text-left text-xs font-semibold uppercase tracking-wider text-[var(--text-3)]">
              <th scope="col" className="px-4 py-3">Project</th>
              <th scope="col" className="px-4 py-3">Period</th>
              <th scope="col" className="px-4 py-3 text-right">Projected</th>
              <th scope="col" className="px-4 py-3 text-right">Actual</th>
              <th scope="col" className="px-4 py-3 text-right">Realized</th>
              <th scope="col" className="px-4 py-3 text-right">Leakage</th>
              <th scope="col" className="px-4 py-3">Status</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-[var(--border)]">
            {rows.length === 0 ? (
              <tr>
                <td colSpan={7} className="px-4 py-12 text-center">
                  <TrendingUp className="mx-auto mb-2 h-8 w-8 text-[var(--text-3)]" />
                  <p className="text-sm text-[var(--text-3)]">No realization periods yet</p>
                  <p className="mt-1 text-xs text-[var(--text-3)]">
                    Add periods inside a project&apos;s Realization tab to track actual vs. projected savings.
                  </p>
                </td>
              </tr>
            ) : (
              rows.map((p) => {
                const event = getFirst<EventRelation>(p.event)
                return (
                  <tr key={p.id} className="transition-colors hover:bg-[var(--surface-2)]">
                    <td className="px-4 py-3">
                      {event?.event_name ? (
                        <Link href={`/events/${p.event_id}`} className="inline-flex items-center gap-1 text-sm font-medium text-[var(--brand-ink)] hover:underline">
                          {event.event_name}
                          <ArrowRight className="h-3 w-3" />
                        </Link>
                      ) : <span className="text-sm text-[var(--text-3)]">—</span>}
                    </td>
                    <td className="px-4 py-3">
                      <div className="text-sm text-[var(--text)]">{p.period_name}</div>
                      <div className="text-xs text-[var(--text-3)]">{formatDate(p.period_start_date)} → {formatDate(p.period_end_date)}</div>
                    </td>
                    <td className="px-4 py-3 text-right text-sm font-medium text-[var(--text)]">{formatCurrency(p.projected_savings)}</td>
                    <td className="px-4 py-3 text-right text-sm text-[var(--text-2)]">{formatCurrency(p.actual_amount)}</td>
                    <td className="px-4 py-3 text-right text-sm font-medium text-green-600 dark:text-green-400">{formatCurrency(p.realized_savings)}</td>
                    <td className="px-4 py-3 text-right text-sm font-medium text-red-600 dark:text-red-400">{(p.leakage_amount ?? 0) > 0 ? formatCurrency(p.leakage_amount) : '—'}</td>
                    <td className="px-4 py-3">
                      <span className={`inline-flex rounded-full px-2.5 py-0.5 text-xs font-medium ${STATUS_PILL[p.realization_status ?? ''] || STATUS_PILL['Pending']}`}>
                        {p.realization_status}
                      </span>
                    </td>
                  </tr>
                )
              })
            )}
          </tbody>
        </table>
      </div>
    </div>
  )
}
