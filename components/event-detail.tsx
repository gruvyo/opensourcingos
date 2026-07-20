'use client'

import { useState } from 'react'
import {
  FileText, List, BarChart2, Users, FileCheck,
  Calculator, Clock, StickyNote,
  Briefcase, LifeBuoy,
} from 'lucide-react'
import { clsx } from 'clsx'
import { formatDate, statusColor } from '@/lib/utils'
import { ScopeLinesTab } from './scope-lines-tab'
import { BaselinesTab } from './baselines-tab'
import { OffersTab } from './offers-tab'
import { CalculationsTab } from './calculations-tab'


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
  project_type: string | null
  buyer_name: string | null
  notes: string | null
  category: any
  business_unit: any
  cost_center: any
  incumbent_supplier: any
  awarded_supplier: any
}

const SOURCING_TABS = [
  { id: 'overview', label: 'Overview', icon: FileText },
  { id: 'scope', label: 'Scope Lines', icon: List },
  { id: 'baselines', label: 'Baselines', icon: BarChart2 },
  { id: 'offers', label: 'Supplier Offers', icon: Users },
  { id: 'awards', label: 'Awards', icon: FileCheck },
  { id: 'calculations', label: 'Calculations', icon: Calculator },
  { id: 'notes', label: 'Notes', icon: StickyNote },
]

const SUPPORT_TABS = [
  { id: 'overview', label: 'Overview', icon: FileText },
  { id: 'notes', label: 'Notes', icon: StickyNote },
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

  const isSupport = event.project_type === 'Support'
  const TABS = isSupport ? SUPPORT_TABS : SOURCING_TABS

  return (
    <div>
      <div className="mb-6">
        <div className="flex items-start justify-between">
          <div>
            <div className="flex items-center gap-3">
              <h1 className="text-2xl font-bold text-gray-900 dark:text-gray-100">{event.event_name}</h1>
              <span className={clsx(
                'inline-flex items-center gap-1 rounded-full px-2.5 py-0.5 text-xs font-medium',
                isSupport
                  ? 'bg-orange-100 text-orange-700 dark:bg-orange-900/30 dark:text-orange-300'
                  : 'bg-indigo-100 text-indigo-700 dark:bg-indigo-900/30 dark:text-indigo-300'
              )}>
                {isSupport ? <LifeBuoy className="h-3 w-3" /> : <Briefcase className="h-3 w-3" />}
                {isSupport ? 'Support' : 'Sourcing'}
              </span>
            </div>
            <p className="mt-1 text-sm text-gray-600 dark:text-gray-400">
              {event.event_type} • {isSupport ? (event.event_status || '—') : (event.sourcing_method || '—')}
            </p>
          </div>
          <span className={clsx('inline-flex rounded-full px-3 py-1 text-sm font-medium', statusColor(event.event_status))}>
            {event.event_status}
          </span>
        </div>
        {event.event_description && (
          <p className="mt-3 text-sm text-gray-600 dark:text-gray-400">{event.event_description}</p>
        )}
      </div>

      <div className="border-b border-gray-200 dark:border-gray-700">
        <nav className="flex gap-1 overflow-x-auto">
          {TABS.map((tab) => {
            const Icon = tab.icon
            return (
              <button key={tab.id} onClick={() => setActiveTab(tab.id)}
                className={clsx(
                  'flex items-center gap-2 border-b-2 px-4 py-3 text-sm font-medium transition-colors whitespace-nowrap',
                  activeTab === tab.id
                    ? 'border-indigo-600 text-indigo-600 dark:text-indigo-400'
                    : 'border-transparent text-gray-500 hover:text-gray-700 dark:text-gray-400 dark:hover:text-gray-200'
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
        {activeTab === 'notes' && <NotesTab notes={event.notes} />}
        {!isSupport && activeTab === 'scope' && <ScopeLinesTab eventId={event.id} scopeLines={scopeLines} />}
        {!isSupport && activeTab === 'baselines' && <BaselinesTab eventId={event.id} scopeLines={scopeLines} />}
        {!isSupport && activeTab === 'offers' && <OffersTab eventId={event.id} scopeLines={scopeLines} suppliers={suppliers} />}
        {!isSupport && activeTab === 'awards' && <AwardsTab eventId={event.id} />}
        {!isSupport && activeTab === 'calculations' && <CalculationsTab eventId={event.id} />}

      </div>
    </div>
  )
}

function OverviewTab({ event }: { event: Event }) {
  const isSupport = event.project_type === 'Support'

  const details = [
    { label: 'Project Type', value: isSupport ? 'Support / Non-Commercial' : 'Sourcing' },
    { label: 'IP Owner / Buyer', value: event.buyer_name },
    { label: 'Category', value: getFirst(event.category)?.category_name },
    { label: 'Business Unit', value: getFirst(event.business_unit)?.business_unit_name },
    { label: 'Cost Center', value: getFirst(event.cost_center)?.cost_center_name },
    { label: 'Incumbent Supplier', value: getFirst(event.incumbent_supplier)?.supplier_name },
    !isSupport && { label: 'Awarded Supplier', value: getFirst(event.awarded_supplier)?.supplier_name },
    { label: 'Currency', value: event.currency_code },
    !isSupport && { label: 'Reporting Basis', value: event.official_reporting_basis },
  ].filter(Boolean) as { label: string; value: any }[]

  const dates = [
    { label: isSupport ? 'Start Date' : 'Event Start', value: event.event_start_date },
    { label: isSupport ? 'Due Date' : 'Event Close', value: event.event_close_date },
    !isSupport && { label: 'Contract Start', value: event.contract_start_date },
    !isSupport && { label: 'Contract End', value: event.contract_end_date },
    !isSupport && { label: 'Recognition Start', value: event.recognition_start_date },
    !isSupport && { label: 'Recognition End', value: event.recognition_end_date },
  ].filter(Boolean) as { label: string; value: string | null }[]

  return (
    <div className="grid grid-cols-1 gap-6 md:grid-cols-2">
      <div className="rounded-lg border border-gray-200 bg-white p-6 shadow-sm dark:border-gray-700 dark:bg-gray-800">
        <h3 className="mb-4 text-sm font-semibold uppercase tracking-wider text-gray-500 dark:text-gray-400">Project Details</h3>
        <dl className="space-y-3">
          {details.map((d) => (
            <div key={d.label} className="flex justify-between">
              <dt className="text-sm text-gray-600 dark:text-gray-400">{d.label}</dt>
              <dd className="text-sm font-medium text-gray-900 dark:text-gray-100">{d.value || '—'}</dd>
            </div>
          ))}
        </dl>
      </div>
      <div className="rounded-lg border border-gray-200 bg-white p-6 shadow-sm dark:border-gray-700 dark:bg-gray-800">
        <h3 className="mb-4 text-sm font-semibold uppercase tracking-wider text-gray-500 dark:text-gray-400">Key Dates</h3>
        <dl className="space-y-3">
          {dates.map((d) => (
            <div key={d.label} className="flex justify-between">
              <dt className="flex items-center gap-2 text-sm text-gray-600 dark:text-gray-400">
                <Clock className="h-3 w-3" />
                {d.label}
              </dt>
              <dd className="text-sm font-medium text-gray-900 dark:text-gray-100">{formatDate(d.value)}</dd>
            </div>
          ))}
        </dl>
      </div>
    </div>
  )
}

function NotesTab({ notes }: { notes: string | null }) {
  return (
    <div className="rounded-lg border border-gray-200 bg-white p-6 shadow-sm dark:border-gray-700 dark:bg-gray-800">
      <h3 className="mb-4 text-sm font-semibold uppercase tracking-wider text-gray-500 dark:text-gray-400">Notes</h3>
      {notes ? (
        <div className="whitespace-pre-wrap text-sm text-gray-700 dark:text-gray-300">{notes}</div>
      ) : (
        <p className="text-sm text-gray-400 dark:text-gray-500">No notes have been added for this project.</p>
      )}
    </div>
  )
}

function AwardsTab({ eventId }: { eventId: string }) {
  return (
    <div className="rounded-lg border border-gray-200 bg-white p-12 text-center shadow-sm dark:border-gray-700 dark:bg-gray-800">
      <FileCheck className="mx-auto mb-3 h-10 w-10 text-gray-300 dark:text-gray-600" />
      <h3 className="text-lg font-medium text-gray-900 dark:text-gray-100">Awards</h3>
      <p className="mt-1 text-sm text-gray-500 dark:text-gray-400">
        Create awards from the Supplier Offers tab by expanding an offer and clicking &quot;Create Award from Offer.&quot;
      </p>
    </div>
  )
}