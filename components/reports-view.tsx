'use client'

import { Download, FileText, DollarSign } from 'lucide-react'
import { formatCurrency, formatDate } from '@/lib/utils'

type EventRow = {
  id: string
  event_name: string
  event_type: string
  event_status: string
  category: any
  business_unit: any
  incumbent_supplier: any
  awarded_supplier: any
  contract_start_date: string | null
  contract_end_date: string | null
}

type SavingsRow = {
  id: string
  calculation_name: string
  savings_type: string
  gross_savings_amount: number
  savings_percentage: number
  calculation_status: string
  finance_validated: boolean
  current_year_recognized_amount: number
  event: any
  baseline: any
  award: any
}

// Helper to get first element from array-or-object join
function getFirst(obj: any): any {
  if (!obj) return null
  if (Array.isArray(obj)) return obj[0] || null
  return obj
}

function downloadCSV(filename: string, rows: string[][]) {
  const csv = rows.map(r => r.map(cell => `"${(cell || '').replace(/"/g, '""')}"`).join(',')).join('\n')
  const blob = new Blob([csv], { type: 'text/csv' })
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = filename
  a.click()
  URL.revokeObjectURL(url)
}

export function ReportsView({ events, savingsCalcs }: { events: EventRow[]; savingsCalcs: SavingsRow[] }) {
  const exportEvents = () => {
    const headers = ['Event Name', 'Type', 'Status', 'Category', 'Business Unit', 'Incumbent Supplier', 'Awarded Supplier', 'Contract Start', 'Contract End']
    const rows = [headers, ...events.map(e => [
      e.event_name, e.event_type, e.event_status,
      getFirst(e.category)?.category_name || '',
      getFirst(e.business_unit)?.business_unit_name || '',
      getFirst(e.incumbent_supplier)?.supplier_name || '',
      getFirst(e.awarded_supplier)?.supplier_name || '',
      e.contract_start_date || '', e.contract_end_date || '',
    ])]
    downloadCSV('sourcing_events.csv', rows)
  }

  const exportSavings = () => {
    const headers = ['Event', 'Calculation Name', 'Savings Type', 'Baseline', 'Award', 'Gross Savings', 'Savings %', 'Status', 'Finance Validated', 'Current-Year Recognized']
    const rows = [headers, ...savingsCalcs.map(c => [
      getFirst(c.event)?.event_name || '', c.calculation_name, c.savings_type,
      getFirst(c.baseline)?.baseline_name || '', getFirst(c.award)?.award_name || '',
      c.gross_savings_amount?.toString() || '', c.savings_percentage?.toFixed(2) || '',
      c.calculation_status, c.finance_validated ? 'Yes' : 'No',
      c.current_year_recognized_amount?.toString() || '',
    ])]
    downloadCSV('savings_calculations.csv', rows)
  }

  const totalSavings = savingsCalcs.reduce((sum, c) => sum + (c.gross_savings_amount || 0), 0)
  const validatedSavings = savingsCalcs.filter(c => c.finance_validated).reduce((sum, c) => sum + (c.gross_savings_amount || 0), 0)
  const recognizedSavings = savingsCalcs.reduce((sum, c) => sum + (c.current_year_recognized_amount || 0), 0)

  return (
    <div className="mt-6 space-y-6">
      <div className="grid grid-cols-3 gap-4">
        <div className="rounded-lg border border-gray-200 bg-white p-6 shadow-sm">
          <p className="text-sm font-medium text-gray-500">Total Gross Savings</p>
          <p className="mt-2 text-2xl font-bold text-gray-900">{formatCurrency(totalSavings)}</p>
        </div>
        <div className="rounded-lg border border-gray-200 bg-white p-6 shadow-sm">
          <p className="text-sm font-medium text-gray-500">Finance Validated</p>
          <p className="mt-2 text-2xl font-bold text-emerald-600">{formatCurrency(validatedSavings)}</p>
        </div>
        <div className="rounded-lg border border-gray-200 bg-white p-6 shadow-sm">
          <p className="text-sm font-medium text-gray-500">Current-Year Recognized</p>
          <p className="mt-2 text-2xl font-bold text-indigo-600">{formatCurrency(recognizedSavings)}</p>
        </div>
      </div>

      <div className="grid grid-cols-1 gap-4 md:grid-cols-2">
        <div className="rounded-lg border border-gray-200 bg-white p-6 shadow-sm">
          <div className="flex items-start gap-4">
            <div className="flex h-12 w-12 items-center justify-center rounded-lg bg-indigo-50">
              <FileText className="h-6 w-6 text-indigo-600" />
            </div>
            <div className="flex-1">
              <h3 className="text-sm font-semibold text-gray-900">Sourcing Events Export</h3>
              <p className="mt-1 text-xs text-gray-500">
                Export all {events.length} sourcing events with categories, suppliers, dates, and status
              </p>
              <button onClick={exportEvents}
                className="mt-3 flex items-center gap-2 rounded-lg bg-indigo-600 px-4 py-2 text-sm font-medium text-white hover:bg-indigo-700">
                <Download className="h-4 w-4" />
                Download CSV
              </button>
            </div>
          </div>
        </div>

        <div className="rounded-lg border border-gray-200 bg-white p-6 shadow-sm">
          <div className="flex items-start gap-4">
            <div className="flex h-12 w-12 items-center justify-center rounded-lg bg-green-50">
              <DollarSign className="h-6 w-6 text-green-600" />
            </div>
            <div className="flex-1">
              <h3 className="text-sm font-semibold text-gray-900">Savings Calculations Export</h3>
              <p className="mt-1 text-xs text-gray-500">
                Export all {savingsCalcs.length} savings calculations with baseline, award, and savings amounts
              </p>
              <button onClick={exportSavings}
                className="mt-3 flex items-center gap-2 rounded-lg bg-indigo-600 px-4 py-2 text-sm font-medium text-white hover:bg-indigo-700">
                <Download className="h-4 w-4" />
                Download CSV
              </button>
            </div>
          </div>
        </div>
      </div>

      <div className="rounded-lg border border-gray-200 bg-white shadow-sm">
        <div className="border-b border-gray-200 px-6 py-4">
          <h3 className="text-sm font-semibold text-gray-900">Savings Calculations</h3>
        </div>
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b border-gray-200 bg-gray-50 text-left text-xs uppercase text-gray-500">
                <th className="px-4 py-3">Event</th>
                <th className="px-4 py-3">Calculation</th>
                <th className="px-4 py-3">Type</th>
                <th className="px-4 py-3 text-right">Gross Savings</th>
                <th className="px-4 py-3 text-right">Savings %</th>
                <th className="px-4 py-3">Status</th>
                <th className="px-4 py-3 text-center">Finance</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-200">
              {savingsCalcs.length === 0 ? (
                <tr>
                  <td colSpan={7} className="px-4 py-8 text-center text-sm text-gray-500">
                    No savings calculations yet
                  </td>
                </tr>
              ) : (
                savingsCalcs.map((calc) => (
                  <tr key={calc.id} className="hover:bg-gray-50">
                    <td className="px-4 py-3 text-sm text-gray-900">{getFirst(calc.event)?.event_name || '—'}</td>
                    <td className="px-4 py-3 text-sm text-gray-600">{calc.calculation_name}</td>
                    <td className="px-4 py-3">
                      <span className="rounded bg-gray-100 px-2 py-0.5 text-xs text-gray-700">
                        {calc.savings_type}
                      </span>
                    </td>
                    <td className="px-4 py-3 text-right text-sm font-medium text-green-600">
                      {formatCurrency(calc.gross_savings_amount)}
                    </td>
                    <td className="px-4 py-3 text-right text-sm text-gray-700">
                      {calc.savings_percentage?.toFixed(1)}%
                    </td>
                    <td className="px-4 py-3 text-sm text-gray-600">{calc.calculation_status}</td>
                    <td className="px-4 py-3 text-center">
                      {calc.finance_validated ? (
                        <span className="rounded bg-emerald-100 px-2 py-0.5 text-xs text-emerald-700">Validated</span>
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
    </div>
  )
}
