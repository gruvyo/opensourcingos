import { createClient } from '@/lib/supabase/server'
import Link from 'next/link'
import { formatCurrency, statusColor } from '@/lib/utils'
import { Calculator, ArrowRight } from 'lucide-react'

function getFirst(obj: any): any {
  if (!obj) return null
  if (Array.isArray(obj)) return obj[0] || null
  return obj
}

export default async function SavingsPage() {
  const supabase = await createClient()

  const { data: savingsCalcs } = await supabase
    .from('savings_calculations')
    .select(`
      id, calculation_name, savings_type, gross_savings_amount, savings_percentage,
      calculation_status, finance_validated, current_year_recognized_amount,
      net_savings_amount, savings_basis, created_at,
      event:sourcing_events(event_name),
      baseline:baselines(baseline_name),
      award:awards(award_name)
    `)
    .order('created_at', { ascending: false })

  const calcs = savingsCalcs || []
  const totalGross = calcs.reduce((sum: number, c: any) => sum + (c.gross_savings_amount || 0), 0)
  const totalNet = calcs.reduce((sum: number, c: any) => sum + (c.net_savings_amount || 0), 0)
  const totalRecognized = calcs.reduce((sum: number, c: any) => sum + (c.current_year_recognized_amount || 0), 0)
  const totalValidated = calcs.filter((c: any) => c.finance_validated).reduce((sum: number, c: any) => sum + (c.gross_savings_amount || 0), 0)

  // Group by savings type
  const byType = new Map<string, number>()
  for (const c of calcs) {
    byType.set(c.savings_type, (byType.get(c.savings_type) || 0) + (c.gross_savings_amount || 0))
  }

  return (
    <div className="p-8">
      <div className="mb-6">
        <h1 className="text-2xl font-bold text-gray-900 dark:text-gray-100">Savings Calculations</h1>
        <p className="mt-1 text-sm text-gray-600 dark:text-gray-400">
          All savings calculations across sourcing projects
        </p>
      </div>

      {/* Summary cards */}
      <div className="grid grid-cols-2 gap-4 lg:grid-cols-4">
        <div className="rounded-lg border border-gray-200 bg-white p-6 shadow-sm dark:border-gray-700 dark:bg-gray-800">
          <p className="text-sm font-medium text-gray-500 dark:text-gray-400">Total Gross Savings</p>
          <p className="mt-2 text-2xl font-bold text-gray-900 dark:text-gray-100">{formatCurrency(totalGross)}</p>
        </div>
        <div className="rounded-lg border border-gray-200 bg-white p-6 shadow-sm dark:border-gray-700 dark:bg-gray-800">
          <p className="text-sm font-medium text-gray-500 dark:text-gray-400">Total Net Savings</p>
          <p className="mt-2 text-2xl font-bold text-gray-900 dark:text-gray-100">{formatCurrency(totalNet)}</p>
        </div>
        <div className="rounded-lg border border-gray-200 bg-white p-6 shadow-sm dark:border-gray-700 dark:bg-gray-800">
          <p className="text-sm font-medium text-gray-500 dark:text-gray-400">Finance Validated</p>
          <p className="mt-2 text-2xl font-bold text-emerald-600 dark:text-emerald-400">{formatCurrency(totalValidated)}</p>
        </div>
        <div className="rounded-lg border border-gray-200 bg-white p-6 shadow-sm dark:border-gray-700 dark:bg-gray-800">
          <p className="text-sm font-medium text-gray-500 dark:text-gray-400">Current-Year Recognized</p>
          <p className="mt-2 text-2xl font-bold text-indigo-600 dark:text-indigo-400">{formatCurrency(totalRecognized)}</p>
        </div>
      </div>

      {/* Savings by type */}
      {byType.size > 0 && (
        <div className="mt-6 rounded-lg border border-gray-200 bg-white p-6 shadow-sm dark:border-gray-700 dark:bg-gray-800">
          <h3 className="mb-4 text-sm font-semibold uppercase tracking-wider text-gray-500 dark:text-gray-400">Savings by Type</h3>
          <div className="flex flex-wrap gap-3">
            {Array.from(byType.entries()).map(([type, amount]) => (
              <div key={type} className="rounded-lg bg-gray-50 px-4 py-2 dark:bg-gray-700/50">
                <span className="text-sm font-medium text-gray-700 dark:text-gray-300">{type}</span>
                <span className="ml-2 text-sm font-bold text-gray-900 dark:text-gray-100">{formatCurrency(amount)}</span>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* Calculations table */}
      <div className="mt-6 overflow-x-auto rounded-lg border border-gray-200 bg-white shadow-sm dark:border-gray-700 dark:bg-gray-800">
        <div className="border-b border-gray-200 px-6 py-4 dark:border-gray-700">
          <h3 className="text-sm font-semibold text-gray-900 dark:text-gray-100">All Calculations</h3>
        </div>
        <table className="w-full min-w-[800px]">
          <thead>
            <tr className="border-b border-gray-200 bg-gray-50 dark:border-gray-700 dark:bg-gray-900/50">
              <th className="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-gray-500 dark:text-gray-400">Event</th>
              <th className="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-gray-500 dark:text-gray-400">Calculation</th>
              <th className="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-gray-500 dark:text-gray-400">Type</th>
              <th className="px-4 py-3 text-right text-xs font-semibold uppercase tracking-wider text-gray-500 dark:text-gray-400">Gross Savings</th>
              <th className="px-4 py-3 text-right text-xs font-semibold uppercase tracking-wider text-gray-500 dark:text-gray-400">Net Savings</th>
              <th className="px-4 py-3 text-right text-xs font-semibold uppercase tracking-wider text-gray-500 dark:text-gray-400">Savings %</th>
              <th className="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-gray-500 dark:text-gray-400">Status</th>
              <th className="px-4 py-3 text-center text-xs font-semibold uppercase tracking-wider text-gray-500 dark:text-gray-400">Finance</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-gray-200 dark:divide-gray-700">
            {calcs.length === 0 ? (
              <tr>
                <td colSpan={8} className="px-4 py-12 text-center">
                  <Calculator className="mx-auto mb-2 h-8 w-8 text-gray-300 dark:text-gray-600" />
                  <p className="text-sm text-gray-500 dark:text-gray-400">No savings calculations yet</p>
                  <p className="mt-1 text-xs text-gray-400 dark:text-gray-500">
                    Calculations are created inside each sourcing event's Calculations tab
                  </p>
                </td>
              </tr>
            ) : (
              calcs.map((calc: any) => (
                <tr key={calc.id} className="hover:bg-gray-50 dark:hover:bg-gray-700/50">
                  <td className="px-4 py-3">
                    {getFirst(calc.event)?.event_name ? (
                      <Link href={`/events/${calc.event_id || ''}`} className="flex items-center gap-1 text-sm font-medium text-indigo-600 hover:text-indigo-800 dark:text-indigo-400">
                        {getFirst(calc.event)?.event_name}
                        <ArrowRight className="h-3 w-3" />
                      </Link>
                    ) : <span className="text-sm text-gray-400">—</span>}
                  </td>
                  <td className="px-4 py-3 text-sm text-gray-600 dark:text-gray-400">{calc.calculation_name}</td>
                  <td className="px-4 py-3">
                    <span className="rounded bg-gray-100 px-2 py-0.5 text-xs text-gray-700 dark:bg-gray-700 dark:text-gray-300">
                      {calc.savings_type}
                    </span>
                  </td>
                  <td className="px-4 py-3 text-right text-sm font-medium text-green-600 dark:text-green-400">
                    {formatCurrency(calc.gross_savings_amount)}
                  </td>
                  <td className="px-4 py-3 text-right text-sm text-gray-600 dark:text-gray-400">
                    {formatCurrency(calc.net_savings_amount)}
                  </td>
                  <td className="px-4 py-3 text-right text-sm text-gray-600 dark:text-gray-400">
                    {calc.savings_percentage?.toFixed(1)}%
                  </td>
                  <td className="px-4 py-3 text-sm text-gray-600 dark:text-gray-400">{calc.calculation_status}</td>
                  <td className="px-4 py-3 text-center">
                    {calc.finance_validated ? (
                      <span className="rounded bg-emerald-100 px-2 py-0.5 text-xs text-emerald-700 dark:bg-emerald-900/30 dark:text-emerald-400">Validated</span>
                    ) : (
                      <span className="text-xs text-gray-400">—</span>
                    )}
                  </td>
                </tr>
              ))
            )}
          </tbody>
        </table>
      </div>
    </div>
  )
}