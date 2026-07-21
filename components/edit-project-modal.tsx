'use client'

import { useState } from 'react'
import { createClient } from '@/lib/supabase/client'
import { X } from 'lucide-react'
import { clsx } from 'clsx'

type Option = { id: string; category_name?: string; business_unit_name?: string; cost_center_name?: string; supplier_name?: string }

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

export function EditProjectModal({
  project,
  categories,
  businessUnits,
  costCenters,
  suppliers,
  onClose,
  onSaved,
}: {
  project: any
  categories: Option[]
  businessUnits: Option[]
  costCenters: Option[]
  suppliers: Option[]
  onClose: () => void
  onSaved: () => void
}) {
  const supabase = createClient()
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const isSupport = project.project_type === 'Support'

  const [form, setForm] = useState({
    event_name: project.event_name || '',
    event_description: project.event_description || '',
    event_type: project.event_type || '',
    sourcing_method: project.sourcing_method || '',
    event_status: project.event_status || 'Pipeline',
    buyer_name: project.buyer_name || '',
    category_id: project.category_id || '',
    business_unit_id: project.business_unit_id || '',
    cost_center_id: project.cost_center_id || '',
    incumbent_supplier_id: project.incumbent_supplier_id || '',
    event_start_date: project.event_start_date || '',
    event_close_date: project.event_close_date || '',
    notes: project.notes || '',
  })

  const handleChange = (field: string, value: string) => {
    setForm(prev => ({ ...prev, [field]: value }))
  }

  const handleSave = async () => {
    setLoading(true)
    setError(null)

    const updates: Record<string, any> = {
      event_name: form.event_name,
      event_description: form.event_description || null,
      event_type: form.event_type || null,
      event_status: form.event_status,
      buyer_name: form.buyer_name || null,
      event_start_date: form.event_start_date || null,
      event_close_date: form.event_close_date || null,
      category_id: form.category_id || null,
      business_unit_id: form.business_unit_id || null,
      cost_center_id: form.cost_center_id || null,
      incumbent_supplier_id: form.incumbent_supplier_id || null,
      notes: form.notes || null,
      updated_at: new Date().toISOString(),
    }

    if (!isSupport) {
      updates.sourcing_method = form.sourcing_method || null
    }

    const { error: updateError } = await supabase
      .from('sourcing_events')
      .update(updates)
      .eq('id', project.id)

    if (updateError) {
      setError(updateError.message)
      setLoading(false)
      return
    }

    setLoading(false)
    onSaved()
  }

  const handleDelete = async () => {
    if (!confirm('Delete this entire project? This will remove all scope lines, baselines, offers, awards, and savings calculations. This CANNOT be undone.')) return
    setLoading(true)
    setError(null)

    const { error: deleteError } = await supabase
      .from('sourcing_events')
      .delete()
      .eq('id', project.id)

    if (deleteError) {
      setError(deleteError.message)
      setLoading(false)
      return
    }

    setLoading(false)
    window.location.href = '/events'
  }

  const inputClass = 'mt-1 block w-full rounded-lg border border-gray-300 px-3 py-2 text-sm focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500 dark:border-gray-600 dark:bg-gray-800 dark:text-gray-100'
  const labelClass = 'block text-xs font-medium text-gray-600 dark:text-gray-400'
  const statuses = isSupport ? SUPPORT_STATUSES : SOURCING_STATUSES

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4" onClick={onClose}>
      <div
        className="max-h-[90vh] w-full max-w-2xl overflow-y-auto rounded-lg bg-white p-6 shadow-xl dark:bg-gray-800"
        onClick={(e) => e.stopPropagation()}
      >
        {/* Header */}
        <div className="mb-6 flex items-center justify-between">
          <h2 className="text-xl font-bold text-gray-900 dark:text-gray-100">Edit Project</h2>
          <button onClick={onClose} className="text-gray-400 hover:text-gray-600 dark:text-gray-500 dark:hover:text-gray-300">
            <X className="h-5 w-5" />
          </button>
        </div>

        {error && (
          <div className="mb-4 rounded-lg bg-red-50 p-4 text-sm text-red-700 dark:bg-red-900/30 dark:text-red-400">
            {error}
          </div>
        )}

        {/* Form fields */}
        <div className="space-y-4">
          {/* Name */}
          <div>
            <label className={labelClass}>Project Name *</label>
            <input
              type="text"
              required
              value={form.event_name}
              onChange={(e) => handleChange('event_name', e.target.value)}
              className={inputClass}
            />
          </div>

          {/* Description */}
          <div>
            <label className={labelClass}>Description</label>
            <textarea
              value={form.event_description}
              onChange={(e) => handleChange('event_description', e.target.value)}
              className={inputClass}
              rows={2}
            />
          </div>

          {/* Status + Type + Method */}
          <div className="grid grid-cols-2 gap-4">
            <div>
              <label className={labelClass}>Status</label>
              <select value={form.event_status} onChange={(e) => handleChange('event_status', e.target.value)} className={inputClass}>
                {statuses.map(s => <option key={s} value={s}>{s}</option>)}
              </select>
            </div>
            <div>
              <label className={labelClass}>Event Type</label>
              <input
                type="text"
                value={form.event_type}
                onChange={(e) => handleChange('event_type', e.target.value)}
                className={inputClass}
              />
            </div>
            {!isSupport && (
              <div>
                <label className={labelClass}>Sourcing Method</label>
                <select value={form.sourcing_method} onChange={(e) => handleChange('sourcing_method', e.target.value)} className={inputClass}>
                  <option value="">Select method...</option>
                  {SOURCING_METHODS.map(m => <option key={m} value={m}>{m}</option>)}
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

          {/* Classification */}
          <div className="grid grid-cols-2 gap-4">
            <div>
              <label className={labelClass}>Category</label>
              <select value={form.category_id} onChange={(e) => handleChange('category_id', e.target.value)} className={inputClass}>
                <option value="">Select category...</option>
                {categories.map(c => <option key={c.id} value={c.id}>{c.category_name}</option>)}
              </select>
            </div>
            <div>
              <label className={labelClass}>Business Unit</label>
              <select value={form.business_unit_id} onChange={(e) => handleChange('business_unit_id', e.target.value)} className={inputClass}>
                <option value="">Select business unit...</option>
                {businessUnits.map(b => <option key={b.id} value={b.id}>{b.business_unit_name}</option>)}
              </select>
            </div>
            <div>
              <label className={labelClass}>Cost Center</label>
              <select value={form.cost_center_id} onChange={(e) => handleChange('cost_center_id', e.target.value)} className={inputClass}>
                <option value="">Select cost center...</option>
                {costCenters.map(c => <option key={c.id} value={c.id}>{c.cost_center_name}</option>)}
              </select>
            </div>
            <div>
              <label className={labelClass}>Incumbent Supplier</label>
              <select value={form.incumbent_supplier_id} onChange={(e) => handleChange('incumbent_supplier_id', e.target.value)} className={inputClass}>
                <option value="">Select supplier...</option>
                {suppliers.map(s => <option key={s.id} value={s.id}>{s.supplier_name}</option>)}
              </select>
            </div>
          </div>

          {/* Dates */}
          <div className="grid grid-cols-2 gap-4">
            <div>
              <label className={labelClass}>{isSupport ? 'Start Date' : 'Project Start Date'}</label>
              <input type="date" value={form.event_start_date} onChange={(e) => handleChange('event_start_date', e.target.value)} className={inputClass} />
            </div>
            <div>
              <label className={labelClass}>{isSupport ? 'Due Date' : 'Project Close Date'}</label>
              <input type="date" value={form.event_close_date} onChange={(e) => handleChange('event_close_date', e.target.value)} className={inputClass} />
            </div>
          </div>

          {/* Notes */}
          <div>
            <label className={labelClass}>Notes</label>
            <textarea
              value={form.notes}
              onChange={(e) => handleChange('notes', e.target.value)}
              className={inputClass}
              rows={3}
            />
          </div>
        </div>

        {/* Action buttons */}
        <div className="mt-6 flex items-center justify-between">
          <button
            onClick={handleDelete}
            disabled={loading}
            className="rounded-lg border border-red-300 px-4 py-2 text-sm font-medium text-red-600 hover:bg-red-50 dark:border-red-800 dark:text-red-400 dark:hover:bg-red-900/30"
          >
            Delete Project
          </button>
          <div className="flex gap-3">
            <button
              onClick={onClose}
              className="rounded-lg border border-gray-300 px-4 py-2 text-sm font-medium text-gray-700 hover:bg-gray-50 dark:border-gray-600 dark:text-gray-300 dark:hover:bg-gray-700"
            >
              Cancel
            </button>
            <button
              onClick={handleSave}
              disabled={loading}
              className="rounded-lg bg-indigo-600 px-4 py-2 text-sm font-medium text-white transition-colors hover:bg-indigo-700 disabled:opacity-50"
            >
              {loading ? 'Saving...' : 'Save Changes'}
            </button>
          </div>
        </div>
      </div>
    </div>
  )
}