'use client'

import { useActionState, useEffect, useState } from 'react'
import { ClipboardCheck, Pencil, Plus, Trash2 } from 'lucide-react'
import { deleteSupplierReview, saveSupplierReview, type ReviewActionState } from '@/app/suppliers/review-actions'
import { Badge, type BadgeTone } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { ConfirmDialog } from '@/components/ui/confirm-dialog'
import { Input } from '@/components/ui/input'
import { useWorkspaceFormat } from '@/components/workspace-format-provider'

type Person = { full_name: string | null; email: string }
export type SupplierPerformanceReview = {
  id: string
  review_title: string
  review_date: string
  overall_score: number
  delivery_score: number | null
  quality_score: number | null
  commercial_score: number | null
  compliance_score: number | null
  summary: string
  next_review_date: string | null
  reviewer: Person | Person[] | null
}

const initialState: ReviewActionState = { status: 'idle', message: '' }
const scoreOptions = [1, 2, 3, 4, 5]
const scoreFields = [
  ['deliveryScore', 'Delivery', 'delivery_score'],
  ['qualityScore', 'Quality', 'quality_score'],
  ['commercialScore', 'Commercial', 'commercial_score'],
  ['complianceScore', 'Compliance', 'compliance_score'],
] as const

function reviewerName(reviewer: SupplierPerformanceReview['reviewer']) {
  const person = Array.isArray(reviewer) ? reviewer[0] : reviewer
  return person?.full_name || person?.email || 'Former workspace member'
}

function scoreTone(score: number): BadgeTone {
  if (score <= 2) return 'danger'
  if (score >= 4) return 'success'
  return 'neutral'
}

export function SupplierPerformanceReviews({ supplierId, reviews, canEdit, today }: { supplierId: string; reviews: SupplierPerformanceReview[]; canEdit: boolean; today: string }) {
  const { formatDate } = useWorkspaceFormat()
  const [editor, setEditor] = useState<'new' | string | null>(null)
  const [deleteTarget, setDeleteTarget] = useState<SupplierPerformanceReview | null>(null)
  const [deleteError, setDeleteError] = useState('')
  const handleDelete = async () => {
    if (!deleteTarget) return
    const result = await deleteSupplierReview(supplierId, deleteTarget.id)
    if (result.status === 'error') setDeleteError(result.message)
    else setDeleteError('')
  }

  return <div>
    <div className="flex flex-wrap items-center justify-between gap-3 border-b border-[var(--border)] px-5 py-4">
      <div><h2 className="text-sm font-semibold text-[var(--text)]">Performance reviews</h2><p className="mt-1 text-xs text-[var(--text-3)]">Overall performance plus optional unweighted category scores</p></div>
      {canEdit && editor !== 'new' ? <Button type="button" variant="secondary" size="sm" onClick={() => setEditor('new')}><Plus className="h-3.5 w-3.5" aria-hidden="true" />Add review</Button> : null}
    </div>
    {editor === 'new' ? <ReviewEditor supplierId={supplierId} review={null} today={today} onClose={() => setEditor(null)} /> : null}
    {reviews.length ? <div className="divide-y divide-[var(--border)]">{reviews.map(review => editor === review.id
      ? <ReviewEditor key={review.id} supplierId={supplierId} review={review} today={today} onClose={() => setEditor(null)} />
      : <article key={review.id} className="px-5 py-4"><div className="flex flex-wrap items-start justify-between gap-3"><div><div className="flex flex-wrap items-center gap-2"><h3 className="font-medium text-[var(--text)]">{review.review_title}</h3><Badge tone={scoreTone(review.overall_score)}>{review.overall_score}/5 overall</Badge></div><p className="mt-1 text-xs text-[var(--text-3)]">{formatDate(review.review_date)} · {reviewerName(review.reviewer)}</p></div>{canEdit ? <div className="flex gap-1"><Button type="button" variant="ghost" size="sm" onClick={() => setEditor(review.id)} aria-label={`Edit ${review.review_title}`}><Pencil className="h-3.5 w-3.5" aria-hidden="true" /></Button><Button type="button" variant="ghost" size="sm" onClick={() => setDeleteTarget(review)} aria-label={`Delete ${review.review_title}`}><Trash2 className="h-3.5 w-3.5" aria-hidden="true" /></Button></div> : null}</div><div className="mt-3 flex flex-wrap gap-2">{scoreFields.map(([, label, key]) => review[key] ? <Badge key={key} tone="neutral">{label} {review[key]}/5</Badge> : null)}</div><p className="mt-3 whitespace-pre-wrap text-sm leading-6 text-[var(--text-2)]">{review.summary}</p>{review.next_review_date ? <p className="mt-2 text-xs text-[var(--text-3)]">Next review {formatDate(review.next_review_date)}</p> : null}</article>)}</div>
      : editor !== 'new' ? <div className="p-6 text-center"><ClipboardCheck className="mx-auto h-5 w-5 text-[var(--text-3)]" aria-hidden="true" /><p className="mt-2 text-sm text-[var(--text-2)]">No performance reviews have been added yet.</p></div> : null}
    {deleteError ? <p className="border-t border-[var(--border)] px-5 py-3 text-sm text-[var(--danger)]" aria-live="polite">{deleteError}</p> : null}
    {deleteTarget ? <ConfirmDialog title="Delete this performance review?" description={`${deleteTarget.review_title} will be removed. The change will remain in workspace audit history.`} onConfirm={handleDelete} onCancel={() => setDeleteTarget(null)} /> : null}
  </div>
}

function ReviewEditor({ supplierId, review, today, onClose }: { supplierId: string; review: SupplierPerformanceReview | null; today: string; onClose: () => void }) {
  const action = saveSupplierReview.bind(null, supplierId, review?.id || null)
  const [state, formAction, pending] = useActionState(action, initialState)
  useEffect(() => { if (state.status === 'success') onClose() }, [onClose, state.status])
  return <form action={formAction} className="border-b border-[var(--border)] bg-[var(--surface-2)] px-5 py-4"><fieldset disabled={pending} className="grid gap-4 disabled:opacity-70 sm:grid-cols-2">
    <label className="text-xs font-medium text-[var(--text-2)]">Review title *<Input name="reviewTitle" defaultValue={review?.review_title || ''} className="mt-1.5" required autoFocus /></label>
    <label className="text-xs font-medium text-[var(--text-2)]">Review date *<Input name="reviewDate" type="date" defaultValue={review?.review_date || today} className="mt-1.5" required /></label>
    <ScoreSelect name="overallScore" label="Overall score *" value={review?.overall_score || null} required />
    {scoreFields.map(([name, label, key]) => <ScoreSelect key={name} name={name} label={`${label} score`} value={review?.[key] || null} />)}
    <label className="text-xs font-medium text-[var(--text-2)]">Next review date<Input name="nextReviewDate" type="date" defaultValue={review?.next_review_date || ''} className="mt-1.5" /></label>
    <label className="text-xs font-medium text-[var(--text-2)] sm:col-span-2">Summary *<textarea name="summary" rows={4} maxLength={10000} defaultValue={review?.summary || ''} required className="mt-1.5 w-full resize-y rounded-md border border-[var(--border-strong)] bg-[var(--surface)] px-3 py-2 text-sm text-[var(--text)] transition-colors focus:border-[var(--brand)] focus:outline-none focus:ring-2 focus:ring-[var(--brand)]/30" /></label>
  </fieldset>{state.status === 'error' ? <p className="mt-3 text-sm text-[var(--danger)]" aria-live="polite">{state.message}</p> : null}<div className="mt-4 flex flex-wrap justify-end gap-2"><Button type="button" variant="secondary" size="sm" onClick={onClose} disabled={pending}>Cancel</Button><Button type="submit" size="sm" disabled={pending}>{pending ? 'Saving…' : review ? 'Save review' : 'Add review'}</Button></div></form>
}

function ScoreSelect({ name, label, value, required = false }: { name: string; label: string; value: number | null; required?: boolean }) {
  return <label className="text-xs font-medium text-[var(--text-2)]">{label}<select name={name} defaultValue={value || ''} required={required} className="mt-1.5 w-full rounded-md border border-[var(--border-strong)] bg-[var(--surface)] px-3 py-2 text-sm text-[var(--text)] focus:border-[var(--brand)] focus:outline-none focus:ring-2 focus:ring-[var(--brand)]/30"><option value="">{required ? 'Select score' : 'Not scored'}</option>{scoreOptions.map(option => <option key={option} value={option}>{option} / 5</option>)}</select></label>
}
