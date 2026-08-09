'use client'

import { useActionState, useEffect, useState } from 'react'
import { Mail, Pencil, Phone, Plus, Star, Trash2 } from 'lucide-react'
import {
  deleteSupplierContact,
  saveSupplierContact,
  type ContactActionState,
} from '@/app/suppliers/contact-actions'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { ConfirmDialog } from '@/components/ui/confirm-dialog'
import { Input } from '@/components/ui/input'

export type SupplierContact = {
  id: string
  contact_name: string
  job_title: string | null
  email: string | null
  phone: string | null
  is_primary: boolean
}

const initialState: ContactActionState = { status: 'idle', message: '' }

export function SupplierContacts({
  supplierId,
  contacts,
  canEdit,
}: {
  supplierId: string
  contacts: SupplierContact[]
  canEdit: boolean
}) {
  const [editor, setEditor] = useState<'new' | string | null>(null)
  const [deleteTarget, setDeleteTarget] = useState<SupplierContact | null>(null)
  const [deleteError, setDeleteError] = useState('')

  const handleDelete = async () => {
    if (!deleteTarget) return
    const result = await deleteSupplierContact(supplierId, deleteTarget.id)
    if (result.status === 'error') setDeleteError(result.message)
    else setDeleteError('')
  }

  return (
    <div>
      <div className="flex flex-wrap items-center justify-between gap-3 border-b border-[var(--border)] px-5 py-4">
        <div>
          <h2 className="text-sm font-semibold text-[var(--text)]">Supplier contacts</h2>
          <p className="mt-1 text-xs text-[var(--text-3)]">Commercial and operational people for this relationship</p>
        </div>
        {canEdit && editor !== 'new' ? (
          <Button type="button" variant="secondary" size="sm" onClick={() => setEditor('new')}>
            <Plus className="h-3.5 w-3.5" aria-hidden="true" />
            Add contact
          </Button>
        ) : null}
      </div>

      {editor === 'new' ? (
        <ContactEditor supplierId={supplierId} contact={null} onClose={() => setEditor(null)} />
      ) : null}

      {contacts.length ? (
        <div className="divide-y divide-[var(--border)]">
          {contacts.map(contact => editor === contact.id ? (
            <ContactEditor key={contact.id} supplierId={supplierId} contact={contact} onClose={() => setEditor(null)} />
          ) : (
            <div key={contact.id} className="px-5 py-4">
              <div className="flex flex-wrap items-start justify-between gap-3">
                <div className="min-w-0">
                  <div className="flex flex-wrap items-center gap-2">
                    <p className="font-medium text-[var(--text)]">{contact.contact_name}</p>
                    {contact.is_primary ? <Badge tone="brand"><Star className="h-3 w-3" aria-hidden="true" />Primary</Badge> : null}
                  </div>
                  <p className="mt-1 text-xs text-[var(--text-3)]">{contact.job_title || 'Role not specified'}</p>
                </div>
                {canEdit ? (
                  <div className="flex gap-1">
                    <Button type="button" variant="ghost" size="sm" onClick={() => setEditor(contact.id)} aria-label={`Edit ${contact.contact_name}`}>
                      <Pencil className="h-3.5 w-3.5" aria-hidden="true" />
                    </Button>
                    <Button type="button" variant="ghost" size="sm" onClick={() => setDeleteTarget(contact)} aria-label={`Delete ${contact.contact_name}`}>
                      <Trash2 className="h-3.5 w-3.5" aria-hidden="true" />
                    </Button>
                  </div>
                ) : null}
              </div>
              <div className="mt-3 flex flex-wrap gap-x-5 gap-y-2 text-xs">
                {contact.email ? <a href={`mailto:${contact.email}`} className="inline-flex items-center gap-1.5 text-[var(--brand-ink)] hover:underline"><Mail className="h-3.5 w-3.5" aria-hidden="true" />{contact.email}</a> : null}
                {contact.phone ? <a href={`tel:${contact.phone}`} className="inline-flex items-center gap-1.5 text-[var(--brand-ink)] hover:underline"><Phone className="h-3.5 w-3.5" aria-hidden="true" />{contact.phone}</a> : null}
                {!contact.email && !contact.phone ? <span className="text-[var(--text-3)]">No contact details recorded</span> : null}
              </div>
            </div>
          ))}
        </div>
      ) : editor !== 'new' ? (
        <p className="p-5 text-sm text-[var(--text-2)]">No supplier contacts have been added yet.</p>
      ) : null}

      {deleteError ? <p className="border-t border-[var(--border)] px-5 py-3 text-sm text-[var(--danger)]" aria-live="polite">{deleteError}</p> : null}

      {deleteTarget ? (
        <ConfirmDialog
          title="Delete this supplier contact?"
          description={`${deleteTarget.contact_name} will be removed from this supplier relationship. The change will remain in the workspace audit history.`}
          onConfirm={handleDelete}
          onCancel={() => setDeleteTarget(null)}
        />
      ) : null}
    </div>
  )
}

function ContactEditor({
  supplierId,
  contact,
  onClose,
}: {
  supplierId: string
  contact: SupplierContact | null
  onClose: () => void
}) {
  const action = saveSupplierContact.bind(null, supplierId, contact?.id || null)
  const [state, formAction, pending] = useActionState(action, initialState)

  useEffect(() => {
    if (state.status === 'success') onClose()
  }, [onClose, state.status])

  return (
    <form action={formAction} className="border-b border-[var(--border)] bg-[var(--surface-2)] px-5 py-4">
      <fieldset disabled={pending} className="grid gap-4 disabled:opacity-70 sm:grid-cols-2">
        <label className="text-xs font-medium text-[var(--text-2)]">Name *<Input name="contactName" defaultValue={contact?.contact_name || ''} className="mt-1.5" required autoFocus /></label>
        <label className="text-xs font-medium text-[var(--text-2)]">Role or title<Input name="jobTitle" defaultValue={contact?.job_title || ''} className="mt-1.5" /></label>
        <label className="text-xs font-medium text-[var(--text-2)]">Email<Input name="email" type="email" defaultValue={contact?.email || ''} className="mt-1.5" /></label>
        <label className="text-xs font-medium text-[var(--text-2)]">Phone<Input name="phone" type="tel" defaultValue={contact?.phone || ''} className="mt-1.5" /></label>
        <label className="flex items-center gap-2 text-sm font-medium text-[var(--text)] sm:col-span-2"><input name="isPrimary" type="checkbox" defaultChecked={contact?.is_primary || false} className="h-4 w-4 accent-[var(--brand)]" />Primary contact for this supplier</label>
      </fieldset>
      {state.status === 'error' ? <p className="mt-3 text-sm text-[var(--danger)]" aria-live="polite">{state.message}</p> : null}
      <div className="mt-4 flex flex-wrap justify-end gap-2">
        <Button type="button" variant="secondary" size="sm" onClick={onClose} disabled={pending}>Cancel</Button>
        <Button type="submit" size="sm" disabled={pending}>{pending ? 'Saving…' : contact ? 'Save contact' : 'Add contact'}</Button>
      </div>
    </form>
  )
}
