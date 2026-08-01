#!/bin/bash

# Fix reports-view.tsx — update types to accept arrays
cat > components/reports-view.tsx << 'EOF'
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
EOF

# Fix events-list.tsx — update types to accept arrays
cat > components/events-list.tsx << 'EOF'
'use client'

import { useState, useMemo } from 'react'
import Link from 'next/link'
import { Search, Briefcase } from 'lucide-react'
import { formatCurrency, formatDate, statusColor } from '@/lib/utils'

type EventRow = {
  id: string
  event_name: string
  event_type: string
  event_status: string
  event_close_date: string | null
  contract_start_date: string | null
  contract_end_date: string | null
  category: any
  business_unit: any
  incumbent_supplier: any
  awarded_supplier: any
}

function getFirst(obj: any): any {
  if (!obj) return null
  if (Array.isArray(obj)) return obj[0] || null
  return obj
}

const EVENT_STATUSES = [
  'Pipeline', 'Scoped', 'Baseline Pending', 'Baseline Approved',
  'In Market', 'Negotiation', 'Award Recommended', 'Award Approved',
  'Contracted', 'Implemented', 'Realized', 'Finance Validated',
  'Closed', 'Cancelled', 'Rejected'
]

const EVENT_TYPES = [
  'Renewal', 'Competitive Rebid', 'Net New Purchase', 'Renegotiation',
  'Demand Reduction', 'Specification Change', 'Supplier Consolidation',
  'Market Index / Commodity', 'Payment Terms', 'Rebate / Credit',
  'One-Time Fee Waiver', 'Early Payment Discount', 'TCO Improvement',
  'Productivity Improvement'
]

export function EventsList({ events }: { events: EventRow[] }) {
  const [search, setSearch] = useState('')
  const [statusFilter, setStatusFilter] = useState('')
  const [typeFilter, setTypeFilter] = useState('')

  const filteredEvents = useMemo(() => {
    return events.filter((event) => {
      const matchesSearch = event.event_name.toLowerCase().includes(search.toLowerCase())
      const matchesStatus = !statusFilter || event.event_status === statusFilter
      const matchesType = !typeFilter || event.event_type === typeFilter
      return matchesSearch && matchesStatus && matchesType
    })
  }, [events, search, statusFilter, typeFilter])

  return (
    <div className="mt-6">
      <div className="mb-4 flex flex-wrap gap-3">
        <div className="relative flex-1 min-w-[200px]">
          <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-gray-400" />
          <input
            type="text"
            placeholder="Search events..."
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            className="w-full rounded-lg border border-gray-300 pl-10 pr-3 py-2 text-sm focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500"
          />
        </div>
        <select
          value={statusFilter}
          onChange={(e) => setStatusFilter(e.target.value)}
          className="rounded-lg border border-gray-300 px-3 py-2 text-sm focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500"
        >
          <option value="">All Statuses</option>
          {EVENT_STATUSES.map((status) => (
            <option key={status} value={status}>{status}</option>
          ))}
        </select>
        <select
          value={typeFilter}
          onChange={(e) => setTypeFilter(e.target.value)}
          className="rounded-lg border border-gray-300 px-3 py-2 text-sm focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500"
        >
          <option value="">All Types</option>
          {EVENT_TYPES.map((type) => (
            <option key={type} value={type}>{type}</option>
          ))}
        </select>
      </div>

      <div className="overflow-hidden rounded-lg border border-gray-200 bg-white shadow-sm">
        <table className="w-full">
          <thead>
            <tr className="border-b border-gray-200 bg-gray-50">
              <th className="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-gray-500">Event Name</th>
              <th className="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-gray-500">Type</th>
              <th className="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-gray-500">Category</th>
              <th className="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-gray-500">Business Unit</th>
              <th className="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-gray-500">Supplier</th>
              <th className="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-gray-500">Status</th>
              <th className="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-gray-500">Contract</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-gray-200">
            {filteredEvents.length === 0 ? (
              <tr>
                <td colSpan={7} className="px-4 py-12 text-center">
                  <Briefcase className="mx-auto mb-2 h-8 w-8 text-gray-400" />
                  <p className="text-sm text-gray-500">No events found</p>
                </td>
              </tr>
            ) : (
              filteredEvents.map((event) => (
                <tr key={event.id} className="hover:bg-gray-50">
                  <td className="px-4 py-3">
                    <Link href={`/events/${event.id}`} className="text-sm font-medium text-indigo-600 hover:text-indigo-800">
                      {event.event_name}
                    </Link>
                  </td>
                  <td className="px-4 py-3 text-sm text-gray-600">{event.event_type}</td>
                  <td className="px-4 py-3 text-sm text-gray-600">
                    {getFirst(event.category)?.category_name || '—'}
                  </td>
                  <td className="px-4 py-3 text-sm text-gray-600">
                    {getFirst(event.business_unit)?.business_unit_name || '—'}
                  </td>
                  <td className="px-4 py-3 text-sm text-gray-600">
                    {getFirst(event.awarded_supplier)?.supplier_name || getFirst(event.incumbent_supplier)?.supplier_name || '—'}
                  </td>
                  <td className="px-4 py-3">
                    <span className={`inline-flex rounded-full px-2.5 py-0.5 text-xs font-medium ${statusColor(event.event_status)}`}>
                      {event.event_status}
                    </span>
                  </td>
                  <td className="px-4 py-3 text-sm text-gray-600">
                    {event.contract_start_date ? `${formatDate(event.contract_start_date)} → ${formatDate(event.contract_end_date)}` : '—'}
                  </td>
                </tr>
              ))
            )}
          </tbody>
        </table>
      </div>

      <p className="mt-4 text-sm text-gray-500">
        Showing {filteredEvents.length} of {events.length} events
      </p>
    </div>
  )
}
EOF

# Fix event-detail.tsx — update types to accept arrays
cat > components/event-detail.tsx << 'EOF'
'use client'

import { useState } from 'react'
import {
  FileText, List, BarChart2, Users, FileCheck,
  Calculator, TrendingUp, FolderKanban, Clock, CheckCircle,
} from 'lucide-react'
import { clsx } from 'clsx'
import { formatDate, statusColor } from '@/lib/utils'
import { ScopeLinesTab } from './scope-lines-tab'
import { BaselinesTab } from './baselines-tab'
import { OffersTab } from './offers-tab'
import { CalculationsTab } from './calculations-tab'
import { RealizationTab } from './realization-tab'

function getFirst(obj: any): any {
  if (!obj) return null
  if (Array.isArray(obj)) return obj[0] || null
  return obj
}

type Event = {
  id: string
  event_name: string
  event_description: string | null
  event_type: string
  sourcing_method: string | null
  event_status: string
  event_start_date: string | null
  event_close_date: string | null
  contract_start_date: string | null
  contract_end_date: string | null
  recognition_start_date: string | null
  recognition_end_date: string | null
  official_reporting_basis: string | null
  currency_code: string
  category: any
  business_unit: any
  cost_center: any
  incumbent_supplier: any
  awarded_supplier: any
}

const TABS = [
  { id: 'overview', label: 'Overview', icon: FileText },
  { id: 'scope', label: 'Scope Lines', icon: List },
  { id: 'baselines', label: 'Baselines', icon: BarChart2 },
  { id: 'offers', label: 'Supplier Offers', icon: Users },
  { id: 'awards', label: 'Awards', icon: FileCheck },
  { id: 'calculations', label: 'Calculations', icon: Calculator },
  { id: 'realization', label: 'Realization', icon: TrendingUp },
]

export function EventDetail({
  event,
  scopeLines,
  suppliers,
}: {
  event: Event
  scopeLines: any[]
  suppliers: any[]
}) {
  const [activeTab, setActiveTab] = useState('overview')

  return (
    <div>
      <div className="mb-6">
        <div className="flex items-start justify-between">
          <div>
            <h1 className="text-2xl font-bold text-gray-900">{event.event_name}</h1>
            <p className="mt-1 text-sm text-gray-600">
              {event.event_type} • {event.sourcing_method || '—'}
            </p>
          </div>
          <span className={clsx('inline-flex rounded-full px-3 py-1 text-sm font-medium', statusColor(event.event_status))}>
            {event.event_status}
          </span>
        </div>
        {event.event_description && (
          <p className="mt-3 text-sm text-gray-600">{event.event_description}</p>
        )}
      </div>

      <div className="border-b border-gray-200">
        <nav className="flex gap-1 overflow-x-auto">
          {TABS.map((tab) => {
            const Icon = tab.icon
            return (
              <button key={tab.id} onClick={() => setActiveTab(tab.id)}
                className={clsx(
                  'flex items-center gap-2 border-b-2 px-4 py-3 text-sm font-medium transition-colors whitespace-nowrap',
                  activeTab === tab.id
                    ? 'border-indigo-600 text-indigo-600'
                    : 'border-transparent text-gray-500 hover:text-gray-700'
                )}>
                <Icon className="h-4 w-4" />
                {tab.label}
              </button>
            )
          })}
        </nav>
      </div>

      <div className="mt-6">
        {activeTab === 'overview' && <OverviewTab event={event} />}
        {activeTab === 'scope' && <ScopeLinesTab eventId={event.id} scopeLines={scopeLines} />}
        {activeTab === 'baselines' && <BaselinesTab eventId={event.id} scopeLines={scopeLines} />}
        {activeTab === 'offers' && <OffersTab eventId={event.id} scopeLines={scopeLines} suppliers={suppliers} />}
        {activeTab === 'awards' && <AwardsTab eventId={event.id} />}
        {activeTab === 'calculations' && <CalculationsTab eventId={event.id} />}
        {activeTab === 'realization' && <RealizationTab eventId={event.id} />}
      </div>
    </div>
  )
}

function OverviewTab({ event }: { event: Event }) {
  const details = [
    { label: 'Category', value: getFirst(event.category)?.category_name },
    { label: 'Business Unit', value: getFirst(event.business_unit)?.business_unit_name },
    { label: 'Cost Center', value: getFirst(event.cost_center)?.cost_center_name },
    { label: 'Incumbent Supplier', value: getFirst(event.incumbent_supplier)?.supplier_name },
    { label: 'Awarded Supplier', value: getFirst(event.awarded_supplier)?.supplier_name },
    { label: 'Currency', value: event.currency_code },
    { label: 'Reporting Basis', value: event.official_reporting_basis },
  ]

  const dates = [
    { label: 'Event Start', value: event.event_start_date },
    { label: 'Event Close', value: event.event_close_date },
    { label: 'Contract Start', value: event.contract_start_date },
    { label: 'Contract End', value: event.contract_end_date },
    { label: 'Recognition Start', value: event.recognition_start_date },
    { label: 'Recognition End', value: event.recognition_end_date },
  ]

  return (
    <div className="grid grid-cols-1 gap-6 md:grid-cols-2">
      <div className="rounded-lg border border-gray-200 bg-white p-6 shadow-sm">
        <h3 className="mb-4 text-sm font-semibold uppercase tracking-wider text-gray-500">Event Details</h3>
        <dl className="space-y-3">
          {details.map((d) => (
            <div key={d.label} className="flex justify-between">
              <dt className="text-sm text-gray-600">{d.label}</dt>
              <dd className="text-sm font-medium text-gray-900">{d.value || '—'}</dd>
            </div>
          ))}
        </dl>
      </div>
      <div className="rounded-lg border border-gray-200 bg-white p-6 shadow-sm">
        <h3 className="mb-4 text-sm font-semibold uppercase tracking-wider text-gray-500">Key Dates</h3>
        <dl className="space-y-3">
          {dates.map((d) => (
            <div key={d.label} className="flex justify-between">
              <dt className="flex items-center gap-2 text-sm text-gray-600">
                <Clock className="h-3 w-3" />
                {d.label}
              </dt>
              <dd className="text-sm font-medium text-gray-900">{formatDate(d.value)}</dd>
            </div>
          ))}
        </dl>
      </div>
    </div>
  )
}

function AwardsTab({ eventId }: { eventId: string }) {
  return (
    <div className="rounded-lg border border-gray-200 bg-white p-12 text-center shadow-sm">
      <FileCheck className="mx-auto mb-3 h-10 w-10 text-gray-300" />
      <h3 className="text-lg font-medium text-gray-900">Awards</h3>
      <p className="mt-1 text-sm text-gray-500">
        Create awards from the Supplier Offers tab by expanding an offer and clicking "Create Award from Offer."
      </p>
    </div>
  )
}
EOF

echo "DONE"
