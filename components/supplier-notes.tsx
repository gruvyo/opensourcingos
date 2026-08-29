'use client'

import { useActionState, useEffect, useRef } from 'react'
import { CalendarDays, MessageSquareText } from 'lucide-react'
import { addSupplierNote, type SupplierNoteActionState } from '@/app/suppliers/note-actions'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { useWorkspaceFormat } from '@/components/workspace-format-provider'

export type SupplierNote = {
  id: string
  occurred_on: string
  body: string
  created_at: string
  author: { full_name: string | null; email: string } | { full_name: string | null; email: string }[] | null
}

const initialState: SupplierNoteActionState = { status: 'idle', message: '' }

function authorName(author: SupplierNote['author']) {
  const person = Array.isArray(author) ? author[0] : author
  return person?.full_name || person?.email || 'Former workspace member'
}

export function SupplierNotes({
  supplierId,
  notes,
  canEdit,
  today,
}: {
  supplierId: string
  notes: SupplierNote[]
  canEdit: boolean
  today: string
}) {
  const { formatDate } = useWorkspaceFormat()
  const formRef = useRef<HTMLFormElement>(null)
  const action = addSupplierNote.bind(null, supplierId)
  const [state, formAction, pending] = useActionState(action, initialState)

  useEffect(() => {
    if (state.status === 'success') formRef.current?.reset()
  }, [state.status])

  return (
    <div>
      <div className="border-b border-[var(--border)] px-5 py-4">
        <h2 className="text-sm font-semibold text-[var(--text)]">Relationship notes</h2>
        <p className="mt-1 text-xs text-[var(--text-3)]">Dated, append-only context for reviews, risks, and follow-up</p>
      </div>

      {canEdit ? (
        <form ref={formRef} action={formAction} className="border-b border-[var(--border)] bg-[var(--surface-2)] px-5 py-4">
          <fieldset disabled={pending} className="grid gap-3 disabled:opacity-70">
            <label className="max-w-56 text-xs font-medium text-[var(--text-2)]">Activity date<Input name="occurredOn" type="date" defaultValue={today} className="mt-1.5" required /></label>
            <label className="text-xs font-medium text-[var(--text-2)]">Note<textarea name="body" rows={3} maxLength={10000} required className="mt-1.5 w-full resize-y rounded-md border border-[var(--border-strong)] bg-[var(--surface)] px-3 py-2 text-sm text-[var(--text)] transition-colors focus:border-[var(--brand)] focus:outline-none focus:ring-2 focus:ring-[var(--brand)]/30" placeholder="Record relationship context, evidence, or the next follow-up." /></label>
          </fieldset>
          <div className="mt-3 flex flex-wrap items-center justify-between gap-3">
            <p className={state.status === 'error' ? 'text-sm text-[var(--danger)]' : 'text-sm text-[var(--text-3)]'} aria-live="polite">{state.message}</p>
            <Button type="submit" size="sm" disabled={pending}>{pending ? 'Adding…' : 'Add note'}</Button>
          </div>
        </form>
      ) : null}

      {notes.length ? (
        <ol className="divide-y divide-[var(--border)]">
          {notes.map(note => (
            <li key={note.id} className="px-5 py-4">
              <div className="flex flex-wrap items-center gap-x-3 gap-y-1 text-xs text-[var(--text-3)]">
                <span className="inline-flex items-center gap-1.5 font-medium text-[var(--text-2)]"><CalendarDays className="h-3.5 w-3.5" aria-hidden="true" />{formatDate(note.occurred_on)}</span>
                <span>{authorName(note.author)} · added {formatDate(note.created_at)}</span>
              </div>
              <p className="mt-2 whitespace-pre-wrap text-sm leading-6 text-[var(--text-2)]">{note.body}</p>
            </li>
          ))}
        </ol>
      ) : (
        <div className="p-6 text-center">
          <MessageSquareText className="mx-auto h-5 w-5 text-[var(--text-3)]" aria-hidden="true" />
          <p className="mt-2 text-sm text-[var(--text-2)]">No relationship notes have been added yet.</p>
        </div>
      )}
    </div>
  )
}
