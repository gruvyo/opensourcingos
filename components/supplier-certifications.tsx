'use client'

import { useActionState, useEffect, useState } from 'react'
import { Award, ExternalLink, Pencil, Plus, Trash2 } from 'lucide-react'
import { deleteSupplierCertification, saveSupplierCertification, type CertificationActionState } from '@/app/suppliers/certification-actions'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { ConfirmDialog } from '@/components/ui/confirm-dialog'
import { Input } from '@/components/ui/input'
import { SafeExternalLink } from '@/components/safe-external-link'
import { useWorkspaceFormat } from '@/components/workspace-format-provider'

export type SupplierCertification = {
  id: string
  certification_name: string
  issuer: string | null
  certificate_number: string | null
  issued_on: string | null
  expires_on: string | null
  evidence_url: string | null
}

const initialState: CertificationActionState = { status: 'idle', message: '' }

export function SupplierCertifications({ supplierId, certifications, canEdit, today }: { supplierId: string; certifications: SupplierCertification[]; canEdit: boolean; today: string }) {
  const { formatDate } = useWorkspaceFormat()
  const [editor, setEditor] = useState<'new' | string | null>(null)
  const [deleteTarget, setDeleteTarget] = useState<SupplierCertification | null>(null)
  const [deleteError, setDeleteError] = useState('')
  const handleDelete = async () => {
    if (!deleteTarget) return
    const result = await deleteSupplierCertification(supplierId, deleteTarget.id)
    if (result.status === 'error') setDeleteError(result.message)
    else setDeleteError('')
  }

  return <div>
    <div className="flex flex-wrap items-center justify-between gap-3 border-b border-[var(--border)] px-5 py-4">
      <div><h2 className="text-sm font-semibold text-[var(--text)]">Certifications</h2><p className="mt-1 text-xs text-[var(--text-3)]">Issuer, validity dates, and supporting evidence</p></div>
      {canEdit && editor !== 'new' ? <Button type="button" variant="secondary" size="sm" onClick={() => setEditor('new')}><Plus className="h-3.5 w-3.5" aria-hidden="true" />Add certification</Button> : null}
    </div>
    {editor === 'new' ? <CertificationEditor supplierId={supplierId} certification={null} onClose={() => setEditor(null)} /> : null}
    {certifications.length ? <div className="divide-y divide-[var(--border)]">{certifications.map(certification => editor === certification.id
      ? <CertificationEditor key={certification.id} supplierId={supplierId} certification={certification} onClose={() => setEditor(null)} />
      : <div key={certification.id} className="px-5 py-4"><div className="flex flex-wrap items-start justify-between gap-3"><div className="min-w-0"><div className="flex flex-wrap items-center gap-2"><p className="font-medium text-[var(--text)]">{certification.certification_name}</p>{certification.expires_on && certification.expires_on < today ? <Badge tone="danger">Expired</Badge> : null}</div><p className="mt-1 text-xs text-[var(--text-3)]">{certification.issuer || 'Issuer not specified'}{certification.certificate_number ? ` · ${certification.certificate_number}` : ''}</p></div>{canEdit ? <div className="flex gap-1"><Button type="button" variant="ghost" size="sm" onClick={() => setEditor(certification.id)} aria-label={`Edit ${certification.certification_name}`}><Pencil className="h-3.5 w-3.5" aria-hidden="true" /></Button><Button type="button" variant="ghost" size="sm" onClick={() => setDeleteTarget(certification)} aria-label={`Delete ${certification.certification_name}`}><Trash2 className="h-3.5 w-3.5" aria-hidden="true" /></Button></div> : null}</div><div className="mt-3 flex flex-wrap gap-x-5 gap-y-2 text-xs text-[var(--text-2)]"><span>Issued {formatDate(certification.issued_on)}</span><span>Expires {certification.expires_on ? formatDate(certification.expires_on) : 'No expiry recorded'}</span><SafeExternalLink href={certification.evidence_url} className="inline-flex items-center gap-1 text-[var(--brand-ink)] hover:underline">Evidence<ExternalLink className="h-3 w-3" aria-hidden="true" /></SafeExternalLink></div></div>)}</div>
      : editor !== 'new' ? <div className="p-6 text-center"><Award className="mx-auto h-5 w-5 text-[var(--text-3)]" aria-hidden="true" /><p className="mt-2 text-sm text-[var(--text-2)]">No certifications have been added yet.</p></div> : null}
    {deleteError ? <p className="border-t border-[var(--border)] px-5 py-3 text-sm text-[var(--danger)]" aria-live="polite">{deleteError}</p> : null}
    {deleteTarget ? <ConfirmDialog title="Delete this certification?" description={`${deleteTarget.certification_name} will be removed. The change will remain in workspace audit history.`} onConfirm={handleDelete} onCancel={() => setDeleteTarget(null)} /> : null}
  </div>
}

function CertificationEditor({ supplierId, certification, onClose }: { supplierId: string; certification: SupplierCertification | null; onClose: () => void }) {
  const action = saveSupplierCertification.bind(null, supplierId, certification?.id || null)
  const [state, formAction, pending] = useActionState(action, initialState)
  useEffect(() => { if (state.status === 'success') onClose() }, [onClose, state.status])
  return <form action={formAction} className="border-b border-[var(--border)] bg-[var(--surface-2)] px-5 py-4"><fieldset disabled={pending} className="grid gap-4 disabled:opacity-70 sm:grid-cols-2">
    <label className="text-xs font-medium text-[var(--text-2)]">Certification name *<Input name="certificationName" defaultValue={certification?.certification_name || ''} className="mt-1.5" required autoFocus /></label>
    <label className="text-xs font-medium text-[var(--text-2)]">Issuer<Input name="issuer" defaultValue={certification?.issuer || ''} className="mt-1.5" /></label>
    <label className="text-xs font-medium text-[var(--text-2)]">Certificate number<Input name="certificateNumber" defaultValue={certification?.certificate_number || ''} className="mt-1.5" /></label>
    <label className="text-xs font-medium text-[var(--text-2)]">Evidence link<Input name="evidenceUrl" type="url" defaultValue={certification?.evidence_url || ''} className="mt-1.5" placeholder="https://" /></label>
    <label className="text-xs font-medium text-[var(--text-2)]">Issue date<Input name="issuedOn" type="date" defaultValue={certification?.issued_on || ''} className="mt-1.5" /></label>
    <label className="text-xs font-medium text-[var(--text-2)]">Expiration date<Input name="expiresOn" type="date" defaultValue={certification?.expires_on || ''} className="mt-1.5" /></label>
  </fieldset>{state.status === 'error' ? <p className="mt-3 text-sm text-[var(--danger)]" aria-live="polite">{state.message}</p> : null}<div className="mt-4 flex flex-wrap justify-end gap-2"><Button type="button" variant="secondary" size="sm" onClick={onClose} disabled={pending}>Cancel</Button><Button type="submit" size="sm" disabled={pending}>{pending ? 'Saving…' : certification ? 'Save certification' : 'Add certification'}</Button></div></form>
}
