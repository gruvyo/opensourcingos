'use client'

import { useState, useEffect, useRef } from 'react'
import { createClient } from '@/lib/supabase/client'
import { X } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { ConfirmDialog } from '@/components/ui/confirm-dialog'
import { Input, Select } from '@/components/ui/input'
import type { Tables } from '@/lib/database.types'

type Option = { id: string; category_name?: string; business_unit_name?: string; cost_center_name?: string; supplier_name?: string }
type Project = Pick<
  Tables<'sourcing_events'>,
  | 'id'
  | 'project_type'
  | 'event_name'
  | 'event_description'
  | 'event_type'
  | 'event_status'
  | 'buyer_name'
  | 'category_id'
  | 'business_unit_id'
  | 'cost_center_id'
  | 'incumbent_supplier_id'
  | 'event_start_date'
  | 'project_due_date'
  | 'event_close_date'
  | 'contract_start_date'
  | 'contract_end_date'
  | 'notes'
>

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
  projectDescriptionsEnabled,
  projectOwnersEnabled,
  projectCostCentersEnabled,
  projectCategoriesEnabled,
  projectBusinessUnitsEnabled,
  onClose,
  onSaved,
}: {
  project: Project
  categories: Option[]
  businessUnits: Option[]
  costCenters: Option[]
  suppliers: Option[]
  projectDescriptionsEnabled: boolean
  projectOwnersEnabled: boolean
  projectCostCentersEnabled: boolean
  projectCategoriesEnabled: boolean
  projectBusinessUnitsEnabled: boolean
  onClose: () => void
  onSaved: () => void
}) {
  const supabase = createClient()
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [showDeleteConfirm, setShowDeleteConfirm] = useState(false)
  const dialogRef = useRef<HTMLDivElement>(null)
  const titleId = 'edit-project-title'

  const isSupport = project.project_type === 'Support'

  // Accessible dialog behavior: lock scroll, focus in, trap Tab, Esc to close,
  // and restore focus to the trigger on close.
  useEffect(() => {
    const prevActive = document.activeElement as HTMLElement | null
    document.body.style.overflow = 'hidden'

    const focusables = () =>
      Array.from(
        dialogRef.current?.querySelectorAll<HTMLElement>(
          'a[href], button:not([disabled]), input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])',
        ) ?? [],
      )

    focusables()[0]?.focus()

    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        onClose()
        return
      }
      if (e.key === 'Tab') {
        const list = focusables()
        if (list.length === 0) return
        const first = list[0]
        const last = list[list.length - 1]
        if (e.shiftKey && document.activeElement === first) {
          e.preventDefault()
          last.focus()
        } else if (!e.shiftKey && document.activeElement === last) {
          e.preventDefault()
          first.focus()
        }
      }
    }

    document.addEventListener('keydown', onKey)
    return () => {
      document.removeEventListener('keydown', onKey)
      document.body.style.overflow = ''
      prevActive?.focus?.()
    }
  }, [onClose])

  const [form, setForm] = useState({
    event_name: project.event_name || '',
    event_description: project.event_description || '',
    event_type: project.event_type || '',
    event_status: project.event_status || 'Pipeline',
    buyer_name: project.buyer_name || '',
    category_id: project.category_id || '',
    business_unit_id: project.business_unit_id || '',
    cost_center_id: project.cost_center_id || '',
    incumbent_supplier_id: project.incumbent_supplier_id || '',
    event_start_date: project.event_start_date || '',
    project_due_date: project.project_due_date || '',
    event_close_date: project.event_close_date || '',
    // The contract start is what "Savings start" defaults from on the
    // Calculations tab, which in turn seeds the savings schedule. It was
    // readable on the Projects list but not editable anywhere.
    contract_start_date: project.contract_start_date || '',
    contract_end_date: project.contract_end_date || '',
    notes: project.notes || '',
  })

  const handleChange = (field: string, value: string) => {
    setForm(prev => ({ ...prev, [field]: value }))
  }

  const handleSave = async () => {
    setLoading(true)
    setError(null)

    const updates: Record<string, string | null> = {
      event_name: form.event_name,
      event_type: form.event_type || null,
      event_status: form.event_status,
      event_start_date: form.event_start_date || null,
      project_due_date: form.project_due_date || null,
      event_close_date: form.event_close_date || null,
      contract_start_date: form.contract_start_date || null,
      contract_end_date: form.contract_end_date || null,
      incumbent_supplier_id: form.incumbent_supplier_id || null,
      notes: form.notes || null,
      updated_at: new Date().toISOString(),
    }

    if (projectDescriptionsEnabled) {
      updates.event_description = form.event_description || null
    }

    if (projectOwnersEnabled) {
      updates.buyer_name = form.buyer_name || null
    }

    if (projectCostCentersEnabled) {
      updates.cost_center_id = form.cost_center_id || null
    }

    if (projectCategoriesEnabled) {
      updates.category_id = form.category_id || null
    }

    if (projectBusinessUnitsEnabled) {
      updates.business_unit_id = form.business_unit_id || null
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

  const labelClass = 'mb-1 block text-xs font-medium text-[var(--text-2)]'
  const textareaClass = 'w-full rounded-md border border-[var(--border-strong)] bg-[var(--surface)] px-3 py-2 text-sm text-[var(--text)] placeholder:text-[var(--text-3)] transition-colors focus:border-[var(--brand)] focus:outline-none focus:ring-2 focus:ring-[var(--brand)]/30'
  const statuses = isSupport ? SUPPORT_STATUSES : SOURCING_STATUSES

  return (
    <>
      <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4" onClick={onClose}>
      <div
        ref={dialogRef}
        role="dialog"
        aria-modal="true"
        aria-labelledby={titleId}
        className="max-h-[90vh] w-full max-w-2xl overflow-y-auto rounded-lg bg-[var(--surface)] p-6 shadow-xl"
        onClick={(e) => e.stopPropagation()}
      >
        {/* Header */}
        <div className="mb-6 flex items-center justify-between">
          <h2 id={titleId} className="text-xl font-bold text-[var(--text)]">Edit Project</h2>
          <button type="button" onClick={onClose} aria-label="Close dialog" className="rounded-md p-1 text-[var(--text-3)] transition-colors hover:bg-[var(--surface-2)] hover:text-[var(--text)]">
            <X className="h-5 w-5" />
          </button>
        </div>

        {error && (
          <div className="mb-4 rounded-md bg-[var(--danger-soft)] px-4 py-3 text-sm text-[var(--danger)]" role="alert">
            {error}
          </div>
        )}

        {/* Form fields */}
        <div className="space-y-4">
          <div>
            <label htmlFor="ep-name" className={labelClass}>Project Name *</label>
            <Input id="ep-name" type="text" required value={form.event_name} onChange={(e) => handleChange('event_name', e.target.value)} />
          </div>

          {projectDescriptionsEnabled ? (
            <div>
              <label htmlFor="ep-desc" className={labelClass}>Description</label>
              <textarea id="ep-desc" value={form.event_description} onChange={(e) => handleChange('event_description', e.target.value)} className={textareaClass} rows={2} />
            </div>
          ) : null}

          <div className="grid grid-cols-2 gap-4">
            <div>
              <label htmlFor="ep-status" className={labelClass}>Status</label>
              <Select id="ep-status" value={form.event_status} onChange={(e) => handleChange('event_status', e.target.value)}>
                {statuses.map(s => <option key={s} value={s}>{s}</option>)}
              </Select>
            </div>
            <div>
              <label htmlFor="ep-type" className={labelClass}>Event Type</label>
              <Input id="ep-type" type="text" value={form.event_type} onChange={(e) => handleChange('event_type', e.target.value)} />
            </div>
            {projectOwnersEnabled ? (
              <div>
                <label htmlFor="ep-buyer" className={labelClass}>Owner / Buyer</label>
                <Input id="ep-buyer" type="text" value={form.buyer_name} onChange={(e) => handleChange('buyer_name', e.target.value)} placeholder="e.g. Jane Smith" />
              </div>
            ) : null}
          </div>

          <div className="grid grid-cols-2 gap-4">
            {projectCategoriesEnabled ? (
              <div>
                <label htmlFor="ep-category" className={labelClass}>Category</label>
                <Select id="ep-category" value={form.category_id} onChange={(e) => handleChange('category_id', e.target.value)}>
                  <option value="">Select category...</option>
                  {categories.map(c => <option key={c.id} value={c.id}>{c.category_name}</option>)}
                </Select>
              </div>
            ) : null}
            {projectBusinessUnitsEnabled ? (
              <div>
                <label htmlFor="ep-bu" className={labelClass}>Business Unit</label>
                <Select id="ep-bu" value={form.business_unit_id} onChange={(e) => handleChange('business_unit_id', e.target.value)}>
                  <option value="">Select business unit...</option>
                  {businessUnits.map(b => <option key={b.id} value={b.id}>{b.business_unit_name}</option>)}
                </Select>
              </div>
            ) : null}
            {projectCostCentersEnabled ? (
              <div>
                <label htmlFor="ep-cc" className={labelClass}>Cost Center</label>
                <Select id="ep-cc" value={form.cost_center_id} onChange={(e) => handleChange('cost_center_id', e.target.value)}>
                  <option value="">Select cost center...</option>
                  {costCenters.map(c => <option key={c.id} value={c.id}>{c.cost_center_name}</option>)}
                </Select>
              </div>
            ) : null}
            <div>
              <label htmlFor="ep-supplier" className={labelClass}>Incumbent Supplier</label>
              <Select id="ep-supplier" value={form.incumbent_supplier_id} onChange={(e) => handleChange('incumbent_supplier_id', e.target.value)}>
                <option value="">Select supplier...</option>
                {suppliers.map(s => <option key={s.id} value={s.id}>{s.supplier_name}</option>)}
              </Select>
            </div>
          </div>

          <div className="grid grid-cols-1 gap-4 sm:grid-cols-3">
            <div>
              <label htmlFor="ep-start" className={labelClass}>{isSupport ? 'Start Date' : 'Project Start Date'}</label>
              <Input id="ep-start" type="date" value={form.event_start_date} onChange={(e) => handleChange('event_start_date', e.target.value)} />
            </div>
            <div>
              <label htmlFor="ep-due" className={labelClass}>Project Due Date</label>
              <Input id="ep-due" type="date" value={form.project_due_date} onChange={(e) => handleChange('project_due_date', e.target.value)} />
            </div>
            <div>
              <label htmlFor="ep-close" className={labelClass}>Completion Date</label>
              <Input id="ep-close" type="date" value={form.event_close_date} onChange={(e) => handleChange('event_close_date', e.target.value)} />
            </div>
          </div>

          {!isSupport && (
            <div className="grid grid-cols-2 gap-4">
              <div>
                <label htmlFor="ep-cstart" className={labelClass}>Contract Start Date</label>
                <Input id="ep-cstart" type="date" value={form.contract_start_date} onChange={(e) => handleChange('contract_start_date', e.target.value)} />
                <p className="mt-1 text-[11px] text-[var(--text-3)]">
                  Savings start defaults from this, and the schedule starts from that.
                </p>
              </div>
              <div>
                <label htmlFor="ep-cend" className={labelClass}>Contract End Date</label>
                <Input id="ep-cend" type="date" value={form.contract_end_date} onChange={(e) => handleChange('contract_end_date', e.target.value)} />
                <p className="mt-1 text-[11px] text-[var(--text-3)]">
                  The contract&apos;s own end. The savings window comes from the deal term instead.
                </p>
              </div>
            </div>
          )}

          <div>
            <label htmlFor="ep-notes" className={labelClass}>Notes</label>
            <textarea id="ep-notes" value={form.notes} onChange={(e) => handleChange('notes', e.target.value)} className={textareaClass} rows={3} />
          </div>
        </div>

        {/* Action buttons */}
        <div className="mt-6 flex items-center justify-between">
          <Button variant="danger" onClick={() => setShowDeleteConfirm(true)} disabled={loading}>
            Delete Project
          </Button>
          <div className="flex gap-3">
            <Button variant="secondary" onClick={onClose}>Cancel</Button>
            <Button onClick={handleSave} disabled={loading}>
              {loading ? 'Saving…' : 'Save Changes'}
            </Button>
          </div>
        </div>
        </div>
      </div>
      {showDeleteConfirm && (
        <ConfirmDialog
          title="Delete this project?"
          description="This removes the project and all of its scope lines, baselines, offers, awards, and savings calculations. This cannot be undone."
          confirmLabel="Delete Project"
          pendingLabel="Deleting Project..."
          onConfirm={handleDelete}
          onCancel={() => setShowDeleteConfirm(false)}
        />
      )}
    </>
  )
}
