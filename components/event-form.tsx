'use client'

import { useState } from 'react'
import { useRouter } from 'next/navigation'
import { createClient } from '@/lib/supabase/client'
import { Briefcase, LifeBuoy, Plus, X } from 'lucide-react'

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

const SOURCING_STATUSES = [
  'Pipeline', 'Scoped', 'Baseline Pending', 'Baseline Approved',
  'In Market', 'Negotiation', 'Award Recommended', 'Award Approved',
  'Contracted', 'Implemented', 'Realized', 'Finance Validated',
  'Closed', 'Cancelled', 'Rejected'
]

const SUPPORT_STATUSES = [
  'Not Started', 'In Progress', 'Hold', 'Complete', 'Cancelled'
]

const SUPPORT_TYPES = [
  'Vendor Issue', 'Support Ticket', 'Contract Question',
  'Billing Dispute', 'Service Request', 'Compliance/Legal',
  'Other'
]

const REPORTING_BASIS = [
  'Current-Year Realized', 'Annualized', 'Contract Term', 'One-Time'
]

export function EventForm({
  categories,
  businessUnits,
  costCenters,
  suppliers: initialSuppliers,
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

  // Suppliers state — allows adding new ones inline
  const [suppliers, setSuppliers] = useState<Option[]>(initialSuppliers)
  const [showAddSupplier, setShowAddSupplier] = useState(false)
  const [newSupplierName, setNewSupplierName] = useState('')
  const [addingSupplier, setAddingSupplier] = useState(false)

  const [projectType, setProjectType] = useState<'Sourcing' | 'Support'>('Sourcing')

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
    buyer_name: '',
    notes: '',
  })

  const handleChange = (field: string, value: string) => {
    setForm(prev => ({ ...prev, [field]: value }))
  }

  const handleProjectTypeChange = (type: 'Sourcing' | 'Support') => {
    setProjectType(type)
    setForm(prev => ({
      ...prev,
      event_status: type === 'Sourcing' ? 'Pipeline' : 'Not Started',
      event_type: '',
      sourcing_method: '',
    }))
  }

  const handleAddSupplier = async () => {
    const name = newSupplierName.trim()
    if (!name) return

    setAddingSupplier(true)
    const { data: { user } } = await supabase.auth.getUser()
    if (!user) {
      setError('You must be logged in')
      setAddingSupplier(false)
      return
    }

    const { data: profile } = await supabase
      .from('profiles')
      .select('organization_id')
      .eq('id', user!.id)
      .single()

    if (!profile?.organization_id) {
      setError('No organization found')
      setAddingSupplier(false)
      return
    }

    const { data, error: insertError } = await supabase
      .from('suppliers')
      .insert({
        supplier_name: name,
        organization_id: profile.organization_id,
        created_by: user.id,
      })
      .select('id, supplier_name')
      .single()

    if (insertError) {
      setError(insertError.message)
      setAddingSupplier(false)
      return
    }

    // Add to local list and select it
    setSuppliers(prev => [...prev, { id: data.id, supplier_name: data.supplier_name }])
    setForm(prev => ({ ...prev, incumbent_supplier_id: data.id }))
    setNewSupplierName('')
    setShowAddSupplier(false)
    setAddingSupplier(false)
    setError(null)
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

    const isSupport = projectType === 'Support'

    const eventData: Record<string, any> = {
      event_name: form.event_name,
      event_description: form.event_description || null,
      event_type: form.event_type || null,
      project_type: projectType,
      buyer_name: form.buyer_name || null,
      notes: form.notes || null,
      organization_id: profile.organization_id,
      procurement_owner_id: user.id,
      created_by: user.id,
      updated_by: user.id,
      currency_code: 'USD',
      fx_rate_to_usd: 1.0,
      event_status: form.event_status,
      event_start_date: form.event_start_date || null,
      event_close_date: form.event_close_date || null,
      category_id: form.category_id || null,
      business_unit_id: form.business_unit_id || null,
      cost_center_id: form.cost_center_id || null,
      incumbent_supplier_id: form.incumbent_supplier_id || null,
    }

    // Sourcing-only fields
    if (!isSupport) {
      eventData.sourcing_method = form.sourcing_method || null
      eventData.contract_start_date = form.contract_start_date || null
      eventData.contract_end_date = form.contract_end_date || null
      eventData.recognition_start_date = form.recognition_start_date || null
      eventData.recognition_end_date = form.recognition_end_date || null
      eventData.official_reporting_basis = form.official_reporting_basis
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

  const inputClass = 'mt-1 block w-full rounded-lg border border-gray-300 px-3 py-2 text-sm focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500 dark:border-gray-600'
  const labelClass = 'block text-sm font-medium text-gray-700 dark:text-gray-300'
  const sectionClass = 'rounded-lg border border-gray-200 bg-white p-6 shadow-sm dark:border-gray-700 dark:bg-gray-800'

  const currentTypes = projectType === 'Sourcing' ? EVENT_TYPES : SUPPORT_TYPES
  const currentStatuses = projectType === 'Sourcing' ? SOURCING_STATUSES : SUPPORT_STATUSES

  return (
    <form onSubmit={handleSubmit} className="mt-6 space-y-6">
      {error && (
        <div className="rounded-lg bg-red-50 p-4 text-sm text-red-700">
          {error}
        </div>
      )}

      {/* Project Type Toggle */}
      <div className={sectionClass}>
        <h2 className="mb-4 text-lg font-semibold text-gray-900 dark:text-gray-100">Project Type</h2>
        <div className="flex gap-3">
          <button
            type="button"
            onClick={() => handleProjectTypeChange('Sourcing')}
            className={`flex flex-1 items-center justify-center gap-2 rounded-lg border-2 px-4 py-3 text-sm font-medium transition-colors ${
              projectType === 'Sourcing'
                ? 'border-indigo-600 bg-indigo-50 text-indigo-700 dark:border-indigo-500 dark:bg-indigo-900/30 dark:text-indigo-300'
                : 'border-gray-200 text-gray-600 hover:border-gray-300 dark:border-gray-600 dark:text-gray-400'
            }`}
          >
            <Briefcase className="h-5 w-5" />
            <div className="text-left">
              <div>Sourcing Project</div>
              <div className={`text-xs font-normal ${projectType === 'Sourcing' ? 'text-indigo-600 dark:text-indigo-400' : 'text-gray-400'}`}>
                Commercial pipeline with savings
              </div>
            </div>
          </button>
          <button
            type="button"
            onClick={() => handleProjectTypeChange('Support')}
            className={`flex flex-1 items-center justify-center gap-2 rounded-lg border-2 px-4 py-3 text-sm font-medium transition-colors ${
              projectType === 'Support'
                ? 'border-indigo-600 bg-indigo-50 text-indigo-700 dark:border-indigo-500 dark:bg-indigo-900/30 dark:text-indigo-300'
                : 'border-gray-200 text-gray-600 hover:border-gray-300 dark:border-gray-600 dark:text-gray-400'
            }`}
          >
            <LifeBuoy className="h-5 w-5" />
            <div className="text-left">
              <div>Support / Non-Commercial</div>
              <div className={`text-xs font-normal ${projectType === 'Support' ? 'text-indigo-600 dark:text-indigo-400' : 'text-gray-400'}`}>
                Vendor issues, tickets, $0 savings
              </div>
            </div>
          </button>
        </div>
      </div>

      {/* Basic Info */}
      <div className={sectionClass}>
        <h2 className="mb-4 text-lg font-semibold text-gray-900 dark:text-gray-100">Basic Information</h2>
        <div className="grid grid-cols-1 gap-4 md:grid-cols-2">
          <div className="md:col-span-2">
            <label className={labelClass}>{projectType === 'Sourcing' ? 'Event' : 'Project'} Name *</label>
            <input
              type="text"
              required
              value={form.event_name}
              onChange={(e) => handleChange('event_name', e.target.value)}
              className={inputClass}
              placeholder={projectType === 'Sourcing' ? "e.g. CRM Software Renewal" : "e.g. Vendor billing dispute — Salesforce"}
            />
          </div>
          <div className="md:col-span-2">
            <label className={labelClass}>Description</label>
            <textarea
              value={form.event_description}
              onChange={(e) => handleChange('event_description', e.target.value)}
              className={inputClass}
              rows={3}
              placeholder="Brief description"
            />
          </div>
          <div>
            <label className={labelClass}>{projectType === 'Sourcing' ? 'Event Type' : 'Support Type'} *</label>
            <select
              required
              value={form.event_type}
              onChange={(e) => handleChange('event_type', e.target.value)}
              className={inputClass}
            >
              <option value="">Select type...</option>
              {currentTypes.map((type) => (
                <option key={type} value={type}>{type}</option>
              ))}
            </select>
          </div>
          <div>
            <label className={labelClass}>Status</label>
            <select
              value={form.event_status}
              onChange={(e) => handleChange('event_status', e.target.value)}
              className={inputClass}
            >
              {currentStatuses.map((status) => (
                <option key={status} value={status}>{status}</option>
              ))}
            </select>
          </div>
          {projectType === 'Sourcing' && (
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
          )}
          <div>
            <label className={labelClass}>IP Owner / Buyer</label>
            <input
              type="text"
              value={form.buyer_name}
              onChange={(e) => handleChange('buyer_name', e.target.value)}
              className={inputClass}
              placeholder="e.g. Jane Smith"
            />
          </div>
        </div>
      </div>

      {/* Classification */}
      <div className={sectionClass}>
        <h2 className="mb-4 text-lg font-semibold text-gray-900 dark:text-gray-100">Classification</h2>
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
            <div className="mt-1 flex gap-2">
              <select
                value={form.incumbent_supplier_id}
                onChange={(e) => handleChange('incumbent_supplier_id', e.target.value)}
                className={`${inputClass} flex-1`}
              >
                <option value="">Select supplier...</option>
                {suppliers.map((s) => (
                  <option key={s.id} value={s.id}>{s.supplier_name}</option>
                ))}
              </select>
              <button
                type="button"
                onClick={() => setShowAddSupplier(!showAddSupplier)}
                className="flex items-center gap-1 rounded-lg border border-gray-300 px-3 py-2 text-sm font-medium text-gray-600 hover:bg-gray-50 dark:border-gray-600 dark:text-gray-300 dark:hover:bg-gray-700"
                title="Add new supplier"
              >
                {showAddSupplier ? <X className="h-4 w-4" /> : <Plus className="h-4 w-4" />}
                {showAddSupplier ? 'Cancel' : 'New'}
              </button>
            </div>
            {showAddSupplier && (
              <div className="mt-2 flex gap-2">
                <input
                  type="text"
                  value={newSupplierName}
                  onChange={(e) => setNewSupplierName(e.target.value)}
                  onKeyDown={(e) => { if (e.key === 'Enter') { e.preventDefault(); handleAddSupplier() } }}
                  className={`${inputClass} flex-1`}
                  placeholder="Enter supplier name..."
                  autoFocus
                />
                <button
                  type="button"
                  onClick={handleAddSupplier}
                  disabled={addingSupplier || !newSupplierName.trim()}
                  className="rounded-lg bg-indigo-600 px-4 py-2 text-sm font-medium text-white transition-colors hover:bg-indigo-700 disabled:opacity-50"
                >
                  {addingSupplier ? 'Adding...' : 'Add'}
                </button>
              </div>
            )}
          </div>
        </div>
      </div>

      {/* Dates */}
      <div className={sectionClass}>
        <h2 className="mb-4 text-lg font-semibold text-gray-900 dark:text-gray-100">Dates</h2>
        <div className="grid grid-cols-1 gap-4 md:grid-cols-2">
          <div>
            <label className={labelClass}>{projectType === 'Sourcing' ? 'Event Start Date' : 'Start Date'}</label>
            <input
              type="date"
              value={form.event_start_date}
              onChange={(e) => handleChange('event_start_date', e.target.value)}
              className={inputClass}
            />
          </div>
          <div>
            <label className={labelClass}>{projectType === 'Sourcing' ? 'Event Close Date' : 'Due Date'}</label>
            <input
              type="date"
              value={form.event_close_date}
              onChange={(e) => handleChange('event_close_date', e.target.value)}
              className={inputClass}
            />
          </div>
          {projectType === 'Sourcing' && (
            <>
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
            </>
          )}
        </div>
      </div>

      {/* Notes */}
      <div className={sectionClass}>
        <h2 className="mb-4 text-lg font-semibold text-gray-900 dark:text-gray-100">Notes</h2>
        <textarea
          value={form.notes}
          onChange={(e) => handleChange('notes', e.target.value)}
          className={inputClass}
          rows={4}
          placeholder="Add any notes, context, or updates about this project..."
        />
      </div>

      {/* Submit */}
      <div className="flex justify-end gap-3">
        <button
          type="button"
          onClick={() => router.push('/events')}
          className="rounded-lg border border-gray-300 px-4 py-2 text-sm font-medium text-gray-700 hover:bg-gray-50 dark:border-gray-600 dark:text-gray-300 dark:hover:bg-gray-800"
        >
          Cancel
        </button>
        <button
          type="submit"
          disabled={loading}
          className="rounded-lg bg-indigo-600 px-4 py-2 text-sm font-medium text-white transition-colors hover:bg-indigo-700 disabled:opacity-50"
        >
          {loading ? 'Creating...' : `Create ${projectType === 'Sourcing' ? 'Event' : 'Project'}`}
        </button>
      </div>
    </form>
  )
}