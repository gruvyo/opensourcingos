'use client'

import { useState, useEffect, useCallback } from 'react'
import { createClient } from '@/lib/supabase/client'
import {
  Plus, Star, Trash2, ChevronDown, Pencil,
  ChevronRight, Shield, Calculator, ShieldCheck, ShieldAlert } from 'lucide-react'
import { formatCurrency, formatDate } from '@/lib/utils'
import { termRates, baselineQuality } from '@/lib/savings'
import { Card } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input, Select } from '@/components/ui/input'
import type { Tables, TablesInsert } from '@/lib/database.types'

type Baseline = {
  id: string
  baseline_name: string
  baseline_type: string
  baseline_source: string | null
  baseline_period_start: string | null
  baseline_period_end: string | null
  baseline_total_amount: number
  baseline_term_months: number | null
  is_selected: boolean
  baseline_normalized_amount: number
  baseline_lock_status: string
  baseline_lock_date: string | null
  official_for_hard_savings: boolean
  official_for_cost_avoidance: boolean
  official_for_demand_reduction: boolean
  // A soft baseline declared defensible as own-spend, with a written reason.
  hard_reduction_override: boolean
  hard_reduction_override_reason: string | null
  hard_reduction_override_at: string | null
}

type ScopeLine = {
  id: string
  line_number: number
  item_service_name: string
  uom: string | null
}

type ScopeLineRelation = Pick<Tables<'event_scope_lines'>, 'item_service_name' | 'uom'>
type BaselineLine = Tables<'baseline_lines'> & {
  scope_line: ScopeLineRelation | null
}
type BaselinePayload = Pick<
  TablesInsert<'baselines'>,
  | 'baseline_name'
  | 'baseline_type'
  | 'baseline_source'
  | 'baseline_period_start'
  | 'baseline_period_end'
  | 'baseline_total_amount'
  | 'baseline_term_months'
>

const BASELINE_TYPES = [
  'Current Contract',
  'Prior 12-Month Actual',
  'Approved Budget',
  'Supplier Renewal Quote',
  'Competitive Bid Benchmark',
  'Market Index',
  'Should-Cost Model',
  'Initial Supplier Quote',
]

const BASELINE_TYPE_DEFENSIBILITY: Record<string, string> = {
  'Current Contract': 'Very High',
  'Prior 12-Month Actual': 'Very High',
  'Approved Budget': 'High',
  'Supplier Renewal Quote': 'Medium-High',
  'Competitive Bid Benchmark': 'Medium-High',
  'Market Index': 'Medium-High',
  'Should-Cost Model': 'Medium',
  'Initial Supplier Quote': 'Medium-Low',
}

export function BaselinesTab({ eventId, scopeLines }: { eventId: string; scopeLines: ScopeLine[] }) {
  const [baselines, setBaselines] = useState<Baseline[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [expandedId, setExpandedId] = useState<string | null>(null)
  const [baselineLines, setBaselineLines] = useState<Record<string, BaselineLine[]>>({})
  const [editingBaseline, setEditingBaseline] = useState<Baseline | null>(null)
  const [editingTotalId, setEditingTotalId] = useState<string | null>(null)
  const [editTotalValue, setEditTotalValue] = useState('')
  const [actionError, setActionError] = useState<string | null>(null)
  const supabase = createClient()

  // Exactly one baseline per project is THE baseline. Clear the others first so
  // the partial unique index can never be violated.
  const selectBaseline = async (baselineId: string) => {
    setActionError(null)
    const clear = await supabase.from('baselines').update({ is_selected: false })
      .eq('event_id', eventId).neq('id', baselineId)
    if (clear.error) { setActionError(clear.error.message); return }
    const set = await supabase.from('baselines').update({ is_selected: true }).eq('id', baselineId)
    // Surface it. A failed write here used to do nothing at all on screen.
    if (set.error) { setActionError(set.error.message); return }
    fetchBaselines()
  }

  const saveTotal = async (baselineId: string) => {
    const v = parseFloat(editTotalValue)
    setEditingTotalId(null)
    if (!Number.isFinite(v)) return
    setActionError(null)
    // MONEY write. Same failure mode as selectBaseline above: a discarded error here
    // used to leave the screen showing a total that was never actually saved.
    const { error } = await supabase.from('baselines').update({ baseline_total_amount: v }).eq('id', baselineId)
    if (error) { setActionError(error.message); return }
    fetchBaselines()
  }

  const fetchBaselines = useCallback(async () => {
    const { data } = await supabase
      .from('baselines')
      .select('*')
      .eq('event_id', eventId)
      .order('created_at', { ascending: true })
    setBaselines(data || [])
    setLoading(false)
  }, [eventId, supabase])

  useEffect(() => {
    fetchBaselines()
  }, [fetchBaselines])

  const fetchBaselineLines = async (baselineId: string) => {
    if (baselineLines[baselineId]) return
    const { data } = await supabase
      .from('baseline_lines')
      .select(`
        *,
        scope_line:event_scope_lines(item_service_name, uom)
      `)
      .eq('baseline_id', baselineId)
      .order('line_number', { ascending: true })
    setBaselineLines(prev => ({ ...prev, [baselineId]: data || [] }))
  }

  const toggleExpand = (baselineId: string) => {
    if (expandedId === baselineId) {
      setExpandedId(null)
    } else {
      setExpandedId(baselineId)
      fetchBaselineLines(baselineId)
    }
  }



  const handleDelete = async (baselineId: string) => {
    if (!confirm('Delete this baseline and all its lines? This cannot be undone.')) return
    setActionError(null)
    const { error } = await supabase.from('baselines').delete().eq('id', baselineId)
    if (error) { setActionError(error.message); return }
    // Only drop it from local state once the delete is confirmed. This used to be
    // optimistic — the row vanished from screen even when RLS or a foreign-key
    // constraint rejected the delete, so a "deleted" baseline was still in the database.
    setBaselines(baselines.filter(b => b.id !== baselineId))
  }

  if (loading) {
    return <div className="p-8 text-center text-sm text-[var(--text-3)]">Loading baselines...</div>
  }

  return (
    <div>
      {/* Header */}
      <div className="mb-4 flex items-center justify-between">
        <div>
          <h3 className="text-lg font-semibold text-[var(--text)]">Baselines</h3>
          <p className="text-sm text-[var(--text-2)]">Establish what the company would have paid without procurement action</p>
        </div>
        <Button onClick={() => setShowForm(!showForm)}>
          <Plus className="h-4 w-4" />
          Add Baseline
        </Button>
      </div>

      {actionError && (
        <div role="alert" className="mb-4 rounded-lg border border-red-200 bg-red-50 p-3 text-sm text-red-700 dark:border-red-800 dark:bg-red-900/30 dark:text-red-300">
          <strong>Could not save:</strong> {actionError}
          {actionError.includes('does not exist') && (
            <span> — this usually means a database migration has not been run yet.</span>
          )}
        </div>
      )}

      {/* Baseline Hierarchy Info */}
      <div className="mb-4 rounded-lg border border-blue-200 dark:border-blue-800 bg-blue-50 dark:bg-blue-900/30 p-4">
        <div className="flex items-start gap-3">
          <Shield className="mt-0.5 h-5 w-5 flex-shrink-0 text-blue-600 dark:text-blue-400" />
          <div>
            {/* This used to rank all eight types on a "defensibility" scale that
                put Approved Budget above Should-Cost Model. That ranking now
                contradicts the rule the numbers actually follow, which is not a
                ranking at all but a line: is this money you paid, or a figure
                somebody quoted? Two groups, not eight rungs. */}
            <h4 className="text-sm font-semibold text-blue-900 dark:text-blue-100">
              What makes a cost reduction hard
            </h4>
            <p className="mt-1 text-xs text-blue-700 dark:text-blue-300">
              A <strong>hard</strong> Cost Reduction — the figure your CFO can book to the P&amp;L —
              requires a baseline grounded in <strong>your own spend</strong>. Current Contract,
              Prior 12-Month Actual and Should-Cost Model qualify.
            </p>
            <p className="mt-1 text-xs text-blue-700 dark:text-blue-300">
              Approved Budget, Supplier Renewal Quote, Competitive Bid Benchmark, Market Index and
              Initial Supplier Quote are reference figures — real and useful, but nobody ever paid
              them. Their value books as <strong>Cost Avoidance</strong> instead.
            </p>
            <p className="mt-1 text-xs text-blue-700 dark:text-blue-300 opacity-90">
              Either way the <strong>Total is the same</strong>. Only the split between the two
              lines moves. Expand a baseline to record an override if a soft type genuinely does
              reflect what you were paying.
            </p>
          </div>
        </div>
      </div>

      {/* Add Baseline Form */}
      {showForm && (
        <AddBaselineForm
          eventId={eventId}
          isFirstBaseline={baselines.length === 0}
          onSaved={() => { setShowForm(false); fetchBaselines() }}
          onCancel={() => setShowForm(false)}
        />
      )}

      {editingBaseline && (
        <AddBaselineForm
          eventId={eventId}
          isFirstBaseline={false}
          existing={editingBaseline}
          onSaved={() => { setEditingBaseline(null); fetchBaselines() }}
          onCancel={() => setEditingBaseline(null)}
        />
      )}

      {/* Baselines List */}
      {baselines.length === 0 ? (
        <Card className="p-12 text-center">
          <Calculator className="mx-auto mb-3 h-10 w-10 text-[var(--text-3)]" />
          <h3 className="text-sm font-medium text-[var(--text)]">No baselines yet</h3>
          <p className="mt-1 text-sm text-[var(--text-3)]">Click &quot;Add Baseline&quot; to establish the baseline for this event.</p>
        </Card>
      ) : (
        <div className="space-y-3">
          {baselines.map((baseline) => {
            const isExpanded = expandedId === baseline.id
            const defensibility = BASELINE_TYPE_DEFENSIBILITY[baseline.baseline_type] || '—'
            const lines = baselineLines[baseline.id] || []

            return (
              <Card key={baseline.id} className="overflow-hidden">
                {/* Baseline Header Row */}
                <div className="flex items-center gap-4 p-4">
                  <button
                    type="button"
                    onClick={() => toggleExpand(baseline.id)}
                    aria-expanded={isExpanded}
                    aria-label={`${isExpanded ? 'Collapse' : 'Expand'} baseline ${baseline.baseline_name}`}
                    className="text-[var(--text-3)] hover:text-[var(--text-2)]"
                  >
                    {isExpanded ? <ChevronDown className="h-5 w-5" /> : <ChevronRight className="h-5 w-5" />}
                  </button>

                  <div className="flex-1">
                    <div className="flex items-center gap-2">
                      <h4 className="text-sm font-semibold text-[var(--text)]">{baseline.baseline_name}</h4>
                      <span className="rounded bg-[var(--surface-2)] px-2 py-0.5 text-xs text-[var(--text-2)]">
                        {baseline.baseline_type}
                      </span>
                      <span className="rounded bg-blue-50 dark:bg-blue-900/30 px-2 py-0.5 text-xs text-blue-600 dark:text-blue-400">
                        {defensibility} defensibility
                      </span>
                    </div>
                    {baseline.baseline_source && (
                      <p className="mt-1 text-xs text-[var(--text-3)]">{baseline.baseline_source}</p>
                    )}
                  </div>

                  {/* Total Amount — click to edit. Lines, when present, still recompute it. */}
                  <div className="text-right">
                    <p className="text-xs text-[var(--text-3)]">
                      Total Baseline
                      {baseline.baseline_term_months ? ` · ${baseline.baseline_term_months} mo` : ''}
                    </p>
                    {editingTotalId === baseline.id ? (
                      <div className="mt-0.5 flex items-center gap-1">
                        <Input type="number" step="0.01" autoFocus value={editTotalValue}
                          onChange={(e) => setEditTotalValue(e.target.value)}
                          onKeyDown={(e) => {
                            if (e.key === 'Enter') { e.preventDefault(); saveTotal(baseline.id) }
                            if (e.key === 'Escape') setEditingTotalId(null)
                          }}
                          className="w-36 py-1 text-right text-sm" />
                        <Button type="button" size="sm" onClick={() => saveTotal(baseline.id)}>Save</Button>
                      </div>
                    ) : (
                      <button type="button" title="Click to edit"
                        onClick={() => { setEditingTotalId(baseline.id); setEditTotalValue(String(baseline.baseline_total_amount ?? '')) }}
                        className="text-lg font-bold text-[var(--text)] underline decoration-dotted underline-offset-4 hover:text-[var(--brand-ink)]">
                        {formatCurrency(baseline.baseline_total_amount)}
                      </button>
                    )}
                    {(() => {
                      const r = termRates(baseline.baseline_total_amount, baseline.baseline_term_months)
                      if (!r.known) return null
                      return (
                        <p className="mt-0.5 text-[11px] text-[var(--text-3)]">
                          {formatCurrency(r.perMonth)}/mo · {formatCurrency(r.perYear)}/yr
                        </p>
                      )
                    })()}
                  </div>


                  {/* Official badges. With a single baseline the per-category
                      distinction is noise, so collapse to one "Official" chip. */}
                  <div className="flex gap-1">
                    {baseline.is_selected ? (
                      <span className="flex items-center gap-1 rounded bg-green-100 px-2 py-1 text-xs font-medium text-green-700 dark:bg-green-900/30 dark:text-green-300"
                        title="This is the baseline the savings chain measures against">
                        <Star className="h-3 w-3 fill-current" /> Baseline
                      </span>
                    ) : (
                      <button onClick={() => selectBaseline(baseline.id)}
                        className="rounded border border-[var(--border-strong)] px-2 py-1 text-xs font-medium text-[var(--text-2)] hover:bg-[var(--surface-2)]"
                        title="Use this as the baseline for the savings chain">
                        Use as baseline
                      </button>
                    )}

                    {/* Whether this type may book a HARD Cost Reduction. Shown on
                        every baseline, not just the selected one, so the
                        consequence of a choice is visible before it is made. */}
                    {(() => {
                      const q = baselineQuality(baseline.baseline_type, {
                        enabled: baseline.hard_reduction_override,
                        reason: baseline.hard_reduction_override_reason,
                      })
                      if (q.isHard && !q.byOverride) {
                        return (
                          <span className="flex items-center gap-1 rounded bg-blue-100 px-2 py-1 text-xs font-medium text-blue-700 dark:bg-blue-900/30 dark:text-blue-300"
                            title={q.explanation}>
                            <ShieldCheck className="h-3 w-3" /> Hard
                          </span>
                        )
                      }
                      if (q.byOverride) {
                        return (
                          <span className="flex items-center gap-1 rounded bg-amber-100 px-2 py-1 text-xs font-medium text-amber-700 dark:bg-amber-900/30 dark:text-amber-300"
                            title={`Booked as hard by override: ${baseline.hard_reduction_override_reason}`}>
                            <ShieldAlert className="h-3 w-3" /> Hard by override
                          </span>
                        )
                      }
                      return (
                        <span className="flex items-center gap-1 rounded bg-[var(--surface-2)] px-2 py-1 text-xs font-medium text-[var(--text-2)]"
                          title={q.explanation}>
                          Soft — books as avoidance
                        </span>
                      )
                    })()}
                    {/* The "Hard $" / "Avoid" / "Demand" badges lived here. They
                        rendered official_for_hard_savings and its two siblings,
                        which are only ever written at INSERT (true for the first
                        baseline) -- the "Mark Official" control that could change
                        them was retired on 2026-07-26. So they pinned themselves
                        to whichever baseline happened to be added first and then
                        contradicted the "Selected" badge above forever after.
                        The columns still exist; nothing reads them. */}
                  </div>
                </div>

                {/* Expanded View */}
                {isExpanded && (
                  <div className="border-t border-[var(--border)] bg-[var(--surface-2)]">
                    {/* Actions. The Lock -> Submit -> Approve -> Reject workflow and the
                        per-category "Mark Official" toggles were removed: the real process has
                        no baseline-approval concept, and the savings calculation no longer
                        depends on which baseline is flagged official. Baselines stay editable. */}
                    <div className="flex items-center justify-end gap-3 border-b border-[var(--border)] bg-[var(--surface)] px-4 py-2">
                      <button onClick={() => setEditingBaseline(baseline)}
                        className="flex items-center gap-1 text-xs font-medium text-[var(--brand-ink)] hover:underline">
                        <Pencil className="h-3.5 w-3.5" /> Edit baseline
                      </button>
                      <button type="button" onClick={() => handleDelete(baseline.id)}
                        aria-label={`Delete baseline ${baseline.baseline_name}`}
                        className="text-[var(--text-3)] hover:text-red-600 dark:hover:text-red-400">
                        <Trash2 className="h-4 w-4" />
                      </button>
                    </div>

                    {/* The hard/soft override. Only offered where it can matter:
                        a type that does not already qualify on its own. */}
                    <HardReductionOverride
                      baseline={baseline}
                      onChanged={fetchBaselines}
                      onError={setActionError}
                    />

                    {/* Baseline Lines Table */}
                    <BaselineLinesTable
                      baselineId={baseline.id}
                      eventId={eventId}
                      scopeLines={scopeLines}
                      lines={lines}
                      onLinesChanged={() => fetchBaselineLines(baseline.id)}
                      isLocked={baseline.baseline_lock_status !== 'Draft'}
                    />
                  </div>
                )}
              </Card>
            )
          })}
        </div>
      )}
    </div>
  )
}

/**
 * Declare a soft baseline defensible enough to book a HARD cost reduction.
 *
 * The governing principle is that a hard reduction needs a baseline grounded
 * in your own spend. Real deals break that occasionally for honest reasons —
 * the invoices are gone, but the incumbent's renewal quote is known to match
 * what was actually being paid — so the rule bends rather than blocking work.
 *
 * It bends ON THE RECORD. The reason is mandatory (a CHECK constraint enforces
 * it, not just this form), it is stamped with who and when, and it is shown on
 * the Calculations tab, in reports and in the CSV. An override nobody can find
 * later is not defensible; one that appears in every report is.
 */
function HardReductionOverride({
  baseline,
  onChanged,
  onError,
}: {
  baseline: Baseline
  onChanged: () => void
  onError: (m: string | null) => void
}) {
  const supabase = createClient()
  const [open, setOpen] = useState(false)
  const [reason, setReason] = useState(baseline.hard_reduction_override_reason || '')
  const [busy, setBusy] = useState(false)

  const q = baselineQuality(baseline.baseline_type, {
    enabled: baseline.hard_reduction_override,
    reason: baseline.hard_reduction_override_reason,
  })

  // A type that qualifies on its own has nothing to override.
  if (q.isHard && !q.byOverride) return null

  const MIN = 10

  const apply = async (enable: boolean) => {
    onError(null)
    if (enable && reason.trim().length < MIN) return
    setBusy(true)
    const { data: { user } } = await supabase.auth.getUser()
    const { error } = await supabase.from('baselines').update(
      enable
        ? {
            hard_reduction_override: true,
            hard_reduction_override_reason: reason.trim(),
            hard_reduction_override_by: user?.id ?? null,
            hard_reduction_override_at: new Date().toISOString(),
          }
        : {
            hard_reduction_override: false,
            hard_reduction_override_reason: null,
            hard_reduction_override_by: null,
            hard_reduction_override_at: null,
          },
    ).eq('id', baseline.id)
    setBusy(false)
    if (error) { onError(error.message); return }
    setOpen(false)
    onChanged()
  }

  return (
    <div className="border-b border-[var(--border)] bg-[var(--surface)] px-4 py-3">
      {q.byOverride ? (
        <div className="flex flex-wrap items-start justify-between gap-3">
          <div className="text-xs text-amber-700 dark:text-amber-300">
            <p className="font-semibold">Booked as a hard cost reduction by override</p>
            <p className="mt-0.5 italic">&ldquo;{baseline.hard_reduction_override_reason}&rdquo;</p>
            {baseline.hard_reduction_override_at && (
              <p className="mt-0.5 text-[var(--text-3)]">
                Recorded {formatDate(baseline.hard_reduction_override_at)}
              </p>
            )}
          </div>
          <Button size="sm" variant="secondary" disabled={busy} onClick={() => apply(false)}>
            {busy ? 'Working...' : 'Remove override'}
          </Button>
        </div>
      ) : !open ? (
        <div className="flex flex-wrap items-center justify-between gap-3">
          <p className="text-xs text-[var(--text-2)]">
            {q.explanation} Its value books as <strong>Cost Avoidance</strong> instead — the Total is
            the same either way.
          </p>
          <Button size="sm" variant="secondary" onClick={() => setOpen(true)}>
            Book as hard anyway
          </Button>
        </div>
      ) : (
        <div>
          <label htmlFor={`ovr-${baseline.id}`} className="block text-xs font-medium text-[var(--text-2)]">
            Why is this baseline defensible as your own spend?
          </label>
          <p className="mt-0.5 text-[11px] text-[var(--text-3)]">
            This is shown on the Calculations tab and in every report that carries the number, so
            write it for whoever asks about it a year from now.
          </p>
          <textarea
            id={`ovr-${baseline.id}`}
            value={reason}
            onChange={(e) => setReason(e.target.value)}
            rows={2}
            placeholder="e.g. Invoices lost in the ERP migration; this renewal quote matches the AP records we do have."
            className="mt-2 w-full rounded-md border border-[var(--border-strong)] bg-[var(--surface)] px-3 py-2 text-sm text-[var(--text)] placeholder:text-[var(--text-3)] focus:border-[var(--brand)] focus:outline-none focus:ring-2 focus:ring-[var(--brand)]/30"
          />
          <div className="mt-2 flex items-center justify-end gap-2">
            <span className="mr-auto text-[11px] text-[var(--text-3)]">
              {reason.trim().length < MIN
                ? `${MIN - reason.trim().length} more characters needed`
                : 'Ready'}
            </span>
            <Button size="sm" variant="secondary" onClick={() => { setOpen(false); setReason(baseline.hard_reduction_override_reason || '') }}>
              Cancel
            </Button>
            <Button size="sm" disabled={busy || reason.trim().length < MIN} onClick={() => apply(true)}>
              {busy ? 'Saving...' : 'Record override'}
            </Button>
          </div>
        </div>
      )}
    </div>
  )
}

// ============================================
// Add Baseline Form
// ============================================
function AddBaselineForm({ eventId, isFirstBaseline, existing, onSaved, onCancel }: {
  eventId: string
  isFirstBaseline: boolean
  /** When set, the form edits this baseline instead of creating a new one. */
  existing?: Baseline | null
  onSaved: () => void
  onCancel: () => void
}) {
  const supabase = createClient()
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const isEdit = !!existing
  const [form, setForm] = useState({
    baseline_type: existing?.baseline_type ?? '',
    baseline_source: existing?.baseline_source ?? '',
    baseline_period_start: existing?.baseline_period_start ?? '',
    baseline_period_end: existing?.baseline_period_end ?? '',
    baseline_total_amount: existing ? String(existing.baseline_total_amount ?? '') : '',
    baseline_term_months: existing ? String(existing.baseline_term_months ?? '12') : '12',
  })

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    setLoading(true)
    setError(null)

    const { data: { user } } = await supabase.auth.getUser()
    if (!user) { setError('Not logged in'); setLoading(false); return }

    const { data: profile } = await supabase
      .from('profiles')
      .select('organization_id')
      .eq('id', user!.id)
      .single()

    // baseline_name is NOT NULL in the schema but is redundant on screen: the
    // type plus the source already identify a baseline. Derive it.
    const derivedName = [form.baseline_type, form.baseline_source].filter(Boolean).join(' - ')

    const payload: BaselinePayload = {
      baseline_name: derivedName || form.baseline_type || 'Baseline',
      baseline_type: form.baseline_type,
      baseline_source: form.baseline_source || null,
      baseline_period_start: form.baseline_period_start || null,
      baseline_period_end: form.baseline_period_end || null,
      baseline_total_amount: form.baseline_total_amount === '' ? 0 : parseFloat(form.baseline_total_amount),
      baseline_term_months: form.baseline_term_months === '' ? null : parseFloat(form.baseline_term_months),
    }

    if (isEdit) {
      const { error: updateError } = await supabase
        .from('baselines').update(payload).eq('id', existing!.id)
      if (updateError) { setError(updateError.message); setLoading(false); return }
      onSaved()
      return
    }

    const { error: insertError } = await supabase
      .from('baselines')
      .insert({
        ...payload,
        organization_id: profile?.organization_id,
        event_id: eventId,
        // First baseline on an event is the official one for every category. The
        // manual Mark-Official step was removed; nothing in the savings math reads
        // these now, but the offers-tab comparison still uses them.
        official_for_hard_savings: isFirstBaseline,
        official_for_cost_avoidance: isFirstBaseline,
        official_for_demand_reduction: isFirstBaseline,
        created_by: user.id,
      })

    if (insertError) {
      setError(insertError.message)
      setLoading(false)
      return
    }

    onSaved()
  }

  const labelClass = 'block text-xs font-medium text-[var(--text-2)]'

  return (
    <form onSubmit={handleSubmit} className="mb-6 rounded-lg border border-indigo-200 dark:border-indigo-800 bg-indigo-50 dark:bg-indigo-900/30 p-6">
      <h4 className="mb-4 font-medium text-[var(--text)]">{isEdit ? 'Edit Baseline' : 'New Baseline'}</h4>
      {error && <div role="alert" className="mb-4 rounded bg-red-50 dark:bg-red-900/30 p-3 text-sm text-red-700 dark:text-red-300">{error}</div>}
      <div className="grid grid-cols-1 gap-4 md:grid-cols-2">
        <div>
          <label className={labelClass}>Baseline Type *</label>
          <Select required value={form.baseline_type}
            onChange={(e) => setForm({ ...form, baseline_type: e.target.value })}
            className="mt-1">
            <option value="">Select type...</option>
            {BASELINE_TYPES.map((t) => (
              <option key={t} value={t}>{t} ({BASELINE_TYPE_DEFENSIBILITY[t]})</option>
            ))}
          </Select>
        </div>
        <div>
          <label className={labelClass}>Source</label>
          <Input type="text" value={form.baseline_source}
            onChange={(e) => setForm({ ...form, baseline_source: e.target.value })}
            className="mt-1" placeholder="e.g. Existing contract rate card" />
        </div>
        <div>
          <label className={labelClass}>Baseline Total ($) *</label>
          <Input type="number" step="0.01" required value={form.baseline_total_amount}
            onChange={(e) => setForm({ ...form, baseline_total_amount: e.target.value })}
            className="mt-1" placeholder="e.g. 1000000" />
        </div>
        <div>
          <label className={labelClass}>Term (months) *</label>
          <Input type="number" step="1" min="1" required value={form.baseline_term_months}
            onChange={(e) => setForm({ ...form, baseline_term_months: e.target.value })}
            className="mt-1" placeholder="12" />
        </div>
        <div className="md:col-span-2 -mt-1">
          {(() => {
            const r = termRates(form.baseline_total_amount, form.baseline_term_months)
            return (
              <p className="text-xs text-[var(--text-3)]">
                {r.known
                  ? <>That is <strong className="text-[var(--text-2)]">{formatCurrency(r.perMonth)}/month</strong> · <strong className="text-[var(--text-2)]">{formatCurrency(r.perYear)}/year</strong>. The term lets a 12-month baseline be compared with, say, a 36-month offer.</>
                  : <>Enter the total and the number of months it covers. Line detail is optional.</>}
              </p>
            )
          })()}
        </div>
        <div>
          <label className={labelClass}>Period Start</label>
          <Input type="date" value={form.baseline_period_start}
            onChange={(e) => setForm({ ...form, baseline_period_start: e.target.value })}
            className="mt-1" />
        </div>
        <div>
          <label className={labelClass}>Period End</label>
          <Input type="date" value={form.baseline_period_end}
            onChange={(e) => setForm({ ...form, baseline_period_end: e.target.value })}
            className="mt-1" />
        </div>
      </div>
      <div className="mt-4 flex justify-end gap-2">
        <Button type="button" variant="secondary" onClick={onCancel}>
          Cancel
        </Button>
        <Button type="submit" disabled={loading}>
          {loading ? 'Saving...' : isEdit ? 'Save Changes' : 'Create Baseline'}
        </Button>
      </div>
    </form>
  )
}

// ============================================
// Baseline Lines Table (with calculations)
// ============================================
function BaselineLinesTable({ baselineId, eventId, scopeLines, lines: initialLines, onLinesChanged, isLocked }: {
  baselineId: string
  eventId: string
  scopeLines: ScopeLine[]
  lines: BaselineLine[]
  onLinesChanged: () => void
  isLocked: boolean
}) {
  const supabase = createClient()
  const [lines, setLines] = useState(initialLines)
  const [showAddLine, setShowAddLine] = useState(false)
  // Surfaces errors from the insert/delete/total writes below, same pattern as
  // actionError in the parent BaselinesTab component.
  const [error, setError] = useState<string | null>(null)
  const [newLine, setNewLine] = useState({
    scope_line_id: '',
    baseline_unit_price: '',
    baseline_quantity: '',
    baseline_term_months: '12',
    baseline_recurring_amount: '',
    baseline_one_time_amount: '',
  })

  useEffect(() => { setLines(initialLines) }, [initialLines])

  // Auto-calculate extended amount
  const calcExtended = (price: number, qty: number) => price * qty

  // Auto-calculate annualized amount
  const calcAnnualized = (extended: number, termMonths: number) => {
    if (!termMonths || termMonths === 0) return 0
    return (extended * 12) / termMonths
  }

  // Re-query baseline_lines (same shape as the parent's fetchBaselineLines) and total
  // from THOSE rows, not from the `lines` React state. `lines` is only ever as fresh as
  // the last render — reading it right after an insert/delete `await` chain can still see
  // the pre-update value, which used to total (and WRITE, as the baseline total) a stale
  // array: the first line added wrote a total of 0, and a delete left the removed amount
  // in. Two rapid clicks raced the same way. Always total off what the database actually
  // has, and refresh local state from the same fetch so the two can never disagree.
  const refreshLinesAndTotal = async () => {
    const { data: freshLines, error: fetchError } = await supabase
      .from('baseline_lines')
      .select(`
        *,
        scope_line:event_scope_lines(item_service_name, uom)
      `)
      .eq('baseline_id', baselineId)
      .order('line_number', { ascending: true })

    if (fetchError) { setError(fetchError.message); return }

    const freshRows = freshLines || []
    setLines(freshRows)
    await updateBaselineTotal(freshRows)
  }

  const handleAddLine = async (e: React.FormEvent) => {
    e.preventDefault()
    setError(null)

    const unitPrice = parseFloat(newLine.baseline_unit_price) || 0
    const qty = parseFloat(newLine.baseline_quantity) || 0
    const termMonths = parseFloat(newLine.baseline_term_months) || 12
    const extended = calcExtended(unitPrice, qty)
    const annualized = calcAnnualized(extended, termMonths)
    const recurring = parseFloat(newLine.baseline_recurring_amount) || extended
    const oneTime = parseFloat(newLine.baseline_one_time_amount) || 0

    const { data: { user } } = await supabase.auth.getUser()
    const { data: profile } = await supabase
      .from('profiles')
      .select('organization_id')
      .eq('id', user!.id)
      .single()

    const lineNumber = lines.length + 1

    const { data, error: insertError } = await supabase
      .from('baseline_lines')
      .insert({
        organization_id: profile?.organization_id,
        baseline_id: baselineId,
        event_id: eventId,
        scope_line_id: newLine.scope_line_id || null,
        line_number: lineNumber,
        baseline_unit_price: unitPrice,
        baseline_quantity: qty,
        baseline_extended_amount: extended,
        baseline_recurring_amount: recurring,
        baseline_one_time_amount: oneTime,
        baseline_term_months: termMonths,
        annualized_baseline_amount: annualized,
        normalized_quantity: qty,
        normalized_unit_price: unitPrice,
        normalized_extended_amount: extended,
      })
      .select(`
        *,
        scope_line:event_scope_lines(item_service_name, uom)
      `)
      .single()

    // This used to be gated on `if (!error && data)` with no else branch — the error
    // was checked but never shown anywhere, so a rejected insert just silently did nothing.
    if (insertError || !data) {
      setError(insertError?.message || 'Could not add the line.')
      return
    }

    setNewLine({
      scope_line_id: '', baseline_unit_price: '', baseline_quantity: '',
      baseline_term_months: '12', baseline_recurring_amount: '', baseline_one_time_amount: '',
    })
    setShowAddLine(false)
    onLinesChanged()
    await refreshLinesAndTotal()
  }

  const handleDeleteLine = async (lineId: string) => {
    if (!confirm('Delete this baseline line? This cannot be undone.')) return
    setError(null)
    const { error: deleteError } = await supabase.from('baseline_lines').delete().eq('id', lineId)
    if (deleteError) { setError(deleteError.message); return }
    onLinesChanged()
    await refreshLinesAndTotal()
  }

  const updateBaselineTotal = async (currentLines: BaselineLine[]) => {
    const total = currentLines.reduce((sum, l) => sum + (l.baseline_extended_amount || 0), 0)
    // MONEY write — this total is the minuend of every savings calculation downstream.
    const { error: updateError } = await supabase.from('baselines').update({ baseline_total_amount: total }).eq('id', baselineId)
    if (updateError) setError(updateError.message)
  }

  const labelClass = 'block text-xs font-medium text-[var(--text-3)] mb-1'

  const totalExtended = lines.reduce((sum, l) => sum + (l.baseline_extended_amount || 0), 0)
  const totalAnnualized = lines.reduce((sum, l) => sum + (l.annualized_baseline_amount || 0), 0)

  return (
    <div className="p-4">
      <div className="mb-3 flex items-center justify-between">
        <div>
          <h5 className="text-sm font-medium text-[var(--text-2)]">Line detail (optional)</h5>
          <p className="text-xs text-[var(--text-3)]">
            Only if you want item-level breakdown. Adding lines replaces the total above with
            their sum. Most deals just need the total.
          </p>
        </div>
        {!isLocked && (
          <button onClick={() => setShowAddLine(!showAddLine)}
            className="flex items-center gap-1 rounded bg-[var(--surface)] px-2.5 py-1 text-xs font-medium text-indigo-600 dark:text-indigo-400 hover:bg-indigo-50 dark:bg-indigo-900/30">
            <Plus className="h-3 w-3" /> Add Line
          </button>
        )}
      </div>

      {error && (
        <div role="alert" className="mb-4 rounded bg-red-50 dark:bg-red-900/30 p-3 text-sm text-red-700 dark:text-red-300">
          {error}
        </div>
      )}

      {/* Add Line Form */}
      {showAddLine && !isLocked && (
        <form onSubmit={handleAddLine} className="mb-4 rounded border border-indigo-200 dark:border-indigo-800 bg-[var(--surface)] p-4">
          <div className="grid grid-cols-1 gap-3 md:grid-cols-4">
            <div className="md:col-span-4">
              <label className={labelClass}>Scope Line (optional — link to existing scope)</label>
              <Select value={newLine.scope_line_id}
                onChange={(e) => setNewLine({ ...newLine, scope_line_id: e.target.value })}
                className="px-2 py-1 text-xs">
                <option value="">None</option>
                {scopeLines.map((sl) => (
                  <option key={sl.id} value={sl.id}>
                    {sl.line_number}. {sl.item_service_name} ({sl.uom || '—'})
                  </option>
                ))}
              </Select>
            </div>
            <div>
              <label className={labelClass}>Unit Price</label>
              <Input type="number" step="0.0001" required value={newLine.baseline_unit_price}
                onChange={(e) => setNewLine({ ...newLine, baseline_unit_price: e.target.value })}
                className="px-2 py-1 text-xs" placeholder="0.00" />
            </div>
            <div>
              <label className={labelClass}>Quantity</label>
              <Input type="number" step="0.01" required value={newLine.baseline_quantity}
                onChange={(e) => setNewLine({ ...newLine, baseline_quantity: e.target.value })}
                className="px-2 py-1 text-xs" placeholder="0" />
            </div>
            <div>
              <label className={labelClass}>Term (months)</label>
              <Input type="number" step="0.01" value={newLine.baseline_term_months}
                onChange={(e) => setNewLine({ ...newLine, baseline_term_months: e.target.value })}
                className="px-2 py-1 text-xs" placeholder="12" />
            </div>
            <div>
              <label className={labelClass}>Extended (auto)</label>
              <div className="rounded border border-[var(--border)] bg-[var(--surface-2)] px-2 py-1 text-xs text-[var(--text-2)]">
                {formatCurrency(calcExtended(
                  parseFloat(newLine.baseline_unit_price) || 0,
                  parseFloat(newLine.baseline_quantity) || 0
                ))}
              </div>
            </div>
            <div>
              <label className={labelClass}>One-Time Amount</label>
              <Input type="number" step="0.01" value={newLine.baseline_one_time_amount}
                onChange={(e) => setNewLine({ ...newLine, baseline_one_time_amount: e.target.value })}
                className="px-2 py-1 text-xs" placeholder="0" />
            </div>
          </div>
          <div className="mt-3 flex justify-end gap-2">
            <Button type="button" variant="secondary" size="sm" onClick={() => setShowAddLine(false)}>
              Cancel
            </Button>
            <Button type="submit" size="sm">
              Add Line
            </Button>
          </div>
        </form>
      )}

      {/* Lines Table */}
      {lines.length === 0 ? (
        <p className="py-6 text-center text-xs text-[var(--text-3)]">
          No baseline lines yet. {!isLocked && 'Click "Add Line" to add pricing.'}
        </p>
      ) : (
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <caption className="sr-only">Baseline pricing lines</caption>
            <thead>
              <tr className="border-b border-[var(--border)] text-left text-xs uppercase text-[var(--text-3)]">
                <th scope="col" className="px-2 py-2">#</th>
                <th scope="col" className="px-2 py-2">Scope Line</th>
                <th scope="col" className="px-2 py-2 text-right">Unit Price</th>
                <th scope="col" className="px-2 py-2 text-right">Qty</th>
                <th scope="col" className="px-2 py-2 text-right">Extended</th>
                <th scope="col" className="px-2 py-2 text-right">Recurring</th>
                <th scope="col" className="px-2 py-2 text-right">One-Time</th>
                <th scope="col" className="px-2 py-2 text-right">Term (mo)</th>
                <th scope="col" className="px-2 py-2 text-right">Annualized</th>
                {!isLocked && <th scope="col" aria-label="Actions" className="px-2 py-2"></th>}
              </tr>
            </thead>
            <tbody className="divide-y divide-[var(--border)]">
              {lines.map((line) => (
                <tr key={line.id} className="hover:bg-[var(--surface-2)]">
                  <td className="px-2 py-2 text-xs text-[var(--text-3)]">{line.line_number}</td>
                  <td className="px-2 py-2 text-xs">
                    <div className="font-medium text-[var(--text)]">
                      {line.scope_line?.item_service_name || '—'}
                    </div>
                    {line.scope_line?.uom && (
                      <div className="text-[var(--text-3)]">{line.scope_line.uom}</div>
                    )}
                  </td>
                  <td className="px-2 py-2 text-right text-xs text-[var(--text-2)]">
                    {line.baseline_unit_price ? formatCurrency(line.baseline_unit_price) : '—'}
                  </td>
                  <td className="px-2 py-2 text-right text-xs text-[var(--text-2)]">{line.baseline_quantity ?? '—'}</td>
                  <td className="px-2 py-2 text-right text-xs font-medium text-[var(--text)]">
                    {formatCurrency(line.baseline_extended_amount)}
                  </td>
                  <td className="px-2 py-2 text-right text-xs text-[var(--text-2)]">
                    {formatCurrency(line.baseline_recurring_amount)}
                  </td>
                  <td className="px-2 py-2 text-right text-xs text-[var(--text-2)]">
                    {formatCurrency(line.baseline_one_time_amount)}
                  </td>
                  <td className="px-2 py-2 text-right text-xs text-[var(--text-2)]">{line.baseline_term_months ?? '—'}</td>
                  <td className="px-2 py-2 text-right text-xs font-medium text-indigo-700 dark:text-indigo-300">
                    {formatCurrency(line.annualized_baseline_amount)}
                  </td>
                  {!isLocked && (
                    <td className="px-2 py-2 text-right">
                      <button type="button" onClick={() => handleDeleteLine(line.id)}
                        aria-label={`Delete baseline line ${line.line_number}`}
                        className="text-[var(--text-3)] hover:text-red-600 dark:text-red-400">
                        <Trash2 className="h-3.5 w-3.5" />
                      </button>
                    </td>
                  )}
                </tr>
              ))}
            </tbody>
            <tfoot>
              <tr className="border-t-2 border-[var(--border)] bg-[var(--surface-2)] font-medium">
                <td colSpan={4} className="px-2 py-2 text-right text-xs text-[var(--text-2)]">Totals:</td>
                <td className="px-2 py-2 text-right text-xs font-bold text-[var(--text)]">{formatCurrency(totalExtended)}</td>
                <td colSpan={2} className="px-2 py-2"></td>
                <td className="px-2 py-2 text-right text-xs text-[var(--text-2)]">Annual:</td>
                <td className="px-2 py-2 text-right text-xs font-bold text-indigo-700 dark:text-indigo-300">{formatCurrency(totalAnnualized)}</td>
                {!isLocked && <td className="px-2 py-2"></td>}
              </tr>
            </tfoot>
          </table>
        </div>
      )}
    </div>
  )
}
