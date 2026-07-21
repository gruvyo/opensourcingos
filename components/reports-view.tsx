'use client'

import { useState, useMemo } from 'react'
import { Download, DollarSign, Briefcase, TrendingUp, Filter } from 'lucide-react'
import { formatCurrency, formatDate, statusColor } from '@/lib/utils'

type EventRow = {
  id: string
  event_name: string
  event_type: string
  event_status: string
  project_type: string | null
  buyer_name: string | null
  event_start_date: string | null
  event_close_date: string | null
  contract_start_date: string | null
  contract_end_date: string | null
  category: any
  business_unit: any
  incumbent_supplier: any
  awarded_supplier: any
}

type SavingsRow = {
  id: string
  calculation_name: string
  savings_type: string
  gross_savings_amount: number
  savings_percentage: number
  calculation_status: string
  cost_reduction_amount: number
  cost_avoidance_amount: number
  net_savings_amount: number
  savings_start_date: string | null
  savings_end_date: string | null
  event: any
  baseline: any
  award: any
}

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
  const [typeFilter, setTypeFilter] = useState('')
  const [statusFilter, setStatusFilter] = useState('')
  const [buFilter, setBuFilter] = useState('')

  // Sourcing-only events for savings analysis
  const sourcingEvents = events.filter((e) => (e.project_type || 'Sourcing') === 'Sourcing')

  // Filters
  const businessUnits = useMemo(() => {
    const set = new Set<string>()
    sourcingEvents.forEach((e) => {
      const bu = getFirst(e.business_unit)?.business_unit_name
      if (bu) set.add(bu)
    })
    return Array.from(set).sort()
  }, [sourcingEvents])

  const filteredEvents = useMemo(() => {
    return sourcingEvents.filter((e) => {
      if (typeFilter && e.event_type !== typeFilter) return false
      if (statusFilter && e.event_status !== statusFilter) return false
      if (buFilter && getFirst(e.business_unit)?.business_unit_name !== buFilter) return false
      return true
    })
  }, [sourcingEvents, typeFilter, statusFilter, buFilter])

  // Stats
  const totalSavings = savingsCalcs.reduce((sum, c) => sum + (c.gross_savings_amount || 0), 0)
  const totalCostReduction = savingsCalcs.reduce((sum, c) => sum + (c.cost_reduction_amount || 0), 0)
  const totalCostAvoidance = savingsCalcs.reduce((sum, c) => sum + (c.cost_avoidance_amount || 0), 0)

  // Realized vs Accrued
  const now = new Date()
  const realizedSavings = savingsCalcs.filter(c => {
    if (c.savings_start_date) return new Date(c.savings_start_date) <= now
    return false
  }).reduce((sum, c) => sum + (c.gross_savings_amount || 0), 0)
  const accruedSavings = savingsCalcs.filter(c => {
    if (!c.savings_start_date) return true
    return new Date(c.savings_start_date) > now
  }).reduce((sum, c) => sum + (c.gross_savings_amount || 0), 0)

  // By status
  const byStatus = new Map<string, number>()
  for (const e of sourcingEvents) {
    byStatus.set(e.event_status, (byStatus.get(e.event_status) || 0) + 1)
  }

  // By business unit
  const byBU = new Map<string, { count: number; savings: number }>()
  for (const e of sourcingEvents) {
    const bu = getFirst(e.business_unit)?.business_unit_name || 'Unassigned'
    const savingsForEvent = savingsCalcs.filter(c => getFirst(c.event)?.event_name === e.event_name).reduce((sum, c) => sum + (c.gross_savings_amount || 0), 0)
    const existing = byBU.get(bu) || { count: 0, savings: 0 }
    byBU.set(bu, { count: existing.count + 1, savings: existing.savings + savingsForEvent })
  }

  // By type
  const byType = new Map<string, number>()
  for (const e of sourcingEvents) {
    byType.set(e.event_type, (byType.get(e.event_type) || 0) + 1)
  }

  // By buyer
  const byBuyer = new Map<string, number>()
  for (const e of sourcingEvents) {
    const buyer = e.buyer_name || 'Unassigned'
    byBuyer.set(buyer, (byBuyer.get(buyer) || 0) + 1)
  }

  const exportEvents = () => {
    const headers = ['Project Name', 'Type', 'Status', 'IP Owner', 'Category', 'Business Unit', 'Supplier', 'Event Start', 'Due Date', 'Contract Start', 'Contract End']
    const rows = [headers, ...filteredEvents.map(e => [
      e.event_name, e.event_type, e.event_status, e.buyer_name || '',
      getFirst(e.category)?.category_name || '',
      getFirst(e.business_unit)?.business_unit_name || '',
      getFirst(e.awarded_supplier)?.supplier_name || getFirst(e.incumbent_supplier)?.supplier_name || '',
      e.event_start_date || '', e.event_close_date || '',
      e.contract_start_date || '', e.contract_end_date || '',
    ])]
    downloadCSV('procurement_projects.csv', rows)
  }

  const exportSavings = () => {
    const headers = ['Event', 'Calculation', 'Type', 'Cost Reduction', 'Cost Avoidance', 'Total Savings', 'Savings %', 'Status', 'Savings Start', 'Savings End', 'Classification']
    const rows = [headers, ...savingsCalcs.map(c => {
      const isRealized = c.savings_start_date && new Date(c.savings_start_date) <= now
      return [
        getFirst(c.event)?.event_name || '', c.calculation_name, c.savings_type,
        (c.cost_reduction_amount || 0).toString(), (c.cost_avoidance_amount || 0).toString(),
        (c.gross_savings_amount || 0).toString(), c.savings_percentage?.toFixed(2) || '',
        c.calculation_status,
        c.savings_start_date || '', c.savings_end_date || '',
        c.savings_start_date ? (isRealized ? 'Realized' : 'Accrued') : 'Accrued',
      ]
    })]
    downloadCSV('savings_report.csv', rows)
  }

  const sectionClass = 'rounded-lg border border-gray-200 bg-white p-6 shadow-sm dark:border-gray-700 dark:bg-gray-800'
  const labelClass = 'text-sm font-medium text-gray-500 dark:text-gray-400'
  const valueClass = 'mt-1 text-2xl font-bold'

  return (
    <div className="mt-6 space-y-6">
      {/* Executive Summary */}
      <div className="grid grid-cols-2 gap-4 lg:grid-cols-4">
        <div className={sectionClass}>
          <div className="flex items-center justify-between">
            <div>
              <p className={labelClass}>Total Savings</p>
              <p className={`${valueClass} text-gray-900 dark:text-gray-100`}>{formatCurrency(totalSavings)}</p>
              <p className="mt-1 text-xs text-gray-400 dark:text-gray-500">Cost reduction + cost avoidance across all projects</p>
            </div>
            <div className="flex h-12 w-12 items-center justify-center rounded-lg bg-green-50 dark:bg-green-900/30">
              <DollarSign className="h-6 w-6 text-green-600 dark:text-green-400" />
            </div>
          </div>
        </div>
        <div className={sectionClass}>
          <div className="flex items-center justify-between">
            <div>
              <p className={labelClass}>Sourcing Projects</p>
              <p className={`${valueClass} text-gray-900 dark:text-gray-100`}>{sourcingEvents.length}</p>
              <p className="mt-1 text-xs text-gray-400 dark:text-gray-500">Active and completed sourcing initiatives</p>
            </div>
            <div className="flex h-12 w-12 items-center justify-center rounded-lg bg-indigo-50 dark:bg-indigo-900/30">
              <Briefcase className="h-6 w-6 text-indigo-600 dark:text-indigo-400" />
            </div>
          </div>
        </div>
        <div className={sectionClass}>
          <div className="flex items-center justify-between">
            <div>
              <p className={labelClass}>Realized</p>
              <p className={`${valueClass} text-emerald-600 dark:text-emerald-400`}>{formatCurrency(realizedSavings)}</p>
              <p className="mt-1 text-xs text-gray-400 dark:text-gray-500">Savings already in effect — contract start date has passed</p>
            </div>
            <div className="flex h-12 w-12 items-center justify-center rounded-lg bg-emerald-50 dark:bg-emerald-900/30">
              <TrendingUp className="h-6 w-6 text-emerald-600 dark:text-emerald-400" />
            </div>
          </div>
        </div>
        <div className={sectionClass}>
          <div className="flex items-center justify-between">
            <div>
              <p className={labelClass}>Accrued</p>
              <p className={`${valueClass} text-blue-600 dark:text-blue-400`}>{formatCurrency(accruedSavings)}</p>
              <p className="mt-1 text-xs text-gray-400 dark:text-gray-500">Savings not yet in effect — contract starts in the future</p>
            </div>
            <div className="flex h-12 w-12 items-center justify-center rounded-lg bg-blue-50 dark:bg-blue-900/30">
              <DollarSign className="h-6 w-6 text-blue-600 dark:text-blue-400" />
            </div>
          </div>
        </div>
      </div>

      {/* Savings breakdown */}
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-3">
        <div className={sectionClass}>
          <p className={labelClass}>Cost Reduction</p>
          <p className={`${valueClass} text-red-600 dark:text-red-400`}>{formatCurrency(totalCostReduction)}</p>
          <p className="mt-1 text-xs text-gray-400 dark:text-gray-500">Actual bottom-line reduction — price went down from what we were paying</p>
        </div>
        <div className={sectionClass}>
          <p className={labelClass}>Cost Avoidance</p>
          <p className={`${valueClass} text-amber-600 dark:text-amber-400`}>{formatCurrency(totalCostAvoidance)}</p>
          <p className="mt-1 text-xs text-gray-400 dark:text-gray-500">Value not paid — negotiated below what supplier proposed</p>
        </div>
        <div className={sectionClass}>
          <p className={labelClass}>Total Savings</p>
          <p className={`${valueClass} text-green-600 dark:text-green-400`}>{formatCurrency(totalSavings)}</p>
          <p className="mt-1 text-xs text-gray-400 dark:text-gray-500">Cost reduction + cost avoidance combined</p>
        </div>
      </div>

      {/* Activity breakdowns */}
      <div className="grid grid-cols-1 gap-6 lg:grid-cols-2">
        {/* By Business Unit */}
        <div className={sectionClass}>
          <h3 className="mb-4 text-sm font-semibold uppercase tracking-wider text-gray-500 dark:text-gray-400">Projects by Business Unit</h3>
          <div className="space-y-2">
            {Array.from(byBU.entries()).sort((a, b) => b[1].savings - a[1].savings).map(([bu, data]) => (
              <div key={bu} className="flex items-center justify-between rounded-lg bg-gray-50 px-4 py-2 dark:bg-gray-700/50">
                <span className="text-sm text-gray-700 dark:text-gray-300">{bu}</span>
                <div className="flex items-center gap-4">
                  <span className="text-xs text-gray-500 dark:text-gray-400">{data.count} project{data.count !== 1 ? 's' : ''}</span>
                  <span className="text-sm font-medium text-gray-900 dark:text-gray-100">{formatCurrency(data.savings)}</span>
                </div>
              </div>
            ))}
            {byBU.size === 0 && <p className="text-sm text-gray-400">No data yet</p>}
          </div>
        </div>

        {/* By Status */}
        <div className={sectionClass}>
          <h3 className="mb-4 text-sm font-semibold uppercase tracking-wider text-gray-500 dark:text-gray-400">Pipeline by Status</h3>
          <div className="space-y-2">
            {Array.from(byStatus.entries()).map(([status, count]) => (
              <div key={status} className="flex items-center justify-between rounded-lg bg-gray-50 px-4 py-2 dark:bg-gray-700/50">
                <span className={`inline-flex rounded-full px-2.5 py-0.5 text-xs font-medium ${statusColor(status)}`}>
                  {status}
                </span>
                <span className="text-sm font-medium text-gray-900 dark:text-gray-100">{count}</span>
              </div>
            ))}
            {byStatus.size === 0 && <p className="text-sm text-gray-400">No data yet</p>}
          </div>
        </div>

        {/* By Type */}
        <div className={sectionClass}>
          <h3 className="mb-4 text-sm font-semibold uppercase tracking-wider text-gray-500 dark:text-gray-400">Projects by Type</h3>
          <div className="space-y-2">
            {Array.from(byType.entries()).sort((a, b) => b[1] - a[1]).map(([type, count]) => (
              <div key={type} className="flex items-center justify-between rounded-lg bg-gray-50 px-4 py-2 dark:bg-gray-700/50">
                <span className="text-sm text-gray-700 dark:text-gray-300">{type}</span>
                <span className="text-sm font-medium text-gray-900 dark:text-gray-100">{count}</span>
              </div>
            ))}
            {byType.size === 0 && <p className="text-sm text-gray-400">No data yet</p>}
          </div>
        </div>

        {/* By Buyer / IP Owner */}
        <div className={sectionClass}>
          <h3 className="mb-4 text-sm font-semibold uppercase tracking-wider text-gray-500 dark:text-gray-400">Projects by IP Owner</h3>
          <div className="space-y-2">
            {Array.from(byBuyer.entries()).sort((a, b) => b[1] - a[1]).map(([buyer, count]) => (
              <div key={buyer} className="flex items-center justify-between rounded-lg bg-gray-50 px-4 py-2 dark:bg-gray-700/50">
                <span className="text-sm text-gray-700 dark:text-gray-300">{buyer}</span>
                <span className="text-sm font-medium text-gray-900 dark:text-gray-100">{count}</span>
              </div>
            ))}
            {byBuyer.size === 0 && <p className="text-sm text-gray-400">No data yet</p>}
          </div>
        </div>
      </div>

      {/* Export buttons */}
      <div className="flex flex-wrap gap-4">
        <button onClick={exportEvents}
          className="flex items-center gap-2 rounded-lg bg-indigo-600 px-4 py-2 text-sm font-medium text-white hover:bg-indigo-700">
          <Download className="h-4 w-4" />
          Export Projects CSV
        </button>
        <button onClick={exportSavings}
          className="flex items-center gap-2 rounded-lg bg-green-600 px-4 py-2 text-sm font-medium text-white hover:bg-green-700">
          <Download className="h-4 w-4" />
          Export Savings CSV
        </button>
      </div>

      {/* Project pipeline table */}
      <div className="overflow-x-auto rounded-lg border border-gray-200 bg-white shadow-sm dark:border-gray-700 dark:bg-gray-800">
        <div className="flex items-center justify-between border-b border-gray-200 px-6 py-4 dark:border-gray-700">
          <h3 className="text-sm font-semibold text-gray-900 dark:text-gray-100">Sourcing Project Pipeline</h3>
          <div className="flex items-center gap-1 text-xs text-gray-400">
            <Filter className="h-3 w-3" /> {filteredEvents.length} of {sourcingEvents.length} projects
          </div>
        </div>

        {/* Filters */}
        <div className="flex flex-wrap gap-2 border-b border-gray-100 px-6 py-3 dark:border-gray-700">
          <select value={typeFilter} onChange={(e) => setTypeFilter(e.target.value)}
            className="rounded-lg border border-gray-300 px-3 py-1.5 text-xs dark:border-gray-600 dark:bg-gray-800 dark:text-gray-100">
            <option value="">All Types</option>
            {Array.from(byType.keys()).sort().map(t => <option key={t} value={t}>{t}</option>)}
          </select>
          <select value={statusFilter} onChange={(e) => setStatusFilter(e.target.value)}
            className="rounded-lg border border-gray-300 px-3 py-1.5 text-xs dark:border-gray-600 dark:bg-gray-800 dark:text-gray-100">
            <option value="">All Statuses</option>
            {Array.from(byStatus.keys()).sort().map(s => <option key={s} value={s}>{s}</option>)}
          </select>
          <select value={buFilter} onChange={(e) => setBuFilter(e.target.value)}
            className="rounded-lg border border-gray-300 px-3 py-1.5 text-xs dark:border-gray-600 dark:bg-gray-800 dark:text-gray-100">
            <option value="">All Business Units</option>
            {businessUnits.map(bu => <option key={bu} value={bu}>{bu}</option>)}
          </select>
        </div>

        <table className="w-full min-w-[900px]">
          <thead>
            <tr className="border-b border-gray-200 bg-gray-50 dark:border-gray-700 dark:bg-gray-900/50">
              <th className="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-gray-500 dark:text-gray-400">Project</th>
              <th className="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-gray-500 dark:text-gray-400">Type</th>
              <th className="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-gray-500 dark:text-gray-400">IP Owner</th>
              <th className="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-gray-500 dark:text-gray-400">Business Unit</th>
              <th className="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-gray-500 dark:text-gray-400">Supplier</th>
              <th className="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-gray-500 dark:text-gray-400">Due Date</th>
              <th className="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-gray-500 dark:text-gray-400">Status</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-gray-200 dark:divide-gray-700">
            {filteredEvents.length === 0 ? (
              <tr><td colSpan={7} className="px-4 py-8 text-center text-sm text-gray-500 dark:text-gray-400">No projects match the current filters</td></tr>
            ) : (
              filteredEvents.map((e) => (
                <tr key={e.id} className="hover:bg-gray-50 dark:hover:bg-gray-700/50">
                  <td className="px-4 py-3 text-sm font-medium text-gray-900 dark:text-gray-100">{e.event_name}</td>
                  <td className="px-4 py-3 text-sm text-gray-600 dark:text-gray-400">{e.event_type}</td>
                  <td className="px-4 py-3 text-sm text-gray-600 dark:text-gray-400">{e.buyer_name || '—'}</td>
                  <td className="px-4 py-3 text-sm text-gray-600 dark:text-gray-400">{getFirst(e.business_unit)?.business_unit_name || '—'}</td>
                  <td className="px-4 py-3 text-sm text-gray-600 dark:text-gray-400">{getFirst(e.awarded_supplier)?.supplier_name || getFirst(e.incumbent_supplier)?.supplier_name || '—'}</td>
                  <td className="px-4 py-3 text-sm text-gray-600 dark:text-gray-400">{formatDate(e.event_close_date)}</td>
                  <td className="px-4 py-3">
                    <span className={`inline-flex rounded-full px-2.5 py-0.5 text-xs font-medium ${statusColor(e.event_status)}`}>
                      {e.event_status}
                    </span>
                  </td>
                </tr>
              ))
            )}
          </tbody>
        </table>
      </div>

      {/* Savings calculations table */}
      <div className="overflow-x-auto rounded-lg border border-gray-200 bg-white shadow-sm dark:border-gray-700 dark:bg-gray-800">
        <div className="border-b border-gray-200 px-6 py-4 dark:border-gray-700">
          <h3 className="text-sm font-semibold text-gray-900 dark:text-gray-100">Savings Calculations</h3>
        </div>
        <table className="w-full min-w-[900px]">
          <thead>
            <tr className="border-b border-gray-200 bg-gray-50 dark:border-gray-700 dark:bg-gray-900/50">
              <th className="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-gray-500 dark:text-gray-400">Event</th>
              <th className="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-gray-500 dark:text-gray-400">Type</th>
              <th className="px-4 py-3 text-right text-xs font-semibold uppercase tracking-wider text-gray-500 dark:text-gray-400">Cost Reduction</th>
              <th className="px-4 py-3 text-right text-xs font-semibold uppercase tracking-wider text-gray-500 dark:text-gray-400">Cost Avoidance</th>
              <th className="px-4 py-3 text-right text-xs font-semibold uppercase tracking-wider text-gray-500 dark:text-gray-400">Total</th>
              <th className="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-gray-500 dark:text-gray-400">Period</th>
              <th className="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-gray-500 dark:text-gray-400">Classification</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-gray-200 dark:divide-gray-700">
            {savingsCalcs.length === 0 ? (
              <tr><td colSpan={7} className="px-4 py-8 text-center text-sm text-gray-500 dark:text-gray-400">No savings calculations yet</td></tr>
            ) : (
              savingsCalcs.map((c) => {
                const isRealized = c.savings_start_date && new Date(c.savings_start_date) <= now
                return (
                  <tr key={c.id} className="hover:bg-gray-50 dark:hover:bg-gray-700/50">
                    <td className="px-4 py-3 text-sm text-gray-900 dark:text-gray-100">{getFirst(c.event)?.event_name || '—'}</td>
                    <td className="px-4 py-3">
                      <span className="rounded bg-gray-100 px-2 py-0.5 text-xs text-gray-700 dark:bg-gray-700 dark:text-gray-300">{c.savings_type}</span>
                    </td>
                    <td className="px-4 py-3 text-right text-sm font-medium text-red-600 dark:text-red-400">{formatCurrency(c.cost_reduction_amount)}</td>
                    <td className="px-4 py-3 text-right text-sm font-medium text-amber-600 dark:text-amber-400">{formatCurrency(c.cost_avoidance_amount)}</td>
                    <td className="px-4 py-3 text-right text-sm font-bold text-green-600 dark:text-green-400">{formatCurrency(c.gross_savings_amount)}</td>
                    <td className="px-4 py-3 text-sm text-gray-600 dark:text-gray-400">
                      {c.savings_start_date ? `${formatDate(c.savings_start_date)} → ${formatDate(c.savings_end_date)}` : '—'}
                    </td>
                    <td className="px-4 py-3">
                      <span className={`rounded px-2 py-0.5 text-xs font-medium ${isRealized ? 'bg-emerald-100 text-emerald-700 dark:bg-emerald-900/30 dark:text-emerald-400' : 'bg-blue-100 text-blue-700 dark:bg-blue-900/30 dark:text-blue-400'}`}>
                        {isRealized ? 'Realized' : 'Accrued'}
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