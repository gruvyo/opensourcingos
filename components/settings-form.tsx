'use client'

import { useActionState } from 'react'
import { Save } from 'lucide-react'
import { updateSettings, type SettingsActionState } from '@/app/settings/actions'
import { Button } from '@/components/ui/button'
import { Input, Select } from '@/components/ui/input'

type SettingsValues = {
  organizationName: string
  fullName: string
  currencyCode: string
  locale: string
  timezone: string
  fiscalYearStartMonth: number
  dateFormat: string
  defaultRecognitionMethod: string
  supportProjectsEnabled: boolean
  projectDescriptionsEnabled: boolean
  projectOwnersEnabled: boolean
  projectCostCentersEnabled: boolean
  projectCategoriesEnabled: boolean
  projectBusinessUnitsEnabled: boolean
  requireBaseline: boolean
  hardReductionApprovalThreshold: number | null
}

const initialState: SettingsActionState = { status: 'idle', message: '' }
const months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December']

function Field({ label, hint, children }: { label: string; hint?: string; children: React.ReactNode }) {
  return (
    <label className="block text-sm font-medium text-[var(--text)]">
      {label}
      <span className="mt-1.5 block">{children}</span>
      {hint ? <span className="mt-1 block text-xs font-normal text-[var(--text-3)]">{hint}</span> : null}
    </label>
  )
}

export function SettingsForm({ values, canEdit }: { values: SettingsValues; canEdit: boolean }) {
  const [state, action, pending] = useActionState(updateSettings, initialState)

  return (
    <form action={action} className="space-y-8">
      <fieldset disabled={!canEdit || pending} className="space-y-8 disabled:opacity-70">
        <section>
          <h2 className="text-sm font-semibold text-[var(--text)]">Workspace identity</h2>
          <p className="mt-1 text-xs text-[var(--text-3)]">Names shown in navigation, reporting, and activity history.</p>
          <div className="mt-4 grid gap-4 sm:grid-cols-2">
            <Field label="Organization name *"><Input name="organizationName" defaultValue={values.organizationName} required /></Field>
            <Field label="Your display name *"><Input name="fullName" defaultValue={values.fullName} required /></Field>
          </div>
        </section>

        <section className="border-t border-[var(--border)] pt-6">
          <h2 className="text-sm font-semibold text-[var(--text)]">System setup</h2>
          <p className="mt-1 text-xs text-[var(--text-3)]">Choose which project types and optional fields workspace members can use.</p>
          <div className="mt-4 grid gap-4 sm:grid-cols-2">
            <label className="flex items-start gap-3 rounded-lg border border-[var(--border)] p-4">
              <input name="supportProjectsEnabled" type="checkbox" defaultChecked={values.supportProjectsEnabled} className="mt-1 h-4 w-4 accent-[var(--brand)]" />
              <span>
                <span className="block text-sm font-medium text-[var(--text)]">Allow Support / Non-Commercial projects</span>
                <span className="mt-1 block text-xs text-[var(--text-3)]">When off, members cannot create or convert projects to Support. Existing Support projects remain available.</span>
              </span>
            </label>
            <label className="flex items-start gap-3 rounded-lg border border-[var(--border)] p-4">
              <input name="projectDescriptionsEnabled" type="checkbox" defaultChecked={values.projectDescriptionsEnabled} className="mt-1 h-4 w-4 accent-[var(--brand)]" />
              <span>
                <span className="block text-sm font-medium text-[var(--text)]">Allow Project Descriptions</span>
                <span className="mt-1 block text-xs text-[var(--text-3)]">When off, members cannot add or change descriptions. Existing descriptions remain visible.</span>
              </span>
            </label>
            <label className="flex items-start gap-3 rounded-lg border border-[var(--border)] p-4">
              <input name="projectOwnersEnabled" type="checkbox" defaultChecked={values.projectOwnersEnabled} className="mt-1 h-4 w-4 accent-[var(--brand)]" />
              <span>
                <span className="block text-sm font-medium text-[var(--text)]">Allow Project Owner / Buyer</span>
                <span className="mt-1 block text-xs text-[var(--text-3)]">When off, members cannot add or change owners. Existing owner values remain visible in projects and reports.</span>
              </span>
            </label>
            <label className="flex items-start gap-3 rounded-lg border border-[var(--border)] p-4">
              <input name="projectCostCentersEnabled" type="checkbox" defaultChecked={values.projectCostCentersEnabled} className="mt-1 h-4 w-4 accent-[var(--brand)]" />
              <span>
                <span className="block text-sm font-medium text-[var(--text)]">Allow Project Cost Center</span>
                <span className="mt-1 block text-xs text-[var(--text-3)]">When off, members cannot add or change Cost Centers. Existing values remain visible in project details.</span>
              </span>
            </label>
            <label className="flex items-start gap-3 rounded-lg border border-[var(--border)] p-4">
              <input name="projectCategoriesEnabled" type="checkbox" defaultChecked={values.projectCategoriesEnabled} className="mt-1 h-4 w-4 accent-[var(--brand)]" />
              <span>
                <span className="block text-sm font-medium text-[var(--text)]">Allow Project Category</span>
                <span className="mt-1 block text-xs text-[var(--text-3)]">When off, members cannot add or change project Categories. Existing values remain visible in project details, lists, and dashboards.</span>
              </span>
            </label>
            <label className="flex items-start gap-3 rounded-lg border border-[var(--border)] p-4">
              <input name="projectBusinessUnitsEnabled" type="checkbox" defaultChecked={values.projectBusinessUnitsEnabled} className="mt-1 h-4 w-4 accent-[var(--brand)]" />
              <span>
                <span className="block text-sm font-medium text-[var(--text)]">Allow Project Business Unit</span>
                <span className="mt-1 block text-xs text-[var(--text-3)]">When off, members cannot add or change project Business Units. Existing values remain visible in project details, lists, dashboards, and reports.</span>
              </span>
            </label>
          </div>
        </section>

        <section className="border-t border-[var(--border)] pt-6">
          <h2 className="text-sm font-semibold text-[var(--text)]">Reporting defaults</h2>
          <p className="mt-1 text-xs text-[var(--text-3)]">Defaults for new records and portfolio presentation.</p>
          <div className="mt-4 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
            <Field label="Currency"><Select name="currencyCode" defaultValue={values.currencyCode}>{['USD', 'CAD', 'EUR', 'GBP', 'AUD'].map(value => <option key={value}>{value}</option>)}</Select></Field>
            <Field label="Locale"><Select name="locale" defaultValue={values.locale}>{['en-US', 'en-CA', 'en-GB'].map(value => <option key={value}>{value}</option>)}</Select></Field>
            <Field label="Timezone"><Select name="timezone" defaultValue={values.timezone}>{['America/Chicago', 'America/New_York', 'America/Denver', 'America/Los_Angeles', 'UTC'].map(value => <option key={value}>{value}</option>)}</Select></Field>
            <Field label="Fiscal year starts"><Select name="fiscalYearStartMonth" defaultValue={String(values.fiscalYearStartMonth)}>{months.map((month, index) => <option key={month} value={index + 1}>{month}</option>)}</Select></Field>
            <Field label="Date format"><Select name="dateFormat" defaultValue={values.dateFormat}>{['MMM D, YYYY', 'MM/DD/YYYY', 'DD/MM/YYYY', 'YYYY-MM-DD'].map(value => <option key={value}>{value}</option>)}</Select></Field>
            <Field label="Savings recognition"><Select name="defaultRecognitionMethod" defaultValue={values.defaultRecognitionMethod}><option value="monthly">Monthly</option><option value="annual">Annual</option><option value="one_time">One-time</option></Select></Field>
          </div>
        </section>

        <section className="border-t border-[var(--border)] pt-6">
          <h2 className="text-sm font-semibold text-[var(--text)]">Methodology controls</h2>
          <div className="mt-4 grid gap-4 sm:grid-cols-2">
            <label className="flex items-start gap-3 rounded-lg border border-[var(--border)] p-4">
              <input name="requireBaseline" type="checkbox" defaultChecked={values.requireBaseline} className="mt-1 h-4 w-4 accent-[var(--brand)]" />
              <span><span className="block text-sm font-medium text-[var(--text)]">Require a baseline for hard reduction</span><span className="mt-1 block text-xs text-[var(--text-3)]">Keeps Cost Reduction tied to a defensible reference point.</span></span>
            </label>
            <Field label="Approval threshold" hint="Leave blank when every hard reduction follows the same approval path."><Input name="hardReductionApprovalThreshold" type="number" min="0" step="1000" defaultValue={values.hardReductionApprovalThreshold ?? ''} placeholder="No amount threshold" /></Field>
          </div>
        </section>
      </fieldset>

      {!canEdit ? <p className="rounded-lg bg-[var(--surface-2)] p-3 text-sm text-[var(--text-2)]">Only workspace administrators can change these settings.</p> : null}
      {state.message ? <p aria-live="polite" className={state.status === 'error' ? 'text-sm text-[var(--danger)]' : 'text-sm text-[var(--success)]'}>{state.message}</p> : null}
      {canEdit ? <Button type="submit" disabled={pending}><Save className="h-4 w-4" aria-hidden="true" />{pending ? 'Saving…' : 'Save settings'}</Button> : null}
    </form>
  )
}
