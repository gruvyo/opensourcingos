'use client'

import { useActionState } from 'react'
import { Save } from 'lucide-react'
import { createSupplier, type SupplierActionState, updateSupplier } from '@/app/suppliers/actions'
import { Button } from '@/components/ui/button'
import { Input, Select } from '@/components/ui/input'

export type SupplierFormValues = {
  supplierName: string
  supplierStatus: string
  riskRating: string
  website: string
  countryCode: string
  relationshipOwnerId: string
  nextReviewDate: string
  notes: string
  preferred: boolean
  diverse: boolean
}

type Owner = { id: string; label: string }
const initialState: SupplierActionState = { status: 'idle', message: '' }

function Field({ label, hint, children }: { label: string; hint?: string; children: React.ReactNode }) {
  return (
    <label className="block text-sm font-medium text-[var(--text)]">
      {label}
      <span className="mt-1.5 block">{children}</span>
      {hint ? <span className="mt-1 block text-xs font-normal text-[var(--text-3)]">{hint}</span> : null}
    </label>
  )
}

export function SupplierForm({ supplierId, values, owners }: { supplierId?: string; values: SupplierFormValues; owners: Owner[] }) {
  const action = supplierId ? updateSupplier.bind(null, supplierId) : createSupplier
  const [state, formAction, pending] = useActionState(action, initialState)

  return (
    <form action={formAction} className="space-y-6">
      <fieldset disabled={pending} className="space-y-6 disabled:opacity-70">
        <div className="grid gap-4 sm:grid-cols-2">
          <Field label="Supplier name"><Input name="supplierName" defaultValue={values.supplierName} required autoFocus={!supplierId} /></Field>
          <Field label="Relationship owner"><Select name="relationshipOwnerId" defaultValue={values.relationshipOwnerId}><option value="">Unassigned</option>{owners.map(owner => <option key={owner.id} value={owner.id}>{owner.label}</option>)}</Select></Field>
          <Field label="Status"><Select name="supplierStatus" defaultValue={values.supplierStatus}>{['Active', 'Inactive', 'Prospective', 'Blocked', 'Under Review'].map(value => <option key={value}>{value}</option>)}</Select></Field>
          <Field label="Risk rating"><Select name="riskRating" defaultValue={values.riskRating}><option value="">Unrated</option>{['Low', 'Medium', 'High'].map(value => <option key={value}>{value}</option>)}</Select></Field>
          <Field label="Website"><Input name="website" type="url" defaultValue={values.website} placeholder="https://supplier.com" /></Field>
          <Field label="Country" hint="Two-letter country code, such as US or CA."><Input name="countryCode" defaultValue={values.countryCode} maxLength={2} className="uppercase" /></Field>
          <Field label="Next relationship review"><Input name="nextReviewDate" type="date" defaultValue={values.nextReviewDate} /></Field>
        </div>

        <div className="grid gap-3 sm:grid-cols-2">
          <label className="flex items-center gap-3 rounded-lg border border-[var(--border)] p-4 text-sm font-medium text-[var(--text)]"><input name="preferred" type="checkbox" defaultChecked={values.preferred} className="h-4 w-4 accent-[var(--brand)]" />Preferred supplier</label>
          <label className="flex items-center gap-3 rounded-lg border border-[var(--border)] p-4 text-sm font-medium text-[var(--text)]"><input name="diverse" type="checkbox" defaultChecked={values.diverse} className="h-4 w-4 accent-[var(--brand)]" />Diverse supplier</label>
        </div>

        <Field label="Relationship notes" hint="Keep this concise and suitable for colleagues in your workspace.">
          <textarea name="notes" defaultValue={values.notes} rows={5} className="w-full resize-y rounded-md border border-[var(--border-strong)] bg-[var(--surface)] px-3 py-2 text-sm text-[var(--text)] focus:border-[var(--brand)] focus:outline-none focus:ring-2 focus:ring-[var(--brand)]/30" />
        </Field>
      </fieldset>

      {state.message ? <p aria-live="polite" className={state.status === 'error' ? 'text-sm text-[var(--danger)]' : 'text-sm text-[var(--success)]'}>{state.message}</p> : null}
      <Button type="submit" disabled={pending}><Save className="h-4 w-4" aria-hidden="true" />{pending ? 'Saving…' : supplierId ? 'Save supplier' : 'Create supplier'}</Button>
    </form>
  )
}
