#!/bin/bash

# Create dashboard chart components
cat > components/dashboard-stats.tsx << 'EOF'
'use client'

import { formatCurrency } from '@/lib/utils'
import { DollarSign, Briefcase, TrendingUp, TrendingDown, AlertTriangle } from 'lucide-react'
import { clsx } from 'clsx'

type Stats = {
  totalSavings: number
  activeEvents: number
  realizedSavings: number
  pipelineSavings: number
  leakage: number
  financeValidated: number
}

export function DashboardStats({ stats }: { stats: Stats }) {
  const cards = [
    { label: 'Total Gross Savings', value: formatCurrency(stats.totalSavings), icon: DollarSign, color: 'text-green-600', bg: 'bg-green-50' },
    { label: 'Active Events', value: stats.activeEvents.toString(), icon: Briefcase, color: 'text-indigo-600', bg: 'bg-indigo-50' },
    { label: 'Realized Savings', value: formatCurrency(stats.realizedSavings), icon: TrendingUp, color: 'text-blue-600', bg: 'bg-blue-50' },
    { label: 'Pipeline Value', value: formatCurrency(stats.pipelineSavings), icon: DollarSign, color: 'text-purple-600', bg: 'bg-purple-50' },
    { label: 'Finance Validated', value: formatCurrency(stats.financeValidated), icon: TrendingUp, color: 'text-emerald-600', bg: 'bg-emerald-50' },
    { label: 'Leakage', value: formatCurrency(stats.leakage), icon: AlertTriangle, color: 'text-red-600', bg: 'bg-red-50' },
  ]

  return (
    <div className="grid grid-cols-2 gap-4 lg:grid-cols-3">
      {cards.map((card) => {
        const Icon = card.icon
        return (
          <div key={card.label} className="rounded-lg border border-gray-200 bg-white p-6 shadow-sm">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm font-medium text-gray-500">{card.label}</p>
                <p className="mt-2 text-2xl font-bold text-gray-900">{card.value}</p>
              </div>
              <div className={clsx('flex h-12 w-12 items-center justify-center rounded-lg', card.bg)}>
                <Icon className={clsx('h-6 w-6', card.color)} />
              </div>
            </div>
          </div>
        )
      })}
    </div>
  )
}
EOF

cat > components/dashboard-charts.tsx << 'EOF'
'use client'

import {
  BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer,
  PieChart, Pie, Cell, Legend,
} from 'recharts'
import { formatCurrency } from '@/lib/utils'

const COLORS = ['#6366f1', '#10b981', '#f59e0b', '#ef4444', '#8b5cf6', '#ec4899', '#06b6d4', '#84cc16']

export function SavingsByCategoryChart({ data }: { data: { name: string; value: number }[] }) {
  if (!data || data.length === 0) {
    return <EmptyChart message="No savings data by category yet" />
  }
  return (
    <div className="rounded-lg border border-gray-200 bg-white p-6 shadow-sm">
      <h3 className="mb-4 text-sm font-semibold uppercase tracking-wider text-gray-500">Savings by Category</h3>
      <ResponsiveContainer width="100%" height={300}>
        <BarChart data={data} margin={{ top: 10, right: 10, left: 0, bottom: 0 }}>
          <CartesianGrid strokeDasharray="3 3" stroke="#f3f4f6" />
          <XAxis dataKey="name" tick={{ fontSize: 11 }} interval={0} angle={-20} textAnchor="end" height={60} />
          <YAxis tick={{ fontSize: 11 }} tickFormatter={(v) => `$${(v / 1000).toFixed(0)}k`} />
          <Tooltip formatter={(v: number) => formatCurrency(v)} />
          <Bar dataKey="value" fill="#6366f1" radius={[4, 4, 0, 0]} />
        </BarChart>
      </ResponsiveContainer>
    </div>
  )
}

export function EventsByStatusChart({ data }: { data: { name: string; value: number }[] }) {
  if (!data || data.length === 0) {
    return <EmptyChart message="No events data yet" />
  }
  return (
    <div className="rounded-lg border border-gray-200 bg-white p-6 shadow-sm">
      <h3 className="mb-4 text-sm font-semibold uppercase tracking-wider text-gray-500">Events by Status</h3>
      <ResponsiveContainer width="100%" height={300}>
        <PieChart>
          <Pie
            data={data}
            cx="50%"
            cy="50%"
            labelLine={false}
            label={({ name, value }: any) => `${name}: ${value}`}
            outerRadius={80}
            fill="#8884d8"
            dataKey="value"
          >
            {data.map((_, index) => (
              <Cell key={`cell-${index}`} fill={COLORS[index % COLORS.length]} />
            ))}
          </Pie>
          <Tooltip />
        </PieChart>
      </ResponsiveContainer>
    </div>
  )
}

export function SavingsByTypeChart({ data }: { data: { name: string; value: number }[] }) {
  if (!data || data.length === 0) {
    return <EmptyChart message="No savings type data yet" />
  }
  return (
    <div className="rounded-lg border border-gray-200 bg-white p-6 shadow-sm">
      <h3 className="mb-4 text-sm font-semibold uppercase tracking-wider text-gray-500">Savings by Type</h3>
      <ResponsiveContainer width="100%" height={300}>
        <BarChart data={data} layout="vertical" margin={{ top: 10, right: 10, left: 80, bottom: 0 }}>
          <CartesianGrid strokeDasharray="3 3" stroke="#f3f4f6" />
          <XAxis type="number" tick={{ fontSize: 11 }} tickFormatter={(v) => `$${(v / 1000).toFixed(0)}k`} />
          <YAxis type="category" dataKey="name" tick={{ fontSize: 11 }} width={100} />
          <Tooltip formatter={(v: number) => formatCurrency(v)} />
          <Bar dataKey="value" fill="#10b981" radius={[0, 4, 4, 0]} />
        </BarChart>
      </ResponsiveContainer>
    </div>
  )
}

export function SavingsTrendChart({ data }: { data: { name: string; projected: number; realized: number }[] }) {
  if (!data || data.length === 0) {
    return <EmptyChart message="No trend data yet" />
  }
  return (
    <div className="rounded-lg border border-gray-200 bg-white p-6 shadow-sm">
      <h3 className="mb-4 text-sm font-semibold uppercase tracking-wider text-gray-500">Savings Trend by Quarter</h3>
      <ResponsiveContainer width="100%" height={300}>
        <BarChart data={data} margin={{ top: 10, right: 10, left: 0, bottom: 0 }}>
          <CartesianGrid strokeDasharray="3 3" stroke="#f3f4f6" />
          <XAxis dataKey="name" tick={{ fontSize: 11 }} />
          <YAxis tick={{ fontSize: 11 }} tickFormatter={(v) => `$${(v / 1000).toFixed(0)}k`} />
          <Tooltip formatter={(v: number) => formatCurrency(v)} />
          <Bar dataKey="projected" fill="#c7d2fe" radius={[4, 4, 0, 0]} />
          <Bar dataKey="realized" fill="#10b981" radius={[4, 4, 0, 0]} />
        </BarChart>
      </ResponsiveContainer>
    </div>
  )
}

function EmptyChart({ message }: { message: string }) {
  return (
    <div className="rounded-lg border border-gray-200 bg-white p-6 shadow-sm">
      <h3 className="mb-4 text-sm font-semibold uppercase tracking-wider text-gray-500">Chart</h3>
      <div className="flex h-[300px] items-center justify-center text-sm text-gray-400">{message}</div>
    </div>
  )
}
EOF

# Replace the dashboard page with real data
cat > app/dashboard/page.tsx << 'EOF'
import { createClient } from '@/lib/supabase/server'
import { DashboardStats } from '@/components/dashboard-stats'
import { SavingsByCategoryChart, EventsByStatusChart, SavingsByTypeChart, SavingsTrendChart } from '@/components/dashboard-charts'
import Link from 'next/link'

export default async function DashboardPage() {
  const supabase = await createClient()

  // Fetch all data in parallel
  const [
    { data: events },
    { data: savingsCalcs },
    { data: realizationPeriods },
  ] = await Promise.all([
    supabase.from('sourcing_events').select('id, event_name, event_status, category:categories(category_name)'),
    supabase.from('savings_calculations').select('id, savings_type, gross_savings_amount, finance_validated, current_year_recognized_amount, event_id'),
    supabase.from('realization_periods').select('id, projected_savings, realized_savings, leakage_amount, period_name'),
  ])

  // Calculate stats
  const totalSavings = (savingsCalcs || []).reduce((sum, c) => sum + (c.gross_savings_amount || 0), 0)
  const activeEvents = (events || []).filter(e => !['Closed', 'Cancelled', 'Rejected'].includes(e.event_status)).length
  const realizedSavings = (realizationPeriods || []).reduce((sum, p) => sum + (p.realized_savings || 0), 0)
  const leakage = (realizationPeriods || []).reduce((sum, p) => sum + (p.leakage_amount || 0), 0)
  const financeValidated = (savingsCalcs || []).filter(c => c.finance_validated).reduce((sum, c) => sum + (c.gross_savings_amount || 0), 0)
  const pipelineSavings = (savingsCalcs || []).reduce((sum, c) => sum + ((c.gross_savings_amount || 0) - (c.current_year_recognized_amount || 0)), 0)

  // Savings by Category
  const savingsByCategoryMap = new Map<string, number>()
  for (const calc of savingsCalcs || []) {
    const event = events?.find(e => e.id === calc.event_id)
    const catName = event?.category?.category_name || 'Uncategorized'
    savingsByCategoryMap.set(catName, (savingsByCategoryMap.get(catName) || 0) + (calc.gross_savings_amount || 0))
  }
  const savingsByCategory = Array.from(savingsByCategoryMap.entries())
    .map(([name, value]) => ({ name, value }))
    .sort((a, b) => b.value - a.value)
    .slice(0, 8)

  // Events by Status
  const statusMap = new Map<string, number>()
  for (const event of events || []) {
    statusMap.set(event.event_status, (statusMap.get(event.event_status) || 0) + 1)
  }
  const eventsByStatus = Array.from(statusMap.entries()).map(([name, value]) => ({ name, value }))

  // Savings by Type
  const typeMap = new Map<string, number>()
  for (const calc of savingsCalcs || []) {
    typeMap.set(calc.savings_type, (typeMap.get(calc.savings_type) || 0) + (calc.gross_savings_amount || 0))
  }
  const savingsByType = Array.from(typeMap.entries()).map(([name, value]) => ({ name, value }))

  // Savings Trend by Quarter (from realization periods)
  const trendMap = new Map<string, { projected: number; realized: number }>()
  for (const period of realizationPeriods || []) {
    const existing = trendMap.get(period.period_name) || { projected: 0, realized: 0 }
    trendMap.set(period.period_name, {
      projected: existing.projected + (period.projected_savings || 0),
      realized: existing.realized + (period.realized_savings || 0),
    })
  }
  const savingsTrend = Array.from(trendMap.entries()).map(([name, values]) => ({ name, ...values }))

  return (
    <div className="p-8">
      <div className="mb-6">
        <h1 className="text-2xl font-bold text-gray-900">Dashboard</h1>
        <p className="mt-1 text-sm text-gray-600">
          Procurement value overview — savings, pipeline, and realization
        </p>
      </div>

      {/* Stats Cards */}
      <DashboardStats stats={{
        totalSavings,
        activeEvents,
        realizedSavings,
        pipelineSavings,
        leakage,
        financeValidated,
      }} />

      {/* Charts */}
      <div className="mt-6 grid grid-cols-1 gap-6 lg:grid-cols-2">
        <SavingsByCategoryChart data={savingsByCategory} />
        <EventsByStatusChart data={eventsByStatus} />
        <SavingsByTypeChart data={savingsByType} />
        <SavingsTrendChart data={savingsTrend} />
      </div>

      {/* Recent Events */}
      <div className="mt-6 rounded-lg border border-gray-200 bg-white p-6 shadow-sm">
        <div className="mb-4 flex items-center justify-between">
          <h3 className="text-sm font-semibold uppercase tracking-wider text-gray-500">Recent Events</h3>
          <Link href="/events" className="text-sm font-medium text-indigo-600 hover:text-indigo-800">
            View all →
          </Link>
        </div>
        <div className="space-y-2">
          {(events || []).slice(0, 5).map((event: any) => (
            <Link key={event.id} href={`/events/${event.id}`}
              className="flex items-center justify-between rounded-lg border border-gray-100 px-4 py-3 hover:bg-gray-50">
              <div>
                <p className="text-sm font-medium text-gray-900">{event.event_name}</p>
                <p className="text-xs text-gray-500">{event.category?.category_name || '—'}</p>
              </div>
              <span className="text-xs text-gray-500">{event.event_status}</span>
            </Link>
          ))}
        </div>
      </div>
    </div>
  )
}
EOF

# Create Reports page with CSV export
cat > app/reports/page.tsx << 'EOF'
import { createClient } from '@/lib/supabase/server'
import { ReportsView } from '@/components/reports-view'

export default async function ReportsPage() {
  const supabase = await createClient()

  const { data: events } = await supabase
    .from('sourcing_events')
    .select(`
      id, event_name, event_type, event_status,
      category:categories(category_name),
      business_unit:business_units(business_unit_name),
      incumbent_supplier:suppliers!sourcing_events_incumbent_supplier_id_fkey(supplier_name),
      awarded_supplier:suppliers!sourcing_events_awarded_supplier_id_fkey(supplier_name),
      contract_start_date, contract_end_date
    `)
    .order('created_at', { ascending: false })

  const { data: savingsCalcs } = await supabase
    .from('savings_calculations')
    .select(`
      id, calculation_name, savings_type, gross_savings_amount, savings_percentage,
      calculation_status, finance_validated, current_year_recognized_amount,
      event:sourcing_events(event_name),
      baseline:baselines(baseline_name),
      award:awards(award_name)
    `)
    .order('created_at', { ascending: false })

  return (
    <div className="p-8">
      <h1 className="text-2xl font-bold text-gray-900">Reports</h1>
      <p className="mt-1 text-sm text-gray-600">Export procurement data to CSV</p>
      <ReportsView events={events || []} savingsCalcs={savingsCalcs || []} />
    </div>
  )
}
EOF

cat > components/reports-view.tsx << 'EOF'
'use client'

import { Download, FileText, DollarSign } from 'lucide-react'
import { formatCurrency, formatDate } from '@/lib/utils'

type EventRow = {
  id: string
  event_name: string
  event_type: string
  event_status: string
  category: { category_name: string } | null
  business_unit: { business_unit_name: string } | null
  incumbent_supplier: { supplier_name: string } | null
  awarded_supplier: { supplier_name: string } | null
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
  event: { event_name: string } | null
  baseline: { baseline_name: string } | null
  award: { award_name: string } | null
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
      e.category?.category_name || '', e.business_unit?.business_unit_name || '',
      e.incumbent_supplier?.supplier_name || '', e.awarded_supplier?.supplier_name || '',
      e.contract_start_date || '', e.contract_end_date || '',
    ])]
    downloadCSV('sourcing_events.csv', rows)
  }

  const exportSavings = () => {
    const headers = ['Event', 'Calculation Name', 'Savings Type', 'Baseline', 'Award', 'Gross Savings', 'Savings %', 'Status', 'Finance Validated', 'Current-Year Recognized']
    const rows = [headers, ...savingsCalcs.map(c => [
      c.event?.event_name || '', c.calculation_name, c.savings_type,
      c.baseline?.baseline_name || '', c.award?.award_name || '',
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
      {/* Summary Stats */}
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

      {/* Export Buttons */}
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

      {/* Recent Savings Table */}
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
                    <td className="px-4 py-3 text-sm text-gray-900">{calc.event?.event_name || '—'}</td>
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
EOF

# Clear build cache
rm -rf .next

echo "DONE"
