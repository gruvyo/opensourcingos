'use client'

import { useState, useMemo } from 'react'
import Link from 'next/link'
import { Search, Briefcase, LifeBuoy } from 'lucide-react'
import { formatCurrency, formatDate, statusColor } from '@/lib/utils'
import { clsx } from 'clsx'

type EventRow = {
  id: string
  event_name: string
  event_type: string
  event_status: string
  project_type: string | null
  buyer_name: string | null
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
  'Closed', 'Cancelled', 'Rejected',
  'Not Started', 'In Progress', 'Hold', 'Complete',
]

const EVENT_TYPES = [
  'Renewal', 'Competitive Rebid', 'Net New Purchase', 'Renegotiation',
  'Demand Reduction', 'Specification Change', 'Supplier Consolidation',
  'Market Index / Commodity', 'Payment Terms', 'Rebate / Credit',
  'One-Time Fee Waiver', 'Early Payment Discount', 'TCO Improvement',
  'Productivity Improvement',
  'Vendor Issue', 'Support Ticket', 'Contract Question',
  'Billing Dispute', 'Service Request', 'Compliance/Legal', 'Other',
]

export function EventsList({ events }: { events: EventRow[] }) {
  const [search, setSearch] = useState('')
  const [statusFilter, setStatusFilter] = useState('')
  const [typeFilter, setTypeFilter] = useState('')
  const [projectTypeFilter, setProjectTypeFilter] = useState('')

  const filteredEvents = useMemo(() => {
    return events.filter((event) => {
      const matchesSearch = event.event_name.toLowerCase().includes(search.toLowerCase())
      const matchesStatus = !statusFilter || event.event_status === statusFilter
      const matchesType = !typeFilter || event.event_type === typeFilter
      const matchesProjectType = !projectTypeFilter || (event.project_type || 'Sourcing') === projectTypeFilter
      return matchesSearch && matchesStatus && matchesType && matchesProjectType
    })
  }, [events, search, statusFilter, typeFilter, projectTypeFilter])

  return (
    <div className="mt-6">
      <div className="mb-4 flex flex-wrap gap-3">
        <div className="relative flex-1 min-w-[200px]">
          <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-gray-400" />
          <input
            type="text"
            placeholder="Search projects..."
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            className="w-full rounded-lg border border-gray-300 pl-10 pr-3 py-2 text-sm focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500 dark:border-gray-600 dark:bg-gray-800 dark:text-gray-100"
          />
        </div>
        {/* Project type filter */}
        <select
          value={projectTypeFilter}
          onChange={(e) => setProjectTypeFilter(e.target.value)}
          className="rounded-lg border border-gray-300 px-3 py-2 text-sm focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500 dark:border-gray-600 dark:bg-gray-800 dark:text-gray-100"
        >
          <option value="">All Projects</option>
          <option value="Sourcing">Sourcing</option>
          <option value="Support">Support</option>
        </select>
        <select
          value={statusFilter}
          onChange={(e) => setStatusFilter(e.target.value)}
          className="rounded-lg border border-gray-300 px-3 py-2 text-sm focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500 dark:border-gray-600 dark:bg-gray-800 dark:text-gray-100"
        >
          <option value="">All Statuses</option>
          {EVENT_STATUSES.map((status) => (
            <option key={status} value={status}>{status}</option>
          ))}
        </select>
        <select
          value={typeFilter}
          onChange={(e) => setTypeFilter(e.target.value)}
          className="rounded-lg border border-gray-300 px-3 py-2 text-sm focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500 dark:border-gray-600 dark:bg-gray-800 dark:text-gray-100"
        >
          <option value="">All Types</option>
          {EVENT_TYPES.map((type) => (
            <option key={type} value={type}>{type}</option>
          ))}
        </select>
      </div>

      <div className="overflow-x-auto rounded-lg border border-gray-200 bg-white shadow-sm dark:border-gray-700 dark:bg-gray-800">
        <table className="w-full min-w-[800px]">
          <thead>
            <tr className="border-b border-gray-200 bg-gray-50 dark:border-gray-700 dark:bg-gray-900/50">
              <th className="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-gray-500 dark:text-gray-400">Name</th>
              <th className="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-gray-500 dark:text-gray-400">Type</th>
              <th className="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-gray-500 dark:text-gray-400">IP Owner</th>
              <th className="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-gray-500 dark:text-gray-400">Category</th>
              <th className="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-gray-500 dark:text-gray-400">Business Unit</th>
              <th className="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-gray-500 dark:text-gray-400">Supplier</th>
              <th className="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-gray-500 dark:text-gray-400">Status</th>
              <th className="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-gray-500 dark:text-gray-400">Contract</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-gray-200 dark:divide-gray-700">
            {filteredEvents.length === 0 ? (
              <tr>
                <td colSpan={8} className="px-4 py-12 text-center">
                  <Briefcase className="mx-auto mb-2 h-8 w-8 text-gray-400" />
                  <p className="text-sm text-gray-500 dark:text-gray-400">No projects found</p>
                </td>
              </tr>
            ) : (
              filteredEvents.map((event) => {
                const isSupport = event.project_type === 'Support'
                return (
                  <tr key={event.id} className="hover:bg-gray-50 dark:hover:bg-gray-700/50">
                    <td className="px-4 py-3">
                      <div className="flex items-center gap-2">
                        {isSupport ? (
                          <LifeBuoy className="h-4 w-4 shrink-0 text-orange-500" />
                        ) : (
                          <Briefcase className="h-4 w-4 shrink-0 text-indigo-500" />
                        )}
                        <Link href={`/events/${event.id}`} className="text-sm font-medium text-indigo-600 hover:text-indigo-800 dark:text-indigo-400 dark:hover:text-indigo-300">
                          {event.event_name}
                        </Link>
                      </div>
                    </td>
                    <td className="px-4 py-3 text-sm text-gray-600 dark:text-gray-400">{event.event_type}</td>
                    <td className="px-4 py-3 text-sm text-gray-600 dark:text-gray-400">{event.buyer_name || '—'}</td>
                    <td className="px-4 py-3 text-sm text-gray-600 dark:text-gray-400">
                      {getFirst(event.category)?.category_name || '—'}
                    </td>
                    <td className="px-4 py-3 text-sm text-gray-600 dark:text-gray-400">
                      {getFirst(event.business_unit)?.business_unit_name || '—'}
                    </td>
                    <td className="px-4 py-3 text-sm text-gray-600 dark:text-gray-400">
                      {getFirst(event.awarded_supplier)?.supplier_name || getFirst(event.incumbent_supplier)?.supplier_name || '—'}
                    </td>
                    <td className="px-4 py-3">
                      <span className={clsx('inline-flex rounded-full px-2.5 py-0.5 text-xs font-medium', statusColor(event.event_status))}>
                        {event.event_status}
                      </span>
                    </td>
                    <td className="px-4 py-3 text-sm text-gray-600 dark:text-gray-400">
                      {event.contract_start_date ? `${formatDate(event.contract_start_date)} → ${formatDate(event.contract_end_date)}` : '—'}
                    </td>
                  </tr>
                )
              })
            )}
          </tbody>
        </table>
      </div>

      <p className="mt-4 text-sm text-gray-500 dark:text-gray-400">
        Showing {filteredEvents.length} of {events.length} projects
      </p>
    </div>
  )
}