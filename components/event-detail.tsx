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
  category: { category_name: string } | null
  business_unit: { business_unit_name: string } | null
  cost_center: { cost_center_name: string } | null
  incumbent_supplier: { supplier_name: string } | null
  awarded_supplier: { supplier_name: string } | null
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
    { label: 'Category', value: event.category?.category_name },
    { label: 'Business Unit', value: event.business_unit?.business_unit_name },
    { label: 'Cost Center', value: event.cost_center?.cost_center_name },
    { label: 'Incumbent Supplier', value: event.incumbent_supplier?.supplier_name },
    { label: 'Awarded Supplier', value: event.awarded_supplier?.supplier_name },
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
