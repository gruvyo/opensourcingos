'use client'

import { useState } from 'react'
import { useRouter } from 'next/navigation'
import { createClient } from '@/lib/supabase/client'
import { Briefcase, LifeBuoy, Plus, X } from 'lucide-react'
import { Card } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input, Select } from '@/components/ui/input'

type Option = { id: string; category_name?: string; business_unit_name?: string; cost_center_name?: string; supplier_name?: string }
type ChoiceOption = {
  id: string
  choice_type: 'event_type' | 'event_status' | 'owner'
  project_type: 'Sourcing' | 'Support' | null
  label: string
}

export function EventForm({
  categories,
  businessUnits,
  costCenters,
  suppliers: initialSuppliers,
  choiceOptions,
  defaultCurrency,
  supportProjectsEnabled,
  projectDescriptionsEnabled,
  projectOwnersEnabled,
  projectCostCentersEnabled,
  projectCategoriesEnabled,
  projectBusinessUnitsEnabled,
  projectUpdatesEnabled,
  projectIncumbentSuppliersEnabled,
}: {
  categories: Option[]
  businessUnits: Option[]
  costCenters: Option[]
  suppliers: Option[]
  choiceOptions: ChoiceOption[]
  defaultCurrency: string
  supportProjectsEnabled: boolean
  projectDescriptionsEnabled: boolean
  projectOwnersEnabled: boolean
  projectCostCentersEnabled: boolean
  projectCategoriesEnabled: boolean
  projectBusinessUnitsEnabled: boolean
  projectUpdatesEnabled: boolean
  projectIncumbentSuppliersEnabled: boolean
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

  const choicesFor = (choiceType: ChoiceOption['choice_type'], type: 'Sourcing' | 'Support' | null) =>
    choiceOptions.filter(choice => choice.choice_type === choiceType && choice.project_type === type)

  const sourcingStatuses = choicesFor('event_status', 'Sourcing')

  const [form, setForm] = useState({
    event_name: '',
    event_description: '',
    event_type: '',
    category_id: '',
    business_unit_id: '',
    cost_center_id: '',
    incumbent_supplier_id: '',
    event_status: sourcingStatuses[0]?.label || '',
    event_start_date: '',
    project_due_date: '',
    buyer_name: '',
    notes: '',
  })

  const handleChange = (field: string, value: string) => {
    setForm(prev => ({ ...prev, [field]: value }))
  }

  const handleProjectTypeChange = (type: 'Sourcing' | 'Support') => {
    const statuses = choicesFor('event_status', type)
    setProjectType(type)
    setForm(prev => ({
      ...prev,
      event_status: statuses[0]?.label || '',
      event_type: '',
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
        // NOTE: the suppliers table has no created_by column (it carries only
        // created_at/updated_at). Sending it made PostgREST reject the insert
        // with 400 "column suppliers.created_by does not exist", so adding a
        // new vendor inline always failed silently — and most new projects
        // involve a first-time vendor.
        supplier_status: 'Active',
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

    const eventData = {
      event_name: form.event_name,
      event_description: form.event_description || null,
      event_type: form.event_type || null,
      project_type: projectType,
      buyer_name: projectOwnersEnabled ? form.buyer_name || null : null,
      // Keep the legacy field populated for rollback compatibility. The same
      // content is written to the append-only timeline immediately below.
      notes: form.notes || null,
      organization_id: profile.organization_id,
      procurement_owner_id: user.id,
      currency_code: defaultCurrency,
      fx_rate_to_usd: 1.0,
      event_status: form.event_status,
      event_start_date: form.event_start_date || null,
      project_due_date: form.project_due_date || null,
      category_id: projectCategoriesEnabled ? form.category_id || null : null,
      business_unit_id: projectBusinessUnitsEnabled ? form.business_unit_id || null : null,
      cost_center_id: projectCostCentersEnabled ? form.cost_center_id || null : null,
      incumbent_supplier_id: projectIncumbentSuppliersEnabled ? form.incumbent_supplier_id || null : null,
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

    if (projectUpdatesEnabled && form.notes.trim()) {
      const { error: updateError } = await supabase
        .from('project_updates')
        .insert({
          organization_id: profile.organization_id,
          event_id: data.id,
          body: form.notes.trim(),
          created_by: user.id,
        })

      if (updateError) {
        // Compensate for the failed second write so the user never receives a
        // half-created project with its initial update missing.
        await supabase.from('sourcing_events').delete().eq('id', data.id)
        setError(`The project was not created because its initial update could not be saved: ${updateError.message}`)
        setLoading(false)
        return
      }
    }

    router.push(`/events/${data.id}`)
    router.refresh()
  }

  const textareaClass = 'mt-1 block w-full rounded-md border border-[var(--border-strong)] bg-[var(--surface)] px-3 py-2 text-sm text-[var(--text)] placeholder:text-[var(--text-3)] transition-colors focus:border-[var(--brand)] focus:outline-none focus:ring-2 focus:ring-[var(--brand)]/30'
  const labelClass = 'block text-sm font-medium text-[var(--text-2)]'

  const currentTypes = choicesFor('event_type', projectType)
  const currentStatuses = choicesFor('event_status', projectType)
  const owners = choicesFor('owner', null)

  return (
    <form onSubmit={handleSubmit} className="mt-6 space-y-6">
      {error && (
        <div role="alert" className="rounded-lg bg-red-50 p-4 text-sm text-red-700 dark:bg-red-950/30 dark:text-red-400">
          {error}
        </div>
      )}

      {/* Project Type Toggle */}
      <Card className="p-6">
        <h2 className="mb-4 text-lg font-semibold text-[var(--text)]">Project Type</h2>
        <div className="flex gap-3">
          <button
            type="button"
            aria-pressed={projectType === 'Sourcing'}
            onClick={() => handleProjectTypeChange('Sourcing')}
            className={`flex flex-1 items-center justify-center gap-2 rounded-lg border-2 px-4 py-3 text-sm font-medium transition-colors ${
              projectType === 'Sourcing'
                ? 'border-[var(--brand)] bg-[var(--brand-soft)] text-[var(--brand-ink)]'
                : 'border-[var(--border)] text-[var(--text-2)] hover:border-[var(--border-strong)]'
            }`}
          >
            <Briefcase className="h-5 w-5" />
            <div className="text-left">
              <div>Sourcing Project</div>
              <div className={`text-xs font-normal ${projectType === 'Sourcing' ? 'text-[var(--brand-ink)]' : 'text-[var(--text-3)]'}`}>
                Commercial pipeline with savings
              </div>
            </div>
          </button>
          {supportProjectsEnabled ? (
            <button
              type="button"
              aria-pressed={projectType === 'Support'}
              onClick={() => handleProjectTypeChange('Support')}
              className={`flex flex-1 items-center justify-center gap-2 rounded-lg border-2 px-4 py-3 text-sm font-medium transition-colors ${
                projectType === 'Support'
                  ? 'border-[var(--brand)] bg-[var(--brand-soft)] text-[var(--brand-ink)]'
                  : 'border-[var(--border)] text-[var(--text-2)] hover:border-[var(--border-strong)]'
              }`}
            >
              <LifeBuoy className="h-5 w-5" />
              <div className="text-left">
                <div>Support / Non-Commercial</div>
                <div className={`text-xs font-normal ${projectType === 'Support' ? 'text-[var(--brand-ink)]' : 'text-[var(--text-3)]'}`}>
                  Vendor issues, tickets, $0 savings
                </div>
              </div>
            </button>
          ) : null}
        </div>
        {!supportProjectsEnabled ? (
          <p className="mt-3 text-xs text-[var(--text-3)]">Support / Non-Commercial project creation is turned off by a workspace administrator.</p>
        ) : null}
      </Card>

      {/* Basic Info */}
      <Card className="p-6">
        <h2 className="mb-4 text-lg font-semibold text-[var(--text)]">Basic Information</h2>
        <div className="grid grid-cols-1 gap-4 md:grid-cols-2">
          <div className="md:col-span-2">
            <label className={labelClass}>{projectType === 'Sourcing' ? 'Event' : 'Project'} Name *</label>
            <Input
              aria-label={`${projectType === 'Sourcing' ? 'Event' : 'Project'} Name`}
              type="text"
              required
              value={form.event_name}
              onChange={(e) => handleChange('event_name', e.target.value)}
              className="mt-1"
              placeholder={projectType === 'Sourcing' ? "e.g. CRM Software Renewal" : "e.g. Vendor billing dispute — Salesforce"}
            />
          </div>
          {projectDescriptionsEnabled ? (
            <div className="md:col-span-2">
              <label className={labelClass}>Description</label>
              <textarea
                aria-label="Description"
                value={form.event_description}
                onChange={(e) => handleChange('event_description', e.target.value)}
                className={textareaClass}
                rows={3}
                placeholder="Brief description"
              />
            </div>
          ) : null}
          <div>
            <label className={labelClass}>{projectType === 'Sourcing' ? 'Event Type' : 'Support Type'} *</label>
            <Select
              aria-label={projectType === 'Sourcing' ? 'Event Type' : 'Support Type'}
              required
              value={form.event_type}
              onChange={(e) => handleChange('event_type', e.target.value)}
              className="mt-1"
            >
              <option value="">Select type...</option>
              {currentTypes.map((type) => (
                <option key={type.id} value={type.label}>{type.label}</option>
              ))}
            </Select>
          </div>
          <div>
            <label className={labelClass}>Status</label>
            <Select
              aria-label="Status"
              value={form.event_status}
              onChange={(e) => handleChange('event_status', e.target.value)}
              className="mt-1"
            >
              {currentStatuses.map((status) => (
                <option key={status.id} value={status.label}>{status.label}</option>
              ))}
            </Select>
          </div>
          {projectOwnersEnabled ? (
            <div>
              <label className={labelClass}>Owner / Buyer</label>
              <Select
                aria-label="Owner or Buyer"
                value={form.buyer_name}
                onChange={(e) => handleChange('buyer_name', e.target.value)}
                className="mt-1"
              >
                <option value="">Unassigned</option>
                {owners.map(owner => <option key={owner.id} value={owner.label}>{owner.label}</option>)}
              </Select>
            </div>
          ) : null}
        </div>
      </Card>

      {/* Classification */}
      <Card className="p-6">
        <h2 className="mb-4 text-lg font-semibold text-[var(--text)]">Classification</h2>
        <div className="grid grid-cols-1 gap-4 md:grid-cols-2">
          {projectCategoriesEnabled ? (
            <div>
              <label className={labelClass}>Category</label>
              <Select
                aria-label="Category"
                value={form.category_id}
                onChange={(e) => handleChange('category_id', e.target.value)}
                className="mt-1"
              >
                <option value="">Select category...</option>
                {categories.map((c) => (
                  <option key={c.id} value={c.id}>{c.category_name}</option>
                ))}
              </Select>
            </div>
          ) : null}
          {projectBusinessUnitsEnabled ? (
            <div>
              <label className={labelClass}>Business Unit</label>
              <Select
                aria-label="Business Unit"
                value={form.business_unit_id}
                onChange={(e) => handleChange('business_unit_id', e.target.value)}
                className="mt-1"
              >
                <option value="">Select business unit...</option>
                {businessUnits.map((b) => (
                  <option key={b.id} value={b.id}>{b.business_unit_name}</option>
                ))}
              </Select>
            </div>
          ) : null}
          {projectCostCentersEnabled ? (
            <div>
              <label className={labelClass}>Cost Center</label>
              <Select
                aria-label="Cost Center"
                value={form.cost_center_id}
                onChange={(e) => handleChange('cost_center_id', e.target.value)}
                className="mt-1"
              >
                <option value="">Select cost center...</option>
                {costCenters.map((c) => (
                  <option key={c.id} value={c.id}>{c.cost_center_name}</option>
                ))}
              </Select>
            </div>
          ) : null}
          {projectIncumbentSuppliersEnabled ? <div>
            <label className={labelClass}>Incumbent Supplier</label>
            <div className="mt-1 flex gap-2">
              <Select
                aria-label="Incumbent Supplier"
                value={form.incumbent_supplier_id}
                onChange={(e) => handleChange('incumbent_supplier_id', e.target.value)}
                className="flex-1"
              >
                <option value="">Select supplier...</option>
                {suppliers.map((s) => (
                  <option key={s.id} value={s.id}>{s.supplier_name}</option>
                ))}
              </Select>
              <Button
                type="button"
                variant="secondary"
                size="sm"
                onClick={() => setShowAddSupplier(!showAddSupplier)}
                className="gap-1"
                title="Add new supplier"
              >
                {showAddSupplier ? <X className="h-4 w-4" /> : <Plus className="h-4 w-4" />}
                {showAddSupplier ? 'Cancel' : 'New'}
              </Button>
            </div>
            {showAddSupplier && (
              <div className="mt-2 flex gap-2">
                <Input
                  aria-label="New supplier name"
                  type="text"
                  value={newSupplierName}
                  onChange={(e) => setNewSupplierName(e.target.value)}
                  onKeyDown={(e) => { if (e.key === 'Enter') { e.preventDefault(); handleAddSupplier() } }}
                  className="flex-1"
                  placeholder="Enter supplier name..."
                  autoFocus
                />
                <Button
                  type="button"
                  onClick={handleAddSupplier}
                  disabled={addingSupplier || !newSupplierName.trim()}
                >
                  {addingSupplier ? 'Adding...' : 'Add'}
                </Button>
              </div>
            )}
          </div> : null}
        </div>
      </Card>

      {/* Dates — simplified: only project dates, no contract/recognition/reporting basis */}
      <Card className="p-6">
        <h2 className="mb-4 text-lg font-semibold text-[var(--text)]">Dates</h2>
        <div className="grid grid-cols-1 gap-4 md:grid-cols-2">
          <div>
            <label className={labelClass}>{projectType === 'Sourcing' ? 'Project Start Date' : 'Start Date'}</label>
            <Input
              aria-label={projectType === 'Sourcing' ? 'Project Start Date' : 'Start Date'}
              type="date"
              value={form.event_start_date}
              onChange={(e) => handleChange('event_start_date', e.target.value)}
              className="mt-1"
            />
            <p className="mt-1 text-xs text-[var(--text-3)]">
              {projectType === 'Sourcing' ? 'When the sourcing project kicked off' : 'When the support project started'}
            </p>
          </div>
          <div>
            <label className={labelClass}>Project Due Date</label>
            <Input
              aria-label="Project Due Date"
              type="date"
              value={form.project_due_date}
              onChange={(e) => handleChange('project_due_date', e.target.value)}
              className="mt-1"
            />
            <p className="mt-1 text-xs text-[var(--text-3)]">When the project is expected to be completed</p>
          </div>
        </div>
        {projectType === 'Sourcing' && (
          <p className="mt-3 rounded-lg bg-[var(--surface-2)] p-3 text-xs text-[var(--text-3)]">
            Savings period dates (start and end) are set on each savings calculation in the Calculations tab — those drive all financial reporting.
          </p>
        )}
      </Card>

      {/* Initial Project Update */}
      {projectUpdatesEnabled ? (
        <Card className="p-6">
          <h2 className="text-lg font-semibold text-[var(--text)]">Initial Project Update</h2>
          <p className="mt-1 text-xs text-[var(--text-3)]">
            Optional. This becomes the first dated entry in the project&apos;s update history.
          </p>
          <textarea
            aria-label="Initial Project Update"
            value={form.notes}
            onChange={(e) => handleChange('notes', e.target.value)}
            className={textareaClass}
            rows={4}
            maxLength={10000}
            placeholder="Add the starting context, latest decision, or next step..."
          />
        </Card>
      ) : null}

      {/* Submit */}
      <div className="flex justify-end gap-3">
        <Button
          type="button"
          variant="secondary"
          onClick={() => router.push('/events')}
        >
          Cancel
        </Button>
        <Button
          type="submit"
          disabled={loading}
        >
          {loading ? 'Creating...' : `Create ${projectType === 'Sourcing' ? 'Event' : 'Project'}`}
        </Button>
      </div>
    </form>
  )
}
