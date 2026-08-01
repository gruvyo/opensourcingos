#!/bin/bash

# Create event detail page
mkdir -p app/events/\[eventId\]

cat > 'app/events/[eventId]/page.tsx' << 'EOF'
import { createClient } from '@/lib/supabase/server'
import { EventDetail } from '@/components/event-detail'
import Link from 'next/link'
import { ArrowLeft } from 'lucide-react'
import { notFound } from 'next/navigation'

export default async function EventDetailPage({
  params,
}: {
  params: Promise<{ eventId: string }>
}) {
  const { eventId } = await params
  const supabase = await createClient()

  const { data: event } = await supabase
    .from('sourcing_events')
    .select(`
      *,
      category:categories(category_name),
      business_unit:business_units(business_unit_name),
      cost_center:cost_centers(cost_center_name),
      incumbent_supplier:suppliers!sourcing_events_incumbent_supplier_id_fkey(supplier_name),
      awarded_supplier:suppliers!sourcing_events_awarded_supplier_id_fkey(supplier_name)
    `)
    .eq('id', eventId)
    .single()

  if (!event) notFound()

  const { data: scopeLines } = await supabase
    .from('event_scope_lines')
    .select(`
      *,
      category:categories(category_name)
    `)
    .eq('event_id', eventId)
    .order('line_number', { ascending: true })

  return (
    <div className="p-8">
      <Link href="/events" className="mb-4 flex items-center gap-2 text-sm text-gray-600 hover:text-gray-900">
        <ArrowLeft className="h-4 w-4" />
        Back to Events
      </Link>
      <EventDetail event={event} scopeLines={scopeLines || []} />
    </div>
  )
}
EOF

# Create the event detail component
cat > components/event-detail.tsx << 'EOF'
'use client'

import { useState } from 'react'
import {
  FileText,
  List,
  BarChart2,
  Users,
  FileCheck,
  Calculator,
  TrendingUp,
  FolderKanban,
  Clock,
  CheckCircle,
} from 'lucide-react'
import { clsx } from 'clsx'
import { formatDate, statusColor } from '@/lib/utils'
import { ScopeLinesTab } from './scope-lines-tab'

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
  { id: 'contracts', label: 'Contracts', icon: FolderKanban },
  { id: 'calculations', label: 'Calculations', icon: Calculator },
  { id: 'realization', label: 'Realization', icon: TrendingUp },
]

export function EventDetail({
  event,
  scopeLines,
}: {
  event: Event
  scopeLines: any[]
}) {
  const [activeTab, setActiveTab] = useState('overview')

  return (
    <div>
      {/* Header */}
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

      {/* Tabs */}
      <div className="border-b border-gray-200">
        <nav className="flex gap-1 overflow-x-auto">
          {TABS.map((tab) => {
            const Icon = tab.icon
            return (
              <button
                key={tab.id}
                onClick={() => setActiveTab(tab.id)}
                className={clsx(
                  'flex items-center gap-2 border-b-2 px-4 py-3 text-sm font-medium transition-colors whitespace-nowrap',
                  activeTab === tab.id
                    ? 'border-indigo-600 text-indigo-600'
                    : 'border-transparent text-gray-500 hover:text-gray-700'
                )}
              >
                <Icon className="h-4 w-4" />
                {tab.label}
              </button>
            )
          })}
        </nav>
      </div>

      {/* Tab Content */}
      <div className="mt-6">
        {activeTab === 'overview' && <OverviewTab event={event} />}
        {activeTab === 'scope' && <ScopeLinesTab eventId={event.id} scopeLines={scopeLines} />}
        {activeTab === 'baselines' && <PlaceholderTab label="Baselines" message="Baseline modeling will be built in Phase 3." />}
        {activeTab === 'offers' && <PlaceholderTab label="Supplier Offers" message="Supplier offers will be built in Phase 4." />}
        {activeTab === 'awards' && <PlaceholderTab label="Awards" message="Awards will be built in Phase 4." />}
        {activeTab === 'contracts' && <PlaceholderTab label="Contracts" message="Contracts will be built in a future phase." />}
        {activeTab === 'calculations' && <PlaceholderTab label="Calculations" message="Savings calculations will be built in Phase 5." />}
        {activeTab === 'realization' && <PlaceholderTab label="Realization" message="Realization tracking will be built in Phase 5." />}
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
          {details.map((detail) => (
            <div key={detail.label} className="flex justify-between">
              <dt className="text-sm text-gray-600">{detail.label}</dt>
              <dd className="text-sm font-medium text-gray-900">{detail.value || '—'}</dd>
            </div>
          ))}
        </dl>
      </div>

      <div className="rounded-lg border border-gray-200 bg-white p-6 shadow-sm">
        <h3 className="mb-4 text-sm font-semibold uppercase tracking-wider text-gray-500">Key Dates</h3>
        <dl className="space-y-3">
          {dates.map((date) => (
            <div key={date.label} className="flex justify-between">
              <dt className="flex items-center gap-2 text-sm text-gray-600">
                <Clock className="h-3 w-3" />
                {date.label}
              </dt>
              <dd className="text-sm font-medium text-gray-900">{formatDate(date.value)}</dd>
            </div>
          ))}
        </dl>
      </div>
    </div>
  )
}

function PlaceholderTab({ label, message }: { label: string; message: string }) {
  return (
    <div className="rounded-lg border border-gray-200 bg-white p-12 text-center shadow-sm">
      <CheckCircle className="mx-auto mb-3 h-10 w-10 text-gray-300" />
      <h3 className="text-lg font-medium text-gray-900">{label}</h3>
      <p className="mt-1 text-sm text-gray-500">{message}</p>
    </div>
  )
}
EOF

# Create scope lines tab component
cat > components/scope-lines-tab.tsx << 'EOF'
'use client'

import { useState } from 'react'
import { createClient } from '@/lib/supabase/client'
import { Plus, Trash2, AlertTriangle, CheckCircle } from 'lucide-react'
import { formatDate } from '@/lib/utils'

type ScopeLine = {
  id: string
  line_number: number
  item_service_name: string
  item_description: string | null
  uom: string | null
  baseline_quantity: number | null
  forecast_quantity: number | null
  final_quantity: number | null
  scope_change_flag: boolean
  scope_change_description: string | null
  business_equivalency_confirmed: boolean
  category: { category_name: string } | null
}

const UOM_OPTIONS = [
  'Each', 'License', 'License-Month', 'License-Year', 'Hour', 'Day',
  'Week', 'Month', 'Year', 'FTE', 'Project', 'SOW', 'Location',
  'Shipment', 'Mile', 'Pound', 'Kilogram', 'Pallet', 'Case',
  'Unit', 'Seat', 'Subscription', 'Transaction', 'Gigabyte', 'Terabyte'
]

export function ScopeLinesTab({ eventId, scopeLines: initialLines }: { eventId: string; scopeLines: ScopeLine[] }) {
  const [scopeLines, setScopeLines] = useState(initialLines)
  const [showForm, setShowForm] = useState(false)
  const [loading, setLoading] = useState(false)
  const supabase = createClient()

  const [newLine, setNewLine] = useState({
    item_service_name: '',
    item_description: '',
    uom: '',
    baseline_quantity: '',
    forecast_quantity: '',
    final_quantity: '',
    scope_change_flag: false,
    scope_change_description: '',
    business_equivalency_confirmed: false,
  })

  const handleAdd = async (e: React.FormEvent) => {
    e.preventDefault()
    setLoading(true)

    const { data: { user } } = await supabase.auth.getUser()
    if (!user) { setLoading(false); return }

    const { data: profile } = await supabase
      .from('profiles')
      .select('organization_id')
      .eq('id', user.id)
      .single()

    const lineNumber = scopeLines.length + 1

    const { data, error } = await supabase
      .from('event_scope_lines')
      .insert({
        organization_id: profile?.organization_id,
        event_id: eventId,
        line_number: lineNumber,
        item_service_name: newLine.item_service_name,
        item_description: newLine.item_description || null,
        uom: newLine.uom || null,
        baseline_quantity: newLine.baseline_quantity ? parseFloat(newLine.baseline_quantity) : null,
        forecast_quantity: newLine.forecast_quantity ? parseFloat(newLine.forecast_quantity) : null,
        final_quantity: newLine.final_quantity ? parseFloat(newLine.final_quantity) : null,
        scope_change_flag: newLine.scope_change_flag,
        scope_change_description: newLine.scope_change_description || null,
        business_equivalency_confirmed: newLine.business_equivalency_confirmed,
      })
      .select(`
        *,
        category:categories(category_name)
      `)
      .single()

    if (!error && data) {
      setScopeLines([...scopeLines, data])
      setNewLine({
        item_service_name: '', item_description: '', uom: '',
        baseline_quantity: '', forecast_quantity: '', final_quantity: '',
        scope_change_flag: false, scope_change_description: '',
        business_equivalency_confirmed: false,
      })
      setShowForm(false)
    }
    setLoading(false)
  }

  const handleDelete = async (id: string) => {
    const { error } = await supabase.from('event_scope_lines').delete().eq('id', id)
    if (!error) {
      setScopeLines(scopeLines.filter(l => l.id !== id))
    }
  }

  const inputClass = 'block w-full rounded-lg border border-gray-300 px-3 py-2 text-sm focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500'
  const labelClass = 'block text-xs font-medium text-gray-600 mb-1'

  return (
    <div>
      <div className="mb-4 flex items-center justify-between">
        <div>
          <h3 className="text-lg font-semibold text-gray-900">Scope Lines</h3>
          <p className="text-sm text-gray-600">Define what is being sourced, line by line</p>
        </div>
        <button
          onClick={() => setShowForm(!showForm)}
          className="flex items-center gap-2 rounded-lg bg-indigo-600 px-4 py-2 text-sm font-medium text-white hover:bg-indigo-700"
        >
          <Plus className="h-4 w-4" />
          Add Scope Line
        </button>
      </div>

      {showForm && (
        <form onSubmit={handleAdd} className="mb-6 rounded-lg border border-indigo-200 bg-indigo-50 p-6">
          <h4 className="mb-4 font-medium text-gray-900">New Scope Line</h4>
          <div className="grid grid-cols-1 gap-4 md:grid-cols-3">
            <div className="md:col-span-2">
              <label className={labelClass}>Item / Service Name *</label>
              <input type="text" required value={newLine.item_service_name}
                onChange={(e) => setNewLine({ ...newLine, item_service_name: e.target.value })}
                className={inputClass} placeholder="e.g. CRM Enterprise License" />
            </div>
            <div>
              <label className={labelClass}>UOM</label>
              <select value={newLine.uom}
                onChange={(e) => setNewLine({ ...newLine, uom: e.target.value })}
                className={inputClass}>
                <option value="">Select...</option>
                {UOM_OPTIONS.map((u) => <option key={u} value={u}>{u}</option>)}
              </select>
            </div>
            <div className="md:col-span-3">
              <label className={labelClass}>Description</label>
              <input type="text" value={newLine.item_description}
                onChange={(e) => setNewLine({ ...newLine, item_description: e.target.value })}
                className={inputClass} placeholder="Brief description" />
            </div>
            <div>
              <label className={labelClass}>Baseline Qty</label>
              <input type="number" step="0.01" value={newLine.baseline_quantity}
                onChange={(e) => setNewLine({ ...newLine, baseline_quantity: e.target.value })}
                className={inputClass} />
            </div>
            <div>
              <label className={labelClass}>Forecast Qty</label>
              <input type="number" step="0.01" value={newLine.forecast_quantity}
                onChange={(e) => setNewLine({ ...newLine, forecast_quantity: e.target.value })}
                className={inputClass} />
            </div>
            <div>
              <label className={labelClass}>Final Qty</label>
              <input type="number" step="0.01" value={newLine.final_quantity}
                onChange={(e) => setNewLine({ ...newLine, final_quantity: e.target.value })}
                className={inputClass} />
            </div>
            <div className="md:col-span-3 flex items-center gap-6">
              <label className="flex items-center gap-2 text-sm text-gray-700">
                <input type="checkbox" checked={newLine.scope_change_flag}
                  onChange={(e) => setNewLine({ ...newLine, scope_change_flag: e.target.checked })}
                  className="rounded" />
                Scope change flag
              </label>
              <label className="flex items-center gap-2 text-sm text-gray-700">
                <input type="checkbox" checked={newLine.business_equivalency_confirmed}
                  onChange={(e) => setNewLine({ ...newLine, business_equivalency_confirmed: e.target.checked })}
                  className="rounded" />
                Business equivalency confirmed
              </label>
            </div>
            {newLine.scope_change_flag && (
              <div className="md:col-span-3">
                <label className={labelClass}>Scope Change Description</label>
                <input type="text" value={newLine.scope_change_description}
                  onChange={(e) => setNewLine({ ...newLine, scope_change_description: e.target.value })}
                  className={inputClass} placeholder="Explain the scope change" />
              </div>
            )}
          </div>
          <div className="mt-4 flex justify-end gap-2">
            <button type="button" onClick={() => setShowForm(false)}
              className="rounded-lg border border-gray-300 px-4 py-2 text-sm font-medium text-gray-700 hover:bg-gray-50">
              Cancel
            </button>
            <button type="submit" disabled={loading}
              className="rounded-lg bg-indigo-600 px-4 py-2 text-sm font-medium text-white hover:bg-indigo-700 disabled:opacity-50">
              {loading ? 'Adding...' : 'Add Line'}
            </button>
          </div>
        </form>
      )}

      {/* Scope Lines Table */}
      <div className="overflow-hidden rounded-lg border border-gray-200 bg-white shadow-sm">
        <table className="w-full">
          <thead>
            <tr className="border-b border-gray-200 bg-gray-50">
              <th className="px-4 py-3 text-left text-xs font-semibold uppercase text-gray-500">#</th>
              <th className="px-4 py-3 text-left text-xs font-semibold uppercase text-gray-500">Item / Service</th>
              <th className="px-4 py-3 text-left text-xs font-semibold uppercase text-gray-500">UOM</th>
              <th className="px-4 py-3 text-right text-xs font-semibold uppercase text-gray-500">Baseline Qty</th>
              <th className="px-4 py-3 text-right text-xs font-semibold uppercase text-gray-500">Forecast Qty</th>
              <th className="px-4 py-3 text-right text-xs font-semibold uppercase text-gray-500">Final Qty</th>
              <th className="px-4 py-3 text-center text-xs font-semibold uppercase text-gray-500">Scope Change</th>
              <th className="px-4 py-3 text-center text-xs font-semibold uppercase text-gray-500">Actions</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-gray-200">
            {scopeLines.length === 0 ? (
              <tr>
                <td colSpan={8} className="px-4 py-12 text-center text-sm text-gray-500">
                  No scope lines yet. Click "Add Scope Line" to define what's being sourced.
                </td>
              </tr>
            ) : (
              scopeLines.map((line) => (
                <tr key={line.id} className="hover:bg-gray-50">
                  <td className="px-4 py-3 text-sm text-gray-500">{line.line_number}</td>
                  <td className="px-4 py-3">
                    <div className="text-sm font-medium text-gray-900">{line.item_service_name}</div>
                    {line.item_description && (
                      <div className="text-xs text-gray-500">{line.item_description}</div>
                    )}
                  </td>
                  <td className="px-4 py-3 text-sm text-gray-600">{line.uom || '—'}</td>
                  <td className="px-4 py-3 text-right text-sm text-gray-600">{line.baseline_quantity ?? '—'}</td>
                  <td className="px-4 py-3 text-right text-sm text-gray-600">{line.forecast_quantity ?? '—'}</td>
                  <td className="px-4 py-3 text-right text-sm text-gray-600">{line.final_quantity ?? '—'}</td>
                  <td className="px-4 py-3 text-center">
                    {line.scope_change_flag ? (
                      <div className="flex flex-col items-center gap-1">
                        <AlertTriangle className="h-4 w-4 text-amber-500" />
                        {line.business_equivalency_confirmed && (
                          <CheckCircle className="h-3 w-3 text-green-500" />
                        )}
                      </div>
                    ) : (
                      <span className="text-xs text-gray-400">No</span>
                    )}
                  </td>
                  <td className="px-4 py-3 text-center">
                    <button onClick={() => handleDelete(line.id)}
                      className="text-gray-400 hover:text-red-600">
                      <Trash2 className="h-4 w-4" />
                    </button>
                  </td>
                </tr>
              ))
            )}
          </tbody>
        </table>
      </div>

      {scopeLines.length > 0 && (
        <p className="mt-3 text-sm text-gray-500">
          {scopeLines.length} scope line{scopeLines.length !== 1 ? 's' : ''}
        </p>
      )}
    </div>
  )
}
EOF

# Clear build cache
rm -rf .next

echo "DONE"
