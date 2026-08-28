'use client'

import { useActionState, useRef, useState } from 'react'
import { Archive, Plus, RotateCcw, Save } from 'lucide-react'
import {
  saveClassificationOption,
  toggleClassificationOption,
  type ClassificationActionState,
  type ClassificationKind,
} from '@/app/settings/classification-actions'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'

export type ManagedClassificationOption = {
  id: string
  kind: ClassificationKind
  label: string
  active: boolean
  isTerminal?: boolean
  requiresSavingsDisposition?: boolean
  projectType?: 'Sourcing' | 'Support' | null
  sortOrder?: number
}

type Section = {
  title: string
  description: string
  kind: ClassificationKind
  projectType?: 'Sourcing' | 'Support'
}

const sections: Section[] = [
  { title: 'Sourcing event types', description: 'Why the sourcing project exists. Savings strategies and value levers are tracked separately.', kind: 'event_type', projectType: 'Sourcing' },
  { title: 'Support project types', description: 'Why the non-commercial support request exists.', kind: 'event_type', projectType: 'Support' },
  { title: 'Sourcing statuses', description: 'Workflow stages available to sourcing projects.', kind: 'event_status', projectType: 'Sourcing' },
  { title: 'Support statuses', description: 'Workflow stages available to support projects.', kind: 'event_status', projectType: 'Support' },
  { title: 'Owners / Buyers', description: 'Workspace-managed names available on projects.', kind: 'owner' },
  { title: 'Categories', description: 'What is being bought, grouped for portfolio and spend reporting.', kind: 'category' },
  { title: 'Business Units', description: 'Internal organizations that own demand for a project.', kind: 'business_unit' },
  { title: 'Cost Centers', description: 'Your organization\'s accounting values. No generic defaults are created.', kind: 'cost_center' },
]

const initialState: ClassificationActionState = { status: 'idle', message: '' }

function StateMessage({ state }: { state: ClassificationActionState }) {
  if (!state.message) return null
  return (
    <p aria-live="polite" className={state.status === 'error' ? 'mt-2 text-xs text-[var(--danger)]' : 'mt-2 text-xs text-[var(--success)]'}>
      {state.message}
    </p>
  )
}

function ChoiceRow({ option, canEdit }: { option: ManagedClassificationOption; canEdit: boolean }) {
  const [saveState, saveAction, saving] = useActionState(saveClassificationOption, initialState)
  const [toggleState, toggleAction, toggling] = useActionState(toggleClassificationOption, initialState)
  const [finished, setFinished] = useState(Boolean(option.isTerminal))

  return (
    <div className="border-t border-[var(--border)] py-3 first:border-t-0">
      <div className="flex flex-col gap-2 sm:flex-row sm:items-center">
        <form action={saveAction} className="flex min-w-0 flex-1 flex-wrap gap-2">
          <input type="hidden" name="id" value={option.id} />
          <input type="hidden" name="kind" value={option.kind} />
          <input type="hidden" name="projectType" value={option.projectType || ''} />
          <Input
            name="label"
            aria-label={`Rename ${option.label}`}
            defaultValue={option.label}
            disabled={!canEdit || !option.active || saving || toggling}
            className={`min-w-0 flex-1 ${!option.active ? 'text-[var(--text-3)] line-through' : ''}`}
            required
          />
          {option.kind === 'event_status' ? (
            <label className="flex items-center gap-2 rounded-md border border-[var(--border)] px-3 py-2 text-xs font-medium text-[var(--text-2)]">
              {option.requiresSavingsDisposition ? <input type="hidden" name="isTerminal" value="true" /> : null}
              <input
                type="checkbox"
                name="isTerminal"
                value="true"
                checked={finished}
                onChange={event => setFinished(event.target.checked)}
                disabled={!canEdit || !option.active || saving || toggling || option.requiresSavingsDisposition}
              />
              {option.requiresSavingsDisposition ? 'Finished status (required)' : 'Finished status'}
            </label>
          ) : null}
          {canEdit && option.active ? (
            <Button type="submit" variant="secondary" size="sm" disabled={saving || toggling} title="Save name">
              <Save className="h-4 w-4" aria-hidden="true" />
              <span className="sr-only">Save {option.label}</span>
            </Button>
          ) : null}
        </form>
        {canEdit && option.requiresSavingsDisposition ? (
          <span className="rounded-md border border-[var(--border)] px-3 py-2 text-xs font-medium text-[var(--text-3)]">
            Required workflow status
          </span>
        ) : canEdit ? (
          <form action={toggleAction}>
            <input type="hidden" name="id" value={option.id} />
            <input type="hidden" name="kind" value={option.kind} />
            <input type="hidden" name="active" value={String(!option.active)} />
            <Button type="submit" variant="secondary" size="sm" disabled={saving || toggling} className="w-full sm:w-auto">
              {option.active ? <Archive className="h-4 w-4" aria-hidden="true" /> : <RotateCcw className="h-4 w-4" aria-hidden="true" />}
              {option.active ? 'Archive' : 'Restore'}
            </Button>
          </form>
        ) : null}
      </div>
      <StateMessage state={saveState} />
      <StateMessage state={toggleState} />
    </div>
  )
}

function AddChoiceForm({ section }: { section: Section }) {
  const formRef = useRef<HTMLFormElement>(null)
  const [finished, setFinished] = useState(false)
  const [state, action, pending] = useActionState(async (
    previous: ClassificationActionState,
    formData: FormData,
  ) => {
    const next = await saveClassificationOption(previous, formData)
    if (next.status === 'success') {
      formRef.current?.reset()
      setFinished(false)
    }
    return next
  }, initialState)

  return (
    <div className="mt-3 border-t border-[var(--border)] pt-3">
      <form ref={formRef} action={action} className="flex gap-2">
        <input type="hidden" name="id" value="" />
        <input type="hidden" name="kind" value={section.kind} />
        <input type="hidden" name="projectType" value={section.projectType || ''} />
        <Input name="label" aria-label={`Add ${section.title} choice`} placeholder="Add a choice" disabled={pending} className="min-w-0 flex-1" required />
        {section.kind === 'event_status' ? (
          <label className="flex items-center gap-2 rounded-md border border-[var(--border)] px-3 py-2 text-xs font-medium text-[var(--text-2)]">
            <input
              type="checkbox"
              name="isTerminal"
              value="true"
              checked={finished}
              onChange={event => setFinished(event.target.checked)}
              disabled={pending}
            />
            Finished
          </label>
        ) : null}
        <Button type="submit" size="sm" disabled={pending}>
          <Plus className="h-4 w-4" aria-hidden="true" />
          Add
        </Button>
      </form>
      <StateMessage state={state} />
    </div>
  )
}

export function ClassificationManager({
  options,
  canEdit,
}: {
  options: ManagedClassificationOption[]
  canEdit: boolean
}) {
  return (
    <section>
      <div>
        <h2 className="text-sm font-semibold text-[var(--text)]">Workspace choices</h2>
        <p className="mt-1 text-xs leading-5 text-[var(--text-3)]">
          Rename, add, or archive the choices used by project forms. Mark a status as Finished to remove projects in that status from active pipeline and deadline views. The required Sourcing completion status may be renamed, but it always keeps its executed/no-savings decision guard. New custom statuses are not Finished by default.
        </p>
      </div>

      <div className="mt-5 grid gap-4 lg:grid-cols-2">
        {sections.map(section => {
          const matching = options
            .filter(option => option.kind === section.kind && (option.projectType || undefined) === section.projectType)
            .sort((a, b) => Number(b.active) - Number(a.active) || (a.sortOrder ?? 1000) - (b.sortOrder ?? 1000) || a.label.localeCompare(b.label))
          return (
            <div key={`${section.kind}-${section.projectType || 'all'}`} className="rounded-xl border border-[var(--border)] p-4">
              <h3 className="text-sm font-semibold text-[var(--text)]">{section.title}</h3>
              <p className="mt-1 text-xs text-[var(--text-3)]">{section.description}</p>
              <div className="mt-3">
                {matching.length ? matching.map(option => <ChoiceRow key={option.id} option={option} canEdit={canEdit} />) : (
                  <p className="py-3 text-xs text-[var(--text-3)]">
                    {section.kind === 'cost_center' ? 'No Cost Centers yet. Add the accounting values used by your organization.' : 'No choices yet.'}
                  </p>
                )}
              </div>
              {canEdit ? <AddChoiceForm section={section} /> : null}
            </div>
          )
        })}
      </div>
    </section>
  )
}
