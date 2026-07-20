import { createClient } from '@/lib/supabase/server'
import Link from 'next/link'
import { formatCurrency, formatDate, statusColor } from '@/lib/utils'
import { TrendingUp, ArrowRight } from 'lucide-react'

function getFirst(obj: any): any {
  if (!obj) return null
  if (Array.isArray(obj)) return obj[0] || null
  return obj
}

export default async function RealizationPage() {
  const supabase = await createClient()

  const { data: periods } = await supabase
    .from('realization_periods')
    .select(`
      id, period_name, period_type, period_start_date, period_end_date,
      projected_savings, realized_savings, leakage_amount, leakage_reason,
      finance_validated, notes, created_at,
      calculation:savings_calculations(
        id, calculation_name,
        event:sourcing_events(id, event_name)
      )
    `)
    .order('period_start_date', { ascending: false, nullsFirst: false })

  const allPeriods = periods || []
  const totalProjected = allPeriods.reduce((sum: number, p: any) => sum + (p.projected_savings || 0), 0)
  const totalRealized = allPeriods.reduce((sum: number, p: any) => sum + (p.realized_savings || 0), 0)
  const totalLeakage = allPeriods.reduce((sum: number, p: any) => sum + (p.leakage_amount || 0), 0)
  const realizationRate = totalProjected > 0 ? (totalRealized / totalProjected) * 100 : 0

  return (
    <div className="p-8">
      <div className="mb-6">
        <h1 className="text-2xl font-bold text-gray-900 dark:text-gray-100">Realization Tracking</h1>
        <p className="mt-1 text-sm text-gray-600 dark:text-gray-400">
          Track projected vs realized savings across all projects
        </p>
      </div>

      {/* Summary cards */}
      <div className="grid grid-cols-2 gap-4 lg:grid-cols-4">
        <div className="rounded-lg border border-gray-200 bg-white p-6 shadow-sm dark:border-gray-700 dark:bg-gray-800">
          <p className="text-sm font-medium text-gray-500 dark:text-gray-400">Total Projected</p>
          <p className="mt-2 text-2xl font-bold text-gray-900 dark:text-gray-100">{formatCurrency(totalProjected)}</p>
        </div>
        <div className="rounded-lg border border-gray-200 bg-white p-6 shadow-sm dark:border-gray-700 dark:bg-gray-800">
          <p className="text-sm font-medium text-gray-500 dark:text-gray-400">Total Realized</p>
          <p className="mt-2 text-2xl font-bold text-green-600 dark:text-green-400">{formatCurrency(totalRealized)}</p>
        </div>
        <div className="rounded-lg border border-gray-200 bg-white p-6 shadow-sm dark:border-gray-700 dark:bg-gray-800">
          <p className="text-sm font-medium text-gray-500 dark:text-gray-400">Realization Rate</p>
          <p className="mt-2 text-2xl font-bold text-indigo-600 dark:text-indigo-400">{realizationRate.toFixed(1)}%</p>
        </div>
        <div className="rounded-lg border border-gray-200 bg-white p-6 shadow-sm dark:border-gray-700 dark:bg-gray-800">
          <p className="text-sm font-medium text-gray-500 dark:text-gray-400">Total Leakage</p>
          <p className="mt-2 text-2xl font-bold text-red-600 dark:text-red-400">{formatCurrency(totalLeakage)}</p>
        </div>
      </div>

      {/* Realization table */}
      <div className="mt-6 overflow-x-auto rounded-lg border border-gray-200 bg-white shadow-sm dark:border-gray-700 dark:bg-gray-800">
        <div className="border-b border-gray-200 px-6 py-4 dark:border-gray-700">
          <h3 className="text-sm font-semibold text-gray-900 dark:text-gray-100">All Realization Periods</h3>
        </div>
        <table className="w-full min-w-[900px]">
          <thead>
            <tr className="border-b border-gray-200 bg-gray-50 dark:border-gray-700 dark:bg-gray-900/50">
              <th className="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-gray-500 dark:text-gray-400">Period</th>
              <th className="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-gray-500 dark:text-gray-400">Event</th>
              <th className="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-gray-500 dark:text-gray-400">Type</th>
              <th className="px-4 py-3 text-right text-xs font-semibold uppercase tracking-wider text-gray-500 dark:text-gray-400">Projected</th>
              <th className="px-4 py-3 text-right text-xs font-semibold uppercase tracking-wider text-gray-500 dark:text-gray-400">Realized</th>
              <th className="px-4 py-3 text-right text-xs font-semibold uppercase tracking-wider text-gray-500 dark:text-gray-400">Leakage</th>
              <th className="px-4 py-3 text-center text-xs font-semibold uppercase tracking-wider text-gray-500 dark:text-gray-400">Finance</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-gray-200 dark:divide-gray-700">
            {allPeriods.length === 0 ? (
              <tr>
                <td colSpan={7} className="px-4 py-12 text-center">
                  <TrendingUp className="mx-auto mb-2 h-8 w-8 text-gray-300 dark:text-gray-600" />
                  <p className="text-sm text-gray-500 dark:text-gray-400">No realization periods yet</p>
                  <p className="mt-1 text-xs text-gray-400 dark:text-gray-500">
                    Realization periods are created inside each sourcing event's Realization tab
                  </p>
                </td>
              </tr>
            ) : (
              allPeriods.map((period: any) => {
                const calc = getFirst(period.calculation)
                const event = getFirst(calc?.event)
                return (
                  <tr key={period.id} className="hover:bg-gray-50 dark:hover:bg-gray-700/50">
                    <td className="px-4 py-3">
                      <div className="text-sm font-medium text-gray-900 dark:text-gray-100">{period.period_name}</div>
                      {period.period_start_date && (
                        <div className="text-xs text-gray-500 dark:text-gray-400">
                          {formatDate(period.period_start_date)} → {formatDate(period.period_end_date)}
                        </div>
                      )}
                    </td>
                    <td className="px-4 py-3">
                      {event ? (
                        <Link href={`/events/${event.id}`} className="flex items-center gap-1 text-sm font-medium text-indigo-600 hover:text-indigo-800 dark:text-indigo-400">
                          {event.event_name}
                          <ArrowRight className="h-3 w-3" />
                        </Link>
                      ) : <span className="text-sm text-gray-400">—</span>}
                    </td>
                    <td className="px-4 py-3 text-sm text-gray-600 dark:text-gray-400">{period.period_type || '—'}</td>
                    <td className="px-4 py-3 text-right text-sm text-gray-600 dark:text-gray-400">{formatCurrency(period.projected_savings)}</td>
                    <td className="px-4 py-3 text-right text-sm font-medium text-green-600 dark:text-green-400">{formatCurrency(period.realized_savings)}</td>
                    <td className="px-4 py-3 text-right text-sm text-red-600 dark:text-red-400">
                      {period.leakage_amount ? formatCurrency(period.leakage_amount) : '—'}
                    </td>
                    <td className="px-4 py-3 text-center">
                      {period.finance_validated ? (
                        <span className="rounded bg-emerald-100 px-2 py-0.5 text-xs text-emerald-700 dark:bg-emerald-900/30 dark:text-emerald-400">Validated</span>
                      ) : (
                        <span className="text-xs text-gray-400">—</span>
                      )}
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