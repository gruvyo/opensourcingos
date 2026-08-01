'use client'

import { useState, useMemo } from 'react'
import Link from 'next/link'
import { Search, Briefcase, LifeBuoy } from 'lucide-react'
import { formatDate, statusColor } from '@/lib/utils'
import { Input, Select } from '@/components/ui/input'
import { clsx } from 'clsx'

type EventRow = {
  id: string
  event_name: string
  event_type: string
  event_status: string
  project_type: string | null
  buyer_name: string | null
  project_due_date: string | null
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
          <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-[var(--text-3)]" />
          <Input
            type="text"
            placeholder="Search projects..."
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            className="pl-10"
          />
        </div>
        <Select value={projectTypeFilter} onChange={(e) => setProjectTypeFilter(e.target.value)} className="w-auto">
          <option value="">All Projects</option>
          <option value="Sourcing">Sourcing</option>
          <option value="Support">Support</option>
        </Select>
        <Select value={statusFilter} onChange={(e) => setStatusFilter(e.target.value)} className="w-auto">
          <option value="">All Statuses</option>
          {EVENT_STATUSES.map((status) => (
            <option key={status} value={status}>{status}</option>
          ))}
        </Select>
        <Select value={typeFilter} onChange={(e) => setTypeFilter(e.target.value)} className="w-auto">
          <option value="">All Types</option>
          {EVENT_TYPES.map((type) => (
            <option key={type} value={type}>{type}</option>
          ))}
        </Select>
      </div>

      <div className="overflow-x-auto rounded-lg border border-[var(--border)] bg-[var(--surface)] shadow-sm">
        <table className="w-full min-w-[800px]">
          <thead>
            <tr className="border-b border-[var(--border)] bg-[var(--surface-2)]">
              <th className="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-[var(--text-3)]">Name</th>
              <th className="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-[var(--text-3)]">Type</th>
              <th className="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-[var(--text-3)]">Owner</th>
              <th className="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-[var(--text-3)]">Category</th>
              <th className="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-[var(--text-3)]">Business Unit</th>
              <th className="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-[var(--text-3)]">Supplier</th>
              <th className="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-[var(--text-3)]">Due Date</th>
              <th className="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-[var(--text-3)]">Status</th>
              <th className="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-[var(--text-3)]">Contract</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-[var(--border)]">
            {filteredEvents.length === 0 ? (
              <tr>
                <td colSpan={9} className="px-4 py-12 text-center">
                  <Briefcase className="mx-auto mb-2 h-8 w-8 text-[var(--text-3)]" />
                  <p className="text-sm text-[var(--text-3)]">No projects found</p>
                </td>
              </tr>
            ) : (
              filteredEvents.map((event) => {
                const isSupport = event.project_type === 'Support'
                return (
                  <tr key={event.id} className="transition-colors hover:bg-[var(--surface-2)]">
                    <td className="px-4 py-3">
                      <div className="flex items-center gap-2">
                        {isSupport ? (
                          <LifeBuoy className="h-4 w-4 shrink-0 text-orange-500" />
                        ) : (
                          <Briefcase className="h-4 w-4 shrink-0 text-indigo-500" />
                        )}
                        <Link href={`/events/${event.id}`} className="text-sm font-medium text-[var(--brand-ink)] hover:underline">
                          {event.event_name}
                        </Link>
                      </div>
                    </td>
                    <td className="px-4 py-3 text-sm text-[var(--text-2)]">{event.event_type}</td>
                    <td className="px-4 py-3 text-sm text-[var(--text-2)]">{event.buyer_name || '—'}</td>
                    <td className="px-4 py-3 text-sm text-[var(--text-2)]">
                      {getFirst(event.category)?.category_name || '—'}
                    </td>
                    <td className="px-4 py-3 text-sm text-[var(--text-2)]">
                      {getFirst(event.business_unit)?.business_unit_name || '—'}
                    </td>
                    <td className="px-4 py-3 text-sm text-[var(--text-2)]">
                      {getFirst(event.awarded_supplier)?.supplier_name || getFirst(event.incumbent_supplier)?.supplier_name || '—'}
                    </td>
                    <td className="px-4 py-3 text-sm text-[var(--text-2)]">{formatDate(event.project_due_date)}</td>
                    <td className="px-4 py-3">
                      <span className={clsx('inline-flex rounded-full px-2.5 py-0.5 text-xs font-medium', statusColor(event.event_status))}>
                        {event.event_status}
                      </span>
                    </td>
                    <td className="px-4 py-3 text-sm text-[var(--text-2)]">
                      {event.contract_start_date ? `${formatDate(event.contract_start_date)} → ${formatDate(event.contract_end_date)}` : '—'}
                    </td>
                  </tr>
                )
              })
            )}
          </tbody>
        </table>
      </div>

      <p className="mt-4 text-sm text-[var(--text-3)]">
        Showing {filteredEvents.length} of {events.length} projects
      </p>
    </div>
  )
}
