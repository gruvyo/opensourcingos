'use client'

import { useState } from 'react'
import { useRouter } from 'next/navigation'
import { createClient } from '@/lib/supabase/client'
import { clsx } from 'clsx'

type Option = { id: string; category_name?: string; business_unit_name?: string; cost_center_name?: string; supplier_name?: string }

const EVENT_TYPES = [
  'Renewal', 'Competitive Rebid', 'Net New Purchase', 'Renegotiation',
  'Demand Reduction', 'Specification Change', 'Supplier Consolidation',
  'Market Index / Commodity', 'Payment Terms', 'Rebate / Credit',
  'One-Time Fee Waiver', 'Early Payment Discount', 'TCO Improvement',
  'Productivity Improvement'
]

const SOURCING_METHODS = [
  'RFP', 'RFQ', 'RFI', 'Auction', 'Sole Source',
  'Negotiated Renewal', 'Benchmark Negotiation', 'Contract Amendment',
  'Catalog Optimization', 'Demand Management', 'Supplier Consolidation'
]

const EVENT_STATUSES = [
  'Pipeline', 'Scoped', 'Baseline Pending', 'Baseline Approved',
  'In Market', 'Negotiation', 'Award Recommended', 'Award Approved',
  'Contracted', 'Implemented', 'Realized', 'Finance Validated',
  'Closed', 'Cancelled', 'Rejected'
]

const REPORTING_BASIS = [
  'Current-Year Realized', 'Annualized', 'Contract Term', 'One-Time'
]

export function EventForm({
  categories,
  businessUnits,
  costCenters,
  suppliers,
}: {
  categories: Option[]
  businessUnits: Option[]
  costCenters: Option[]
  suppliers: Option[]
}) {
  const router = useRouter()
  const supabase = createClient()
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const [form, setForm] = useState({
    event_name: '',
    event_description: '',
    event_type: '',
    sourcing_method: '',
    category_id: '',
    business_unit_id: '',
    cost_center_id: '',
    incumbent_supplier_id: '',
    event_status: 'Pipeline',
    event_start_date: '',
    event_close_date: '',
    contract_start_date: '',
    contract_end_date: '',
    recognition_start_date: '',
    recognition_end_date: '',
    official_reporting_basis: 'Current-Year Realized',
  })

  const handleChange = (field: string, value: string) => {
    setForm(prev => ({ ...prev, [field]: value }))
  }

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    setLoading(true)
    setError(null)

    const { data: { user } } = await supabase.auth.getUser()
    if (!user) {
      setError('You must be logged in')
      setLoading(false)
      return
    }

    const { data: profile } = await supabase
      .from('profiles')
      .select('organization_id')
      .eq('id', user!.id)
      .single()

    if (!profile?.organization_id) {
      setError('No organization found for your account')
      setLoading(false)
      return
    }

    const eventData = {
      ...form,
      organization_id: profile.organization_id,
      procurement_owner_id: user.id,
      created_by: user.id,
      updated_by: user.id,
      currency_code: 'USD',
      fx_rate_to_usd: 1.0,
      event_start_date: form.event_start_date || null,
      event_close_date: form.event_close_date || null,
      contract_start_date: form.contract_start_date || null,
      contract_end_date: form.contract_end_date || null,
      recognition_start_date: form.recognition_start_date || null,
      recognition_end_date: form.recognition_end_date || null,
      category_id: form.category_id || null,
      business_unit_id: form.business_unit_id || null,
      cost_center_id: form.cost_center_id || null,
      incumbent_supplier_id: form.incumbent_supplier_id || null,
    }

    const { data, error: insertError } = await supabase
      .from('sourcing_events')
      .insert(eventData)
      .select('id')
      .single()

    if (insertError) {
      setError(insertError.message)
      setLoading(false)
      return
    }

    router.push(`/events/${data.id}`)
    router.refresh()
  }

  const inputClass = 'mt-1 block w-full rounded-lg border border-gray-300 px-3 py-2 text-sm focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500'
  const labelClass = 'block text-sm font-medium text-gray-700'

  return (
    <form onSubmit={handleSubmit} className="mt-6 space-y-8">
      {error && (
        <div className="rounded-lg bg-red-50 p-4 text-sm text-red-700">
          {error}
        </div>
      )}

      {/* Basic Info */}
      <div className="rounded-lg border border-gray-200 bg-white p-6 shadow-sm">
        <h2 className="mb-4 text-lg font-semibold text-gray-900">Basic Information</h2>
        <div className="grid grid-cols-1 gap-4 md:grid-cols-2">
          <div className="md:col-span-2">
            <label className={labelClass}>Event Name *</label>
            <input
              type="text"
              required
              value={form.event_name}
              onChange={(e) => handleChange('event_name', e.target.value)}
              className={inputClass}
              placeholder="e.g. CRM Software Renewal"
            />
          </div>
          <div className="md:col-span-2">
            <label className={labelClass}>Description</label>
            <textarea
              value={form.event_description}
              onChange={(e) => handleChange('event_description', e.target.value)}
              className={inputClass}
              rows={3}
              placeholder="Brief description of the sourcing event"
            />
          </div>
          <div>
            <label className={labelClass}>Event Type *</label>
            <select
              required
              value={form.event_type}
              onChange={(e) => handleChange('event_type', e.target.value)}
              className={inputClass}
            >
              <option value="">Select type...</option>
              {EVENT_TYPES.map((type) => (
                <option key={type} value={type}>{type}</option>
              ))}
            </select>
          </div>
          <div>
            <label className={labelClass}>Sourcing Method</label>
            <select
              value={form.sourcing_method}
              onChange={(e) => handleChange('sourcing_method', e.target.value)}
              className={inputClass}
            >
              <option value="">Select method...</option>
              {SOURCING_METHODS.map((method) => (
                <option key={method} value={method}>{method}</option>
              ))}
            </select>
          </div>
        </div>
      </div>

      {/* Classification */}
      <div className="rounded-lg border border-gray-200 bg-white p-6 shadow-sm">
        <h2 className="mb-4 text-lg font-semibold text-gray-900">Classification</h2>
        <div className="grid grid-cols-1 gap-4 md:grid-cols-2">
          <div>
            <label className={labelClass}>Category</label>
            <select
              value={form.category_id}
              onChange={(e) => handleChange('category_id', e.target.value)}
              className={inputClass}
            >
              <option value="">Select category...</option>
              {categories.map((c) => (
                <option key={c.id} value={c.id}>{c.category_name}</option>
              ))}
            </select>
          </div>
          <div>
            <label className={labelClass}>Business Unit</label>
            <select
              value={form.business_unit_id}
              onChange={(e) => handleChange('business_unit_id', e.target.value)}
              className={inputClass}
            >
              <option value="">Select business unit...</option>
              {businessUnits.map((b) => (
                <option key={b.id} value={b.id}>{b.business_unit_name}</option>
              ))}
            </select>
          </div>
          <div>
            <label className={labelClass}>Cost Center</label>
            <select
              value={form.cost_center_id}
              onChange={(e) => handleChange('cost_center_id', e.target.value)}
              className={inputClass}
            >
              <option value="">Select cost center...</option>
              {costCenters.map((c) => (
                <option key={c.id} value={c.id}>{c.cost_center_name}</option>
              ))}
            </select>
          </div>
          <div>
            <label className={labelClass}>Incumbent Supplier</label>
            <select
              value={form.incumbent_supplier_id}
              onChange={(e) => handleChange('incumbent_supplier_id', e.target.value)}
              className={inputClass}
            >
              <option value="">Select supplier...</option>
              {suppliers.map((s) => (
                <option key={s.id} value={s.id}>{s.supplier_name}</option>
              ))}
            </select>
          </div>
        </div>
      </div>

      {/* Dates & Status */}
      <div className="rounded-lg border border-gray-200 bg-white p-6 shadow-sm">
        <h2 className="mb-4 text-lg font-semibold text-gray-900">Dates & Status</h2>
        <div className="grid grid-cols-1 gap-4 md:grid-cols-2">
          <div>
            <label className={labelClass}>Event Status</label>
            <select
              value={form.event_status}
              onChange={(e) => handleChange('event_status', e.target.value)}
              className={inputClass}
            >
              {EVENT_STATUSES.map((status) => (
                <option key={status} value={status}>{status}</option>
              ))}
            </select>
          </div>
          <div>
            <label className={labelClass}>Reporting Basis</label>
            <select
              value={form.official_reporting_basis}
              onChange={(e) => handleChange('official_reporting_basis', e.target.value)}
              className={inputClass}
            >
              {REPORTING_BASIS.map((basis) => (
                <option key={basis} value={basis}>{basis}</option>
              ))}
            </select>
          </div>
          <div>
            <label className={labelClass}>Event Start Date</label>
            <input
              type="date"
              value={form.event_start_date}
              onChange={(e) => handleChange('event_start_date', e.target.value)}
              className={inputClass}
            />
          </div>
          <div>
            <label className={labelClass}>Event Close Date</label>
            <input
              type="date"
              value={form.event_close_date}
              onChange={(e) => handleChange('event_close_date', e.target.value)}
              className={inputClass}
            />
          </div>
          <div>
            <label className={labelClass}>Contract Start Date</label>
            <input
              type="date"
              value={form.contract_start_date}
              onChange={(e) => handleChange('contract_start_date', e.target.value)}
              className={inputClass}
            />
          </div>
          <div>
            <label className={labelClass}>Contract End Date</label>
            <input
              type="date"
              value={form.contract_end_date}
              onChange={(e) => handleChange('contract_end_date', e.target.value)}
              className={inputClass}
            />
          </div>
          <div>
            <label className={labelClass}>Recognition Start Date</label>
            <input
              type="date"
              value={form.recognition_start_date}
              onChange={(e) => handleChange('recognition_start_date', e.target.value)}
              className={inputClass}
            />
          </div>
          <div>
            <label className={labelClass}>Recognition End Date</label>
            <input
              type="date"
              value={form.recognition_end_date}
              onChange={(e) => handleChange('recognition_end_date', e.target.value)}
              className={inputClass}
            />
          </div>
        </div>
      </div>

      {/* Submit */}
      <div className="flex justify-end gap-3">
        <button
          type="button"
          onClick={() => router.push('/events')}
          className="rounded-lg border border-gray-300 px-4 py-2 text-sm font-medium text-gray-700 hover:bg-gray-50"
        >
          Cancel
        </button>
        <button
          type="submit"
          disabled={loading}
          className="rounded-lg bg-indigo-600 px-4 py-2 text-sm font-medium text-white transition-colors hover:bg-indigo-700 disabled:opacity-50"
        >
          {loading ? 'Creating...' : 'Create Event'}
        </button>
      </div>
    </form>
  )
}
