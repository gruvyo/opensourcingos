'use client'

import { useActionState, useEffect, useState } from 'react'
import { ExternalLink, Pencil, Plus, ShieldAlert, Trash2 } from 'lucide-react'
import { deleteSupplierRisk, saveSupplierRisk, type RiskActionState } from '@/app/suppliers/risk-actions'
import { Badge, type BadgeTone } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { ConfirmDialog } from '@/components/ui/confirm-dialog'
import { Input } from '@/components/ui/input'
import { SafeExternalLink } from '@/components/safe-external-link'
import { useWorkspaceFormat } from '@/components/workspace-format-provider'

type Person = { full_name: string | null; email: string }
export type SupplierRisk = {
  id: string
  risk_title: string
  identified_on: string
  severity: 'Low' | 'Medium' | 'High' | 'Critical'
  risk_status: 'Open' | 'Monitoring' | 'Resolved'
  description: string
  target_resolution_date: string | null
  evidence_url: string | null
  owner: Person | Person[] | null
}

const initialState: RiskActionState = { status: 'idle', message: '' }
const severities = ['Low', 'Medium', 'High', 'Critical'] as const
const statuses = ['Open', 'Monitoring', 'Resolved'] as const

function ownerName(owner: SupplierRisk['owner']) {
  const person = Array.isArray(owner) ? owner[0] : owner
  return person?.full_name || person?.email || 'Former workspace member'
}

function severityTone(severity: SupplierRisk['severity']): BadgeTone {
  if (severity === 'Critical' || severity === 'High') return 'danger'
  if (severity === 'Medium') return 'warning'
  return 'neutral'
}

export function SupplierRiskRegister({ supplierId, risks, canEdit, today }: { supplierId: string; risks: SupplierRisk[]; canEdit: boolean; today: string }) {
  const { formatDate } = useWorkspaceFormat()
  const [editor, setEditor] = useState<'new' | string | null>(null)
  const [deleteTarget, setDeleteTarget] = useState<SupplierRisk | null>(null)
  const [deleteError, setDeleteError] = useState('')
  const handleDelete = async () => {
    if (!deleteTarget) return
    const result = await deleteSupplierRisk(supplierId, deleteTarget.id)
    if (result.status === 'error') setDeleteError(result.message)
    else setDeleteError('')
  }

  return <div>
    <div className="flex flex-wrap items-center justify-between gap-3 border-b border-[var(--border)] px-5 py-4">
      <div><h2 className="text-sm font-semibold text-[var(--text)]">Risk register</h2><p className="mt-1 text-xs text-[var(--text-3)]">Structured issues and evidence; overall relationship risk remains a separate judgment</p></div>
      {canEdit && editor !== 'new' ? <Button type="button" variant="secondary" size="sm" onClick={() => setEditor('new')}><Plus className="h-3.5 w-3.5" aria-hidden="true" />Add risk</Button> : null}
    </div>
    {editor === 'new' ? <RiskEditor supplierId={supplierId} risk={null} today={today} onClose={() => setEditor(null)} /> : null}
    {risks.length ? <div className="divide-y divide-[var(--border)]">{risks.map(risk => editor === risk.id
      ? <RiskEditor key={risk.id} supplierId={supplierId} risk={risk} today={today} onClose={() => setEditor(null)} />
      : <article key={risk.id} className="px-5 py-4"><div className="flex flex-wrap items-start justify-between gap-3"><div><div className="flex flex-wrap items-center gap-2"><h3 className="font-medium text-[var(--text)]">{risk.risk_title}</h3><Badge tone={severityTone(risk.severity)}>{risk.severity}</Badge><Badge tone={risk.risk_status === 'Resolved' ? 'success' : 'neutral'}>{risk.risk_status}</Badge></div><p className="mt-1 text-xs text-[var(--text-3)]">Identified {formatDate(risk.identified_on)} · {ownerName(risk.owner)}</p></div>{canEdit ? <div className="flex gap-1"><Button type="button" variant="ghost" size="sm" onClick={() => setEditor(risk.id)} aria-label={`Edit ${risk.risk_title}`}><Pencil className="h-3.5 w-3.5" aria-hidden="true" /></Button><Button type="button" variant="ghost" size="sm" onClick={() => setDeleteTarget(risk)} aria-label={`Delete ${risk.risk_title}`}><Trash2 className="h-3.5 w-3.5" aria-hidden="true" /></Button></div> : null}</div><p className="mt-3 whitespace-pre-wrap text-sm leading-6 text-[var(--text-2)]">{risk.description}</p><div className="mt-3 flex flex-wrap gap-x-5 gap-y-2 text-xs text-[var(--text-2)]">{risk.target_resolution_date ? <span>Target resolution {formatDate(risk.target_resolution_date)}</span> : null}<SafeExternalLink href={risk.evidence_url} className="inline-flex items-center gap-1 text-[var(--brand-ink)] hover:underline">Evidence<ExternalLink className="h-3 w-3" aria-hidden="true" /></SafeExternalLink></div></article>)}</div>
      : editor !== 'new' ? <div className="p-6 text-center"><ShieldAlert className="mx-auto h-5 w-5 text-[var(--text-3)]" aria-hidden="true" /><p className="mt-2 text-sm text-[var(--text-2)]">No structured supplier risks have been added yet.</p></div> : null}
    {deleteError ? <p className="border-t border-[var(--border)] px-5 py-3 text-sm text-[var(--danger)]" aria-live="polite">{deleteError}</p> : null}
    {deleteTarget ? <ConfirmDialog title="Delete this supplier risk?" description={`${deleteTarget.risk_title} will be removed. The change will remain in workspace audit history.`} onConfirm={handleDelete} onCancel={() => setDeleteTarget(null)} /> : null}
  </div>
}

function RiskEditor({ supplierId, risk, today, onClose }: { supplierId: string; risk: SupplierRisk | null; today: string; onClose: () => void }) {
  const action = saveSupplierRisk.bind(null, supplierId, risk?.id || null)
  const [state, formAction, pending] = useActionState(action, initialState)
  useEffect(() => { if (state.status === 'success') onClose() }, [onClose, state.status])
  return <form action={formAction} className="border-b border-[var(--border)] bg-[var(--surface-2)] px-5 py-4"><fieldset disabled={pending} className="grid gap-4 disabled:opacity-70 sm:grid-cols-2">
    <label className="text-xs font-medium text-[var(--text-2)]">Risk title *<Input name="riskTitle" defaultValue={risk?.risk_title || ''} className="mt-1.5" required autoFocus /></label>
    <label className="text-xs font-medium text-[var(--text-2)]">Identified on *<Input name="identifiedOn" type="date" defaultValue={risk?.identified_on || today} className="mt-1.5" required /></label>
    <label className="text-xs font-medium text-[var(--text-2)]">Severity *<select name="severity" defaultValue={risk?.severity || 'Medium'} required className="mt-1.5 w-full rounded-md border border-[var(--border-strong)] bg-[var(--surface)] px-3 py-2 text-sm text-[var(--text)] focus:border-[var(--brand)] focus:outline-none focus:ring-2 focus:ring-[var(--brand)]/30">{severities.map(value => <option key={value}>{value}</option>)}</select></label>
    <label className="text-xs font-medium text-[var(--text-2)]">Status *<select name="riskStatus" defaultValue={risk?.risk_status || 'Open'} required className="mt-1.5 w-full rounded-md border border-[var(--border-strong)] bg-[var(--surface)] px-3 py-2 text-sm text-[var(--text)] focus:border-[var(--brand)] focus:outline-none focus:ring-2 focus:ring-[var(--brand)]/30">{statuses.map(value => <option key={value}>{value}</option>)}</select></label>
    <label className="text-xs font-medium text-[var(--text-2)]">Target resolution<Input name="targetResolutionDate" type="date" defaultValue={risk?.target_resolution_date || ''} className="mt-1.5" /></label>
    <label className="text-xs font-medium text-[var(--text-2)]">Evidence link<Input name="evidenceUrl" type="url" defaultValue={risk?.evidence_url || ''} className="mt-1.5" placeholder="https://" /></label>
    <label className="text-xs font-medium text-[var(--text-2)] sm:col-span-2">Description *<textarea name="description" rows={4} maxLength={10000} defaultValue={risk?.description || ''} required className="mt-1.5 w-full resize-y rounded-md border border-[var(--border-strong)] bg-[var(--surface)] px-3 py-2 text-sm text-[var(--text)] transition-colors focus:border-[var(--brand)] focus:outline-none focus:ring-2 focus:ring-[var(--brand)]/30" /></label>
  </fieldset>{state.status === 'error' ? <p className="mt-3 text-sm text-[var(--danger)]" aria-live="polite">{state.message}</p> : null}<div className="mt-4 flex flex-wrap justify-end gap-2"><Button type="button" variant="secondary" size="sm" onClick={onClose} disabled={pending}>Cancel</Button><Button type="submit" size="sm" disabled={pending}>{pending ? 'Saving…' : risk ? 'Save risk' : 'Add risk'}</Button></div></form>
}
