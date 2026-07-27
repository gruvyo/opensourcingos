'use client'

import { useState, useMemo } from 'react'
import { Download, DollarSign, Briefcase, TrendingUp, Filter } from 'lucide-react'
import { formatCurrency, formatDate, statusColor } from '@/lib/utils'
import { portfolioRollup, classifyRealization } from '@/lib/savings'
import { Card } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { Select } from '@/components/ui/input'

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
  event_id: string | null
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

  // Savings figures — single source of truth (lib/savings), scoped to sourcing projects.
  // byBusinessUnit here attributes savings to events by event_id (the old code matched
  // by event_name, which mis-attributed whenever two events shared a name).
  const now = new Date()
  const rollup = portfolioRollup(savingsCalcs as any, sourcingEvents as any, { now })
  const totalSavings = rollup.totalSavings
  const totalCostReduction = rollup.totalCostReduction
  const totalCostAvoidance = rollup.totalCostAvoidance

  // For CSV realized/accrued classification, use the SAME canonical rule.
  const contractStartByEventId = new Map<string, string | null>()
  for (const e of events) contractStartByEventId.set(e.id, e.contract_start_date ?? null)

  // By status (project counts)
  const byStatus = new Map<string, number>()
  for (const e of sourcingEvents) {
    byStatus.set(e.event_status, (byStatus.get(e.event_status) || 0) + 1)
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
    const headers = ['Project Name', 'Type', 'Status', 'Owner', 'Category', 'Business Unit', 'Supplier', 'Event Start', 'Due Date', 'Contract Start', 'Contract End']
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
      const isRealized = classifyRealization(c as any, contractStartByEventId, now) === 'Realized'
      return [
        getFirst(c.event)?.event_name || '', c.calculation_name, c.savings_type,
        (c.cost_reduction_amount || 0).toString(), (c.cost_avoidance_amount || 0).toString(),
        (c.gross_savings_amount || 0).toString(), c.savings_percentage?.toFixed(2) || '',
        c.calculation_status,
        c.savings_start_date || '', c.savings_end_date || '',
        isRealized ? 'Realized' : 'Accrued',
      ]
    })]
    downloadCSV('savings_report.csv', rows)
  }

  const labelClass = 'text-sm font-medium text-[var(--text-3)]'
  const valueClass = 'mt-1 text-2xl font-bold'

  return (
    <div className="mt-6 space-y-6">
      {/* Savings breakdown */}
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-3">
        <Card className="p-6">
          <p className={labelClass}>Cost Reduction</p>
          <p className={`${valueClass} text-red-600 dark:text-red-400`}>{formatCurrency(totalCostReduction)}</p>
          <p className="mt-1 text-xs text-[var(--text-3)]">Actual bottom-line reduction — price went down from what we were paying</p>
        </Card>
        <Card className="p-6">
          <p className={labelClass}>Cost Avoidance</p>
          <p className={`${valueClass} text-amber-600 dark:text-amber-400`}>{formatCurrency(totalCostAvoidance)}</p>
          <p className="mt-1 text-xs text-[var(--text-3)]">Value not paid — negotiated below what supplier proposed</p>
        </Card>
        <Card className="p-6">
          <p className={labelClass}>Total Savings</p>
          <p className={`${valueClass} text-green-600 dark:text-green-400`}>{formatCurrency(totalSavings)}</p>
          <p className="mt-1 text-xs text-[var(--text-3)]">Cost reduction + cost avoidance combined</p>
        </Card>
      </div>

      {/* Activity breakdowns */}
      <div className="grid grid-cols-1 gap-6 lg:grid-cols-2">
        {/* By Business Unit */}
        <Card className="p-6">
          <h3 className="mb-4 text-sm font-semibold uppercase tracking-wider text-[var(--text-3)]">Projects by Business Unit</h3>
          <div className="space-y-2">
            {rollup.byBusinessUnit.map(({ name, value, count }) => (
              <div key={name} className="flex items-center justify-between rounded-lg bg-[var(--surface-2)] px-4 py-2">
                <span className="text-sm text-[var(--text-2)]">{name}</span>
                <div className="flex items-center gap-4">
                  <span className="text-xs text-[var(--text-3)]">{count} project{count !== 1 ? 's' : ''}</span>
                  <span className="text-sm font-medium text-[var(--text)]">{formatCurrency(value)}</span>
                </div>
              </div>
            ))}
            {rollup.byBusinessUnit.length === 0 && <p className="text-sm text-[var(--text-3)]">No data yet</p>}
          </div>
        </Card>

        {/* By Status */}
        <Card className="p-6">
          <h3 className="mb-4 text-sm font-semibold uppercase tracking-wider text-[var(--text-3)]">Pipeline by Status</h3>
          <div className="space-y-2">
            {Array.from(byStatus.entries()).map(([status, count]) => (
              <div key={status} className="flex items-center justify-between rounded-lg bg-[var(--surface-2)] px-4 py-2">
                <span className={`inline-flex rounded-full px-2.5 py-0.5 text-xs font-medium ${statusColor(status)}`}>
                  {status}
                </span>
                <span className="text-sm font-medium text-[var(--text)]">{count}</span>
              </div>
            ))}
            {byStatus.size === 0 && <p className="text-sm text-[var(--text-3)]">No data yet</p>}
          </div>
        </Card>

        {/* By Type */}
        <Card className="p-6">
          <h3 className="mb-4 text-sm font-semibold uppercase tracking-wider text-[var(--text-3)]">Projects by Type</h3>
          <div className="space-y-2">
            {Array.from(byType.entries()).sort((a, b) => b[1] - a[1]).map(([type, count]) => (
              <div key={type} className="flex items-center justify-between rounded-lg bg-[var(--surface-2)] px-4 py-2">
                <span className="text-sm text-[var(--text-2)]">{type}</span>
                <span className="text-sm font-medium text-[var(--text)]">{count}</span>
              </div>
            ))}
            {byType.size === 0 && <p className="text-sm text-[var(--text-3)]">No data yet</p>}
          </div>
        </Card>

        {/* By Owner / Buyer */}
        <Card className="p-6">
          <h3 className="mb-4 text-sm font-semibold uppercase tracking-wider text-[var(--text-3)]">Projects by Owner</h3>
          <div className="space-y-2">
            {Array.from(byBuyer.entries()).sort((a, b) => b[1] - a[1]).map(([buyer, count]) => (
              <div key={buyer} className="flex items-center justify-between rounded-lg bg-[var(--surface-2)] px-4 py-2">
                <span className="text-sm text-[var(--text-2)]">{buyer}</span>
                <span className="text-sm font-medium text-[var(--text)]">{count}</span>
              </div>
            ))}
            {byBuyer.size === 0 && <p className="text-sm text-[var(--text-3)]">No data yet</p>}
          </div>
        </Card>
      </div>

      {/* Export buttons */}
      <div className="flex flex-wrap gap-4">
        <Button onClick={exportEvents}>
          <Download className="h-4 w-4" />
          Export Projects CSV
        </Button>
        <button onClick={exportSavings}
          className="flex items-center gap-2 rounded-lg bg-green-600 px-4 py-2 text-sm font-medium text-white hover:bg-green-700">
          <Download className="h-4 w-4" />
          Export Savings CSV
        </button>
      </div>

      {/* Project pipeline table */}
      <Card className="overflow-x-auto">
        <div className="flex items-center justify-between border-b border-[var(--border)] px-6 py-4">
          <h3 className="text-sm font-semibold text-[var(--text)]">Sourcing Project Pipeline</h3>
          <div className="flex items-center gap-1 text-xs text-[var(--text-3)]">
            <Filter className="h-3 w-3" /> {filteredEvents.length} of {sourcingEvents.length} projects
          </div>
        </div>

        {/* Filters */}
        <div className="flex flex-wrap gap-2 border-b border-[var(--border)] px-6 py-3">
          <Select value={typeFilter} onChange={(e) => setTypeFilter(e.target.value)} className="px-3 py-1.5 text-xs">
            <option value="">All Types</option>
            {Array.from(byType.keys()).sort().map(t => <option key={t} value={t}>{t}</option>)}
          </Select>
          <Select value={statusFilter} onChange={(e) => setStatusFilter(e.target.value)} className="px-3 py-1.5 text-xs">
            <option value="">All Statuses</option>
            {Array.from(byStatus.keys()).sort().map(s => <option key={s} value={s}>{s}</option>)}
          </Select>
          <Select value={buFilter} onChange={(e) => setBuFilter(e.target.value)} className="px-3 py-1.5 text-xs">
            <option value="">All Business Units</option>
            {businessUnits.map(bu => <option key={bu} value={bu}>{bu}</option>)}
          </Select>
        </div>

        <table className="w-full min-w-[900px]">
          <thead>
            <tr className="border-b border-[var(--border)] bg-[var(--surface-2)]">
              <th className="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-[var(--text-3)]">Project</th>
              <th className="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-[var(--text-3)]">Type</th>
              <th className="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-[var(--text-3)]">Owner</th>
              <th className="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-[var(--text-3)]">Business Unit</th>
              <th className="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-[var(--text-3)]">Supplier</th>
              <th className="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-[var(--text-3)]">Due Date</th>
              <th className="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-[var(--text-3)]">Status</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-[var(--border)]">
            {filteredEvents.length === 0 ? (
              <tr><td colSpan={7} className="px-4 py-8 text-center text-sm text-[var(--text-3)]">No projects match the current filters</td></tr>
            ) : (
              filteredEvents.map((e) => (
                <tr key={e.id} className="hover:bg-[var(--surface-2)]">
                  <td className="px-4 py-3 text-sm font-medium text-[var(--text)]">{e.event_name}</td>
                  <td className="px-4 py-3 text-sm text-[var(--text-2)]">{e.event_type}</td>
                  <td className="px-4 py-3 text-sm text-[var(--text-2)]">{e.buyer_name || '—'}</td>
                  <td className="px-4 py-3 text-sm text-[var(--text-2)]">{getFirst(e.business_unit)?.business_unit_name || '—'}</td>
                  <td className="px-4 py-3 text-sm text-[var(--text-2)]">{getFirst(e.awarded_supplier)?.supplier_name || getFirst(e.incumbent_supplier)?.supplier_name || '—'}</td>
                  <td className="px-4 py-3 text-sm text-[var(--text-2)]">{formatDate(e.event_close_date)}</td>
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
      </Card>

      {/* Savings calculations table */}
      <Card className="overflow-x-auto">
        <div className="border-b border-[var(--border)] px-6 py-4">
          <h3 className="text-sm font-semibold text-[var(--text)]">Savings Calculations</h3>
        </div>
        <table className="w-full min-w-[900px]">
          <thead>
            <tr className="border-b border-[var(--border)] bg-[var(--surface-2)]">
              <th className="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-[var(--text-3)]">Event</th>
              <th className="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-[var(--text-3)]">Type</th>
              <th className="px-4 py-3 text-right text-xs font-semibold uppercase tracking-wider text-[var(--text-3)]">Cost Reduction</th>
              <th className="px-4 py-3 text-right text-xs font-semibold uppercase tracking-wider text-[var(--text-3)]">Cost Avoidance</th>
              <th className="px-4 py-3 text-right text-xs font-semibold uppercase tracking-wider text-[var(--text-3)]">Total</th>
              <th className="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-[var(--text-3)]">Period</th>
              <th className="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-[var(--text-3)]">Classification</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-[var(--border)]">
            {savingsCalcs.length === 0 ? (
              <tr><td colSpan={7} className="px-4 py-8 text-center text-sm text-[var(--text-3)]">No savings calculations yet</td></tr>
            ) : (
              savingsCalcs.map((c) => {
                const isRealized = classifyRealization(c as any, contractStartByEventId, now) === 'Realized'
                return (
                  <tr key={c.id} className="hover:bg-[var(--surface-2)]">
                    <td className="px-4 py-3 text-sm text-[var(--text)]">{getFirst(c.event)?.event_name || '—'}</td>
                    <td className="px-4 py-3">
                      <Badge tone="neutral" className="rounded px-2 py-0.5">{c.savings_type}</Badge>
                    </td>
                    <td className="px-4 py-3 text-right text-sm font-medium text-red-600 dark:text-red-400">{formatCurrency(c.cost_reduction_amount)}</td>
                    <td className="px-4 py-3 text-right text-sm font-medium text-amber-600 dark:text-amber-400">{formatCurrency(c.cost_avoidance_amount)}</td>
                    <td className="px-4 py-3 text-right text-sm font-bold text-green-600 dark:text-green-400">{formatCurrency(c.gross_savings_amount)}</td>
                    <td className="px-4 py-3 text-sm text-[var(--text-2)]">
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
      </Card>
    </div>
  )
}
