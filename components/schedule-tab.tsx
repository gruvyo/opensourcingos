'use client'

import { useState, useEffect, useCallback, useMemo } from 'react'
import { createClient } from '@/lib/supabase/client'
import { replaceSavingsScheduleAtomically } from '@/lib/atomic-money-writers'
import type { Tables } from '@/lib/database.types'
import { CalendarRange, AlertCircle, Pencil, RotateCcw, Check, X, BadgeCheck } from 'lucide-react'
import { formatCurrency, formatReduction as money } from '@/lib/utils'
import { roundMoney } from '@/lib/money'
import {
  chainSavings, baselineQuality,
  termRates, generateSchedule, scheduleTotals, scheduleByYear,
  toSchedulePeriods, defaultPeriodCount, periodMonths, monthName, addMonths,
  reportableSavingsPct,
  PERIOD_TYPES, type PeriodType, type ScheduleRates, type SchedulePeriod,
} from '@/lib/savings'
import { clsx } from 'clsx'
import { Card } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { ConfirmDialog } from '@/components/ui/confirm-dialog'
import { Input, Select } from '@/components/ui/input'
import { validateFinalAnchor } from '@/lib/final-anchor'
import { resolveLoadedRows } from '@/lib/load-state'
import { localDateKey } from '@/lib/date-key'

const MONTHS = Array.from({ length: 12 }, (_, i) => ({ value: i + 1, label: monthName(i + 1) }))

type ScheduleBaseline = Pick<Tables<'baselines'>,
  | 'id'
  | 'baseline_total_amount'
  | 'baseline_term_months'
  | 'baseline_type'
  | 'baseline_source'
  | 'is_selected'
  | 'hard_reduction_override'
  | 'hard_reduction_override_reason'
>

type ScheduleOffer = Pick<Tables<'supplier_offers'>,
  'id' | 'offer_total_amount' | 'offer_term_months' | 'offer_role'
>

type ScheduleCalculation = Tables<'savings_calculations'>
type SavedScheduleRow = Tables<'savings_periods'>

/** Money as typed: '' means the anchor is not captured, never zero. */
const toAnchor = (v: string): number | null => (v.trim() === '' ? null : roundMoney(Number(v)))

/**
 * The savings schedule. The chain gives one number for the whole deal; nobody
 * is ever asked for that number. They are asked for THIS YEAR'S savings, so the
 * deal is spread over periods and grouped by calendar year.
 *
 * Rows are generated from the three selected anchors and then editable — but
 * only the anchors are editable. The Reduction / Avoidance / Total split is
 * always derived, so no row can carry a savings figure that does not follow
 * from the chain.
 */
export function ScheduleTab({
  eventId,
  statusRequiresSavingsDisposition,
  currentUserRole,
}: {
  eventId: string
  statusRequiresSavingsDisposition: boolean
  currentUserRole: string | null
}) {
  const supabase = createClient()
  const [loading, setLoading] = useState(true)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [showRegenerateConfirm, setShowRegenerateConfirm] = useState(false)
  const [showExecuteConfirm, setShowExecuteConfirm] = useState(false)
  const [showReverseConfirm, setShowReverseConfirm] = useState(false)
  const [correctionMode, setCorrectionMode] = useState(false)
  const [correctionNote, setCorrectionNote] = useState('')
  const [reversalMode, setReversalMode] = useState(false)
  const [reversalNote, setReversalNote] = useState('')
  const [rowsBeforeCorrection, setRowsBeforeCorrection] = useState<SavedScheduleRow[]>([])

  const [baseline, setBaseline] = useState<ScheduleBaseline | null>(null)
  const [opening, setOpening] = useState<ScheduleOffer | null>(null)
  const [final, setFinal] = useState<ScheduleOffer | null>(null)
  const [calc, setCalc] = useState<ScheduleCalculation | null>(null)
  const [rows, setRows] = useState<SavedScheduleRow[]>([])

  // Schedule settings (the header). Seeded from the saved schedule, else from
  // the savings start date, else from today.
  const [startMonth, setStartMonth] = useState(new Date().getMonth() + 1)
  const [startYear, setStartYear] = useState(new Date().getFullYear())
  const [periodType, setPeriodType] = useState<PeriodType>('monthly')
  const [periodCount, setPeriodCount] = useState(12)

  const [editingId, setEditingId] = useState<string | null>(null)
  const [draft, setDraft] = useState({ baseline: '', opening: '', final: '' })
  const [finalError, setFinalError] = useState<string | null>(null)
  const [pendingZeroFinalRow, setPendingZeroFinalRow] = useState<SavedScheduleRow | null>(null)

  const load = useCallback(async () => {
    const [bases, offers, calcs] = await Promise.all([
      supabase.from('baselines')
        .select('id, baseline_total_amount, baseline_term_months, baseline_type, baseline_source, is_selected, hard_reduction_override, hard_reduction_override_reason')
        .eq('event_id', eventId),
      supabase.from('supplier_offers')
        .select('id, offer_total_amount, offer_term_months, offer_role')
        .eq('event_id', eventId),
      supabase.from('savings_calculations').select('*').eq('event_id', eventId)
        .order('created_at', { ascending: true }),
    ])

    const firstError = bases.error || offers.error || calcs.error
    if (firstError) { setError(firstError.message); setLoading(false); return }

    const b = (bases.data || []).find(x => x.is_selected) ?? null
    const o = (offers.data || []).find(x => x.offer_role === 'opening') ?? null
    const f = (offers.data || []).find(x => x.offer_role === 'final') ?? null
    const c = (calcs.data || [])[0] ?? null
    setBaseline(b); setOpening(o); setFinal(f); setCalc(c)

    if (c) {
      const dealMonths = Number(f?.offer_term_months) || Number(b?.baseline_term_months) || 12
      const type = (c.schedule_period_type as PeriodType) || 'monthly'
      setPeriodType(type)
      setPeriodCount(Number(c.schedule_period_count) || defaultPeriodCount(type, dealMonths))

      const fallback = c.savings_start_date ? new Date(c.savings_start_date + 'T00:00:00') : null
      setStartMonth(Number(c.schedule_start_month) || (fallback ? fallback.getMonth() + 1 : new Date().getMonth() + 1))
      setStartYear(Number(c.schedule_start_year) || (fallback ? fallback.getFullYear() : new Date().getFullYear()))

      const periods = await supabase.from('savings_periods').select('*')
        .eq('savings_calculation_id', c.id).order('period_number', { ascending: true })
      if (periods.error) { setError(periods.error.message); setLoading(false); return }
      setRows(periods.data || [])
    } else {
      setRows([])
    }
    setLoading(false)
  }, [eventId, supabase])

  useEffect(() => {
    let cancelled = false

    const loadInitialData = async () => {
      const [bases, offers, calcs] = await Promise.all([
        supabase.from('baselines')
          .select('id, baseline_total_amount, baseline_term_months, baseline_type, baseline_source, is_selected, hard_reduction_override, hard_reduction_override_reason')
          .eq('event_id', eventId),
        supabase.from('supplier_offers')
          .select('id, offer_total_amount, offer_term_months, offer_role')
          .eq('event_id', eventId),
        supabase.from('savings_calculations').select('*').eq('event_id', eventId)
          .order('created_at', { ascending: true }),
      ])

      if (cancelled) return

      const firstError = bases.error || offers.error || calcs.error
      if (firstError) { setError(firstError.message); setLoading(false); return }

      const b = (bases.data || []).find(x => x.is_selected) ?? null
      const o = (offers.data || []).find(x => x.offer_role === 'opening') ?? null
      const f = (offers.data || []).find(x => x.offer_role === 'final') ?? null
      const c = (calcs.data || [])[0] ?? null
      setBaseline(b); setOpening(o); setFinal(f); setCalc(c)

      if (c) {
        const dealMonths = Number(f?.offer_term_months) || Number(b?.baseline_term_months) || 12
        const type = (c.schedule_period_type as PeriodType) || 'monthly'
        const fallback = c.savings_start_date ? new Date(c.savings_start_date + 'T00:00:00') : null
        const periods = await supabase.from('savings_periods').select('*')
          .eq('savings_calculation_id', c.id).order('period_number', { ascending: true })

        if (cancelled) return
        if (periods.error) { setError(periods.error.message); setLoading(false); return }

        setPeriodType(type)
        setPeriodCount(Number(c.schedule_period_count) || defaultPeriodCount(type, dealMonths))
        setStartMonth(Number(c.schedule_start_month) || (fallback ? fallback.getMonth() + 1 : new Date().getMonth() + 1))
        setStartYear(Number(c.schedule_start_year) || (fallback ? fallback.getFullYear() : new Date().getFullYear()))
        setRows(periods.data || [])
      } else {
        setRows([])
      }
      setLoading(false)
    }

    void loadInitialData()
    return () => { cancelled = true }
  }, [eventId, supabase])

  // The deal term is the Final offer's term — that is what was signed.
  const dealMonths = Number(final?.offer_term_months) || Number(baseline?.baseline_term_months) || 12

  /** Whether this baseline may drive a hard Cost Reduction at all. */
  const quality = useMemo(() => baselineQuality(baseline?.baseline_type, {
    enabled: baseline?.hard_reduction_override,
    reason: baseline?.hard_reduction_override_reason,
  }), [baseline])

  // An anchor with an amount but NO TERM is not captured, not zero. termRates()
  // reports that with known:false; ignoring it published a baseline of $0 and a
  // Cost Reduction of minus the whole deal, with Total still correct so nothing
  // flagged it.
  const rates: ScheduleRates = useMemo(() => {
    const rate = (amount: unknown, months: unknown) => {
      const r = termRates(amount, months)
      return r.known ? r.perMonth : null
    }
    const b = baseline ? rate(baseline.baseline_total_amount, baseline.baseline_term_months) : null
    const o = opening ? rate(opening.offer_total_amount, opening.offer_term_months) : null

    // A SOFT baseline is a reference figure, not spend, so no period may book
    // a hard reduction against it. Drop it out of the baseline slot -- and put
    // it in the opening slot when nothing is there, or the deal's whole value
    // would vanish from the schedule rather than moving to the avoidance line.
    return {
      baselinePerMonth: quality.isHard ? b : null,
      openingPerMonth: quality.isHard ? o : (o ?? b),
      finalPerMonth: final ? (rate(final.offer_total_amount, final.offer_term_months) ?? 0) : 0,
    }
  }, [baseline, opening, final, quality])

  /** The deal term is unknown without the Final offer's term; nothing derives. */
  const dealTermKnown = !!final && termRates(final.offer_total_amount, final.offer_term_months).known

  /** What Generate would produce with the settings as they currently stand. */
  const preview = useMemo(
    () => generateSchedule({ startMonth, startYear, periodType, periodCount, dealMonths }, rates),
    [startMonth, startYear, periodType, periodCount, dealMonths, rates],
  )
  const previewTotals = scheduleTotals(preview)

  // The whole deal, straight off the anchors. Every schedule must add back to
  // this — it is the same chain, just not sliced up.
  // rates already reflect the baseline's quality, so the plain chain is right
  // here -- running chainWithBaselineQuality again would demote it twice.
  const dealAnchors = {
    baseline: rates.baselinePerMonth === null ? null : roundMoney(rates.baselinePerMonth * dealMonths),
    opening: rates.openingPerMonth === null ? null : roundMoney(rates.openingPerMonth * dealMonths),
    final: roundMoney(rates.finalPerMonth * dealMonths),
  }
  const rawDealChain = chainSavings(dealAnchors)
  const dealChain = {
    reduction: rawDealChain.reduction === null ? null : roundMoney(rawDealChain.reduction),
    avoidance: roundMoney(rawDealChain.avoidance),
    total: roundMoney(rawDealChain.total),
  }

  const saved = useMemo(() => toSchedulePeriods(rows), [rows])
  const savedTotals = scheduleTotals(saved)
  const executedTotal = rows.reduce((sum, row) => sum + Number(row.executed_total_savings_amount ?? 0), 0)
  const isExecuted = calc?.calculation_status === 'executed'
  const canEdit = currentUserRole === 'admin' || currentUserRole === 'procurement_user'
  const canCorrect = canEdit
  const canReverse = currentUserRole === 'admin'
  const savedByYear = useMemo(() => scheduleByYear(saved), [saved])
  const editedCount = rows.filter(r => r.is_edited).length
  const drift = saved.length ? savedTotals.total - dealChain.total : 0

  const stepMonths = periodMonths(periodType, dealMonths)
  const settingsChanged = !!calc && (
    Number(calc.schedule_start_month) !== startMonth ||
    Number(calc.schedule_start_year) !== startYear ||
    calc.schedule_period_type !== periodType ||
    Number(calc.schedule_period_count) !== periodCount
  )

  /** Switching period type invalidates the count — reset it to the term's own. */
  const changeType = (t: PeriodType) => {
    setPeriodType(t)
    setPeriodCount(defaultPeriodCount(t, dealMonths))
  }

  // -------------------------------------------------------------------
  // Generate: replace the schedule wholesale, then publish its totals.
  // -------------------------------------------------------------------
  const generate = async () => {
    if (!calc) return
    if (isExecuted) { setError('Executed schedules are preserved and cannot be regenerated.'); return }

    setBusy(true); setError(null)
    const payload = preview.map(p => ({
      period_number: p.periodNumber,
      period_month: p.month,
      period_year: p.year,
      period_months: p.months,
      baseline_amount: p.baseline,
      opening_amount: p.opening,
      final_amount: p.final,
      cost_reduction_amount: p.reduction,
      cost_avoidance_amount: p.avoidance,
      total_savings_amount: p.total,
      is_edited: false,
    }))
    const { error: replaceError } = await replaceSavingsScheduleAtomically(
      supabase, calc.id, startMonth, startYear, periodType, payload,
    )
    if (replaceError) { setError(replaceError.message); setBusy(false); return }

    setBusy(false)
    load()
  }

  // -------------------------------------------------------------------
  // Per-row editing. Only the three anchors; the split is always derived.
  // -------------------------------------------------------------------
  const startEdit = (r: SavedScheduleRow) => {
    if (isExecuted && !correctionMode) return
    setFinalError(null)
    setEditingId(r.id)
    setDraft({
      baseline: r.baseline_amount === null || r.baseline_amount === undefined ? '' : String(r.baseline_amount),
      opening: r.opening_amount === null || r.opening_amount === undefined ? '' : String(r.opening_amount),
      final: r.final_amount === null || r.final_amount === undefined ? '' : String(r.final_amount),
    })
  }

  const draftFinal = validateFinalAnchor(draft.final, { zeroConfirmed: true })
  const draftChain = chainSavings({
    baseline: toAnchor(draft.baseline),
    opening: toAnchor(draft.opening),
    final: draftFinal.status === 'valid' ? draftFinal.value : null,
  })

  const saveRow = async (r: SavedScheduleRow, zeroConfirmed = false) => {
    const finalValidation = validateFinalAnchor(draft.final, { zeroConfirmed })
    if (finalValidation.status === 'error') {
      setFinalError(finalValidation.message)
      return
    }
    if (finalValidation.status === 'confirm-zero') {
      setFinalError(null)
      setPendingZeroFinalRow(r)
      return
    }
    const finalAmount = finalValidation.value
    setFinalError(null)

    if (correctionMode) {
      setRows(current => current.map(row => row.id === r.id ? {
        ...row,
        baseline_amount: toAnchor(draft.baseline),
        opening_amount: toAnchor(draft.opening),
        final_amount: finalAmount,
        cost_reduction_amount: draftChain.reduction === null ? null : roundMoney(draftChain.reduction),
        cost_avoidance_amount: roundMoney(draftChain.avoidance),
        total_savings_amount: roundMoney(draftChain.total),
        is_edited: true,
      } : row))
      setEditingId(null)
      return
    }

    setBusy(true); setError(null)
    const res = await supabase.from('savings_periods').update({
      baseline_amount: toAnchor(draft.baseline),
      opening_amount: toAnchor(draft.opening),
      final_amount: finalAmount,
      cost_reduction_amount: draftChain.reduction === null ? null : roundMoney(draftChain.reduction),
      cost_avoidance_amount: roundMoney(draftChain.avoidance),
      total_savings_amount: roundMoney(draftChain.total),
      is_edited: true,
    }).eq('id', r.id)
    setBusy(false)
    if (res.error) { setError(res.error.message); return }
    setEditingId(null)
    await load()
    await republish()
  }

  /** Put one hand-edited row back to what the generator says it should be. */
  const resetRow = async (r: SavedScheduleRow) => {
    const g = preview[Number(r.period_number) - 1]
    if (!g) { setError('That period is outside the current schedule settings — regenerate instead.'); return }
    if (correctionMode) {
      setRows(current => current.map(row => row.id === r.id ? {
        ...row,
        baseline_amount: g.baseline,
        opening_amount: g.opening,
        final_amount: g.final,
        cost_reduction_amount: g.reduction,
        cost_avoidance_amount: g.avoidance,
        total_savings_amount: g.total,
        is_edited: false,
      } : row))
      return
    }

    setBusy(true); setError(null)
    const res = await supabase.from('savings_periods').update({
      baseline_amount: g.baseline, opening_amount: g.opening, final_amount: g.final,
      cost_reduction_amount: g.reduction, cost_avoidance_amount: g.avoidance,
      total_savings_amount: g.total, is_edited: false,
    }).eq('id', r.id)
    setBusy(false)
    if (res.error) { setError(res.error.message); return }
    await load()
    await republish()
  }

  /** After a row edit the published figure is stale — rewrite it from the rows. */
  const republish = async () => {
    if (!calc) return
    const result = await supabase.from('savings_periods').select('*')
      .eq('savings_calculation_id', calc.id).order('period_number', { ascending: true })
    const resolved = resolveLoadedRows<SavedScheduleRow>('The saved schedule', {
      data: result.data,
      error: result.error,
    })
    if (resolved.status === 'error') {
      setError(`${resolved.message} The edited row was saved, but published totals were not rewritten; try the save again before relying on dashboard figures.`)
      return
    }
    const current = toSchedulePeriods(resolved.rows)
    if (!current.length) {
      setError('The edited row was saved, but the schedule reload returned no periods, so published totals were not rewritten. Reload the page before continuing.')
      return
    }
    const res = await supabase.from('savings_calculations')
      .update(publishable(current, startMonth, startYear, dealMonths)).eq('id', calc.id)
    if (res.error) setError(res.error.message)
  }

  const executeSchedule = async () => {
    if (!calc) return
    setBusy(true); setError(null)
    const { error: executeError } = await supabase.rpc('mark_savings_schedule_executed', {
      p_savings_calculation_id: calc.id,
      p_execution_note: 'Confirmed from the project Savings Schedule.',
    })
    setBusy(false)
    if (executeError) { setError(executeError.message); return }
    await load()
  }

  const startCorrection = () => {
    setRowsBeforeCorrection(rows.map(row => ({ ...row })))
    setCorrectionNote('')
    setReversalMode(false)
    setCorrectionMode(true)
    setError(null)
  }

  const cancelCorrection = () => {
    setRows(rowsBeforeCorrection)
    setRowsBeforeCorrection([])
    setCorrectionNote('')
    setEditingId(null)
    setCorrectionMode(false)
  }

  const submitCorrection = async () => {
    if (!calc || correctionNote.trim() === '') {
      setError('Explain why the executed record is being corrected.')
      return
    }

    const correctedSchedule = toSchedulePeriods(rows)
    const correctedHeader = {
      ...publishable(correctedSchedule, startMonth, startYear, dealMonths),
      schedule_start_month: startMonth,
      schedule_start_year: startYear,
      schedule_period_type: periodType,
      schedule_period_count: rows.length,
    }
    const correctedPeriods = rows.map(row => ({
      id: row.id,
      period_number: row.period_number,
      period_month: row.period_month,
      period_year: row.period_year,
      period_months: row.period_months,
      baseline_amount: row.baseline_amount,
      opening_amount: row.opening_amount,
      final_amount: row.final_amount,
      cost_reduction_amount: row.cost_reduction_amount,
      cost_avoidance_amount: row.cost_avoidance_amount,
      total_savings_amount: row.total_savings_amount,
      is_edited: row.is_edited,
      notes: row.notes,
    }))

    setBusy(true)
    setError(null)
    const { error: correctionError } = await supabase.rpc('correct_savings_execution', {
      p_calc_id: calc.id,
      p_note: correctionNote.trim(),
      p_calculation: correctedHeader,
      p_periods: correctedPeriods,
    })
    setBusy(false)
    if (correctionError) {
      setError(correctionError.message)
      return
    }

    setCorrectionMode(false)
    setCorrectionNote('')
    setRowsBeforeCorrection([])
    await load()
  }

  const reverseExecution = async () => {
    if (!calc || reversalNote.trim() === '') {
      setError('Explain why the execution is being reversed.')
      return
    }

    setBusy(true)
    setError(null)
    const { error: reversalError } = await supabase.rpc('reverse_savings_execution', {
      p_calc_id: calc.id,
      p_note: reversalNote.trim(),
      p_disposition_action: statusRequiresSavingsDisposition ? 'no_executed_savings' : 'clear',
    })
    setBusy(false)
    if (reversalError) {
      setError(reversalError.message)
      return
    }

    setReversalMode(false)
    setReversalNote('')
    await load()
  }

  if (loading) {
    return <div className="p-8 text-center text-sm text-[var(--text-3)]">Loading schedule...</div>
  }

  return (
    <div>
      <div className="mb-4">
        <h2 className="text-lg font-semibold text-[var(--text)]">Savings Schedule</h2>
        <p className="text-sm text-[var(--text-2)]">
          When the savings land. The deal&apos;s anchors, spread over periods and grouped by year.
        </p>
      </div>

      <div className="mb-4 rounded-lg border border-blue-200 bg-blue-50 p-4 dark:border-blue-800 dark:bg-blue-900/20">
        <div className="flex items-start gap-3">
          <CalendarRange className="mt-0.5 h-5 w-5 shrink-0 text-blue-600 dark:text-blue-400" />
          <div className="text-xs text-blue-700 dark:text-blue-300">
            <p className="text-sm font-semibold text-blue-900 dark:text-blue-100">How the schedule works</p>
            <p className="mt-1">
              Each period runs the same chain on the same three anchors, scaled to the months that
              period covers. <strong>Monthly</strong>, <strong>Annual</strong> and{' '}
              <strong>One-Time</strong> therefore book the same total — they only differ in how the
              money is spread.
            </p>
            <p className="mt-1">
              Rows are generated, then editable. Only the three anchors can be edited; Reduction,
              Avoidance and Total are always derived.
            </p>
          </div>
        </div>
      </div>

      {error && (
        <div role="alert" className="mb-4 rounded bg-red-50 p-3 text-sm text-red-700 dark:bg-red-900/30 dark:text-red-300">{error}</div>
      )}

      {!calc ? (
        <Card className="p-8 text-center">
          <AlertCircle className="mx-auto mb-3 h-8 w-8 text-[var(--text-3)]" />
          <p className="text-sm font-medium text-[var(--text)]">Save the savings record first</p>
          <p className="mt-1 text-sm text-[var(--text-3)]">
            The schedule spreads the figure from the Calculations tab. Select your anchors there and
            click <strong>Save savings record</strong>, then come back.
          </p>
        </Card>
      ) : !final ? (
        <Card className="p-8 text-center">
          <AlertCircle className="mx-auto mb-3 h-8 w-8 text-[var(--text-3)]" />
          <p className="text-sm font-medium text-[var(--text)]">No Final offer selected</p>
          <p className="mt-1 text-sm text-[var(--text-3)]">
            The deal term comes from the Final offer, and the schedule cannot be built without it.
          </p>
        </Card>
      ) : !dealTermKnown ? (
        <Card className="p-8 text-center">
          <AlertCircle className="mx-auto mb-3 h-8 w-8 text-amber-500" />
          <p className="text-sm font-medium text-[var(--text)]">The Final offer has no term</p>
          <p className="mt-1 text-sm text-[var(--text-3)]">
            Without a term in months there is no deal term, so no period can be sized. Set it on the
            Supplier Offers tab. Building a schedule on an assumed 12 months would publish a figure
            nobody could defend.
          </p>
        </Card>
      ) : (
        <>
          <Card className="mb-4 p-4">
            <div className="flex flex-wrap items-center justify-between gap-4">
              <div className="flex items-start gap-3">
                <BadgeCheck className={clsx('mt-0.5 h-5 w-5', isExecuted ? 'text-green-600' : 'text-[var(--text-3)]')} aria-hidden="true" />
                <div>
                  <p className="text-sm font-semibold text-[var(--text)]">
                    {isExecuted ? 'Executed savings schedule' : 'Estimated savings schedule'}
                  </p>
                  <p className="mt-1 text-xs text-[var(--text-2)]">
                    {isExecuted
                      ? `${formatCurrency(executedTotal)} is preserved as the confirmed result; the original estimate remains available for comparison.`
                      : 'Execution copies every estimated period into a durable snapshot and records who confirmed it.'}
                  </p>
                </div>
              </div>
              <div className="flex flex-wrap gap-2">
                {canEdit && !isExecuted && saved.length > 0 && (
                  <Button onClick={() => setShowExecuteConfirm(true)} disabled={busy}>
                    Mark schedule executed
                  </Button>
                )}
                {isExecuted && canCorrect && !correctionMode && !reversalMode && (
                  <Button variant="secondary" onClick={startCorrection} disabled={busy}>
                    Correct executed record
                  </Button>
                )}
                {isExecuted && canReverse && !correctionMode && !reversalMode && (
                  <Button variant="secondary" onClick={() => { setReversalMode(true); setError(null) }} disabled={busy}>
                    Reverse accidental execution
                  </Button>
                )}
              </div>
            </div>
          </Card>

          {correctionMode && (
            <Card className="mb-4 border-amber-300 p-4 dark:border-amber-700">
              <h3 className="text-sm font-semibold text-[var(--text)]">Correct the executed record</h3>
              <p className="mt-1 text-xs text-[var(--text-2)]">
                Edit the affected period values below, then explain the correction. The database
                keeps the prior figures in the audit history and re-bases any realization comparison.
              </p>
              <label className="mt-3 block text-xs font-medium text-[var(--text-2)]">
                Correction explanation *
                <textarea
                  value={correctionNote}
                  onChange={event => setCorrectionNote(event.target.value)}
                  rows={3}
                  maxLength={2000}
                  className="mt-1 w-full resize-y rounded-md border border-[var(--border-strong)] bg-[var(--surface)] px-3 py-2 text-sm text-[var(--text)] focus:border-[var(--brand)] focus:outline-none focus:ring-2 focus:ring-[var(--brand)]/30"
                  placeholder="Explain what was wrong and why these corrected figures are defensible."
                />
              </label>
              <div className="mt-3 flex justify-end gap-2">
                <Button variant="secondary" onClick={cancelCorrection} disabled={busy}>Cancel correction</Button>
                <Button onClick={submitCorrection} disabled={busy || correctionNote.trim() === '' || editingId !== null}>
                  {busy ? 'Saving correction...' : 'Save audited correction'}
                </Button>
              </div>
            </Card>
          )}

          {reversalMode && (
            <Card className="mb-4 border-red-300 p-4 dark:border-red-800">
              <h3 className="text-sm font-semibold text-[var(--text)]">Reverse an accidental execution</h3>
              <p className="mt-1 text-xs text-[var(--text-2)]">
                Use this only when the schedule was marked executed too early. If actual or
                Finance-validated realization evidence exists, the database will refuse the reversal
                and require a correction instead.
              </p>
              <label className="mt-3 block text-xs font-medium text-[var(--text-2)]">
                Reversal explanation *
                <textarea
                  value={reversalNote}
                  onChange={event => setReversalNote(event.target.value)}
                  rows={3}
                  maxLength={2000}
                  className="mt-1 w-full resize-y rounded-md border border-[var(--border-strong)] bg-[var(--surface)] px-3 py-2 text-sm text-[var(--text)] focus:border-[var(--brand)] focus:outline-none focus:ring-2 focus:ring-[var(--brand)]/30"
                  placeholder="Explain why the execution was premature."
                />
              </label>
              {statusRequiresSavingsDisposition && (
                <p className="mt-2 text-xs text-amber-700 dark:text-amber-300">
                  This completed project will be recorded as “no executed savings.” The explanation
                  must contain at least 10 characters.
                </p>
              )}
              <div className="mt-3 flex justify-end gap-2">
                <Button variant="secondary" onClick={() => { setReversalMode(false); setReversalNote('') }} disabled={busy}>
                  Cancel reversal
                </Button>
                <Button
                  variant="danger"
                  onClick={() => setShowReverseConfirm(true)}
                  disabled={busy || reversalNote.trim() === '' || (statusRequiresSavingsDisposition && reversalNote.trim().length < 10)}
                >
                  Review reversal
                </Button>
              </div>
            </Card>
          )}

          {/* ---- Settings ------------------------------------------------ */}
          <Card className="mb-4 p-4">
            <h3 className="mb-3 text-sm font-semibold text-[var(--text)]">Schedule settings</h3>
            <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4">
              <div>
                <label className="block text-xs font-medium text-[var(--text-2)]">Start month</label>
                <Select aria-label="Start month" value={startMonth} onChange={e => setStartMonth(Number(e.target.value))} disabled={isExecuted || !canEdit} className="mt-1">
                  {MONTHS.map(m => <option key={m.value} value={m.value}>{m.label}</option>)}
                </Select>
              </div>
              <div>
                <label className="block text-xs font-medium text-[var(--text-2)]">Start year</label>
                <Input aria-label="Start year" type="number" min={2000} max={2100} value={startYear} disabled={isExecuted || !canEdit}
                  onChange={e => setStartYear(Number(e.target.value))} className="mt-1" />
              </div>
              <div>
                <label className="block text-xs font-medium text-[var(--text-2)]">Period type</label>
                <Select aria-label="Period type" value={periodType} onChange={e => changeType(e.target.value as PeriodType)} disabled={isExecuted || !canEdit} className="mt-1">
                  {PERIOD_TYPES.map(p => <option key={p.value} value={p.value}>{p.label}</option>)}
                </Select>
                <p className="mt-1 text-[11px] text-[var(--text-3)]">
                  {stepMonths === 1
                    ? 'One month per period.'
                    : stepMonths > dealMonths
                      // Consulting work rarely runs a whole year. Say plainly that
                      // the period is capped, so nobody reads "Annual" as a claim
                      // that a 4-month project saves for twelve.
                      ? `${stepMonths} months per period, but this deal runs ${dealMonths} — the period books ${dealMonths}.`
                      : `${stepMonths} months per period.`}
                </p>
              </div>
              <div>
                <label className="block text-xs font-medium text-[var(--text-2)]">Period count</label>
                <Input aria-label="Period count" type="number" min={1} max={600} value={periodCount} disabled={isExecuted || !canEdit}
                  onChange={e => setPeriodCount(Number(e.target.value))} className="mt-1" />
                <p className="mt-1 text-[11px] text-[var(--text-3)]">
                  {defaultPeriodCount(periodType, dealMonths)} covers the {dealMonths}-month deal.
                </p>
              </div>
            </div>

            <div className="mt-4 flex flex-wrap items-center justify-between gap-3 border-t border-[var(--border)] pt-3">
              <div className="text-xs text-[var(--text-2)]">
                <p>
                  {preview.length} period{preview.length === 1 ? '' : 's'} from{' '}
                  <strong>{monthName(startMonth)} {startYear}</strong> to{' '}
                  <strong>{lastPeriodLabel(preview)}</strong>, booking{' '}
                  <strong>{formatCurrency(previewTotals.total)}</strong> across{' '}
                  {previewTotals.months} of the {dealMonths} deal months.
                </p>
                {previewTotals.months < dealMonths && (
                  <p className="mt-1 text-amber-600 dark:text-amber-400">
                    This schedule stops {dealMonths - previewTotals.months} month
                    {dealMonths - previewTotals.months === 1 ? '' : 's'} short of the deal term, so it
                    books {formatCurrency(dealChain.total - previewTotals.total)} less than the deal is
                    worth.
                  </p>
                )}
                {preview.some(p => p.months === 0) && (
                  <p className="mt-1 text-amber-600 dark:text-amber-400">
                    {preview.filter(p => p.months === 0).length} period
                    {preview.filter(p => p.months === 0).length === 1 ? '' : 's'} fall past the end of
                    the deal term and book nothing.
                  </p>
                )}
              </div>
              <Button
                onClick={() => editedCount > 0 ? setShowRegenerateConfirm(true) : void generate()}
                disabled={busy || isExecuted || !canEdit}
              >
                {busy ? 'Working...' : saved.length ? 'Regenerate schedule' : 'Generate schedule'}
              </Button>
            </div>
            {saved.length > 0 && settingsChanged && (
              <p className="mt-2 text-right text-[11px] text-amber-600 dark:text-amber-400">
                Settings have changed since this schedule was generated.
              </p>
            )}
            <p className="mt-2 text-right text-[11px] text-[var(--text-3)]">
              Generating publishes these totals to the dashboard, savings and reports.
            </p>
          </Card>

          {saved.length === 0 ? (
            <Card className="p-8 text-center">
              <CalendarRange className="mx-auto mb-3 h-8 w-8 text-[var(--text-3)]" />
              <p className="text-sm font-medium text-[var(--text)]">No schedule yet</p>
              <p className="mt-1 text-sm text-[var(--text-3)]">
                Set the start and the period type above, then generate.
              </p>
            </Card>
          ) : (
            <>
              {/* ---- By year: the fiscal-year report ---------------------- */}
              <Card className="mb-4 p-4">
                <h3 className="mb-1 text-sm font-semibold text-[var(--text)]">By year</h3>
                <p className="mb-3 text-xs text-[var(--text-3)]">
                  Booked per month from the start month, so a period that crosses a year boundary
                  splits across both. The fiscal year is the calendar year, and this answer does not
                  change if you re-slice the schedule as Monthly, Annual or One-Time.
                </p>
                <div className="overflow-x-auto">
                  <table className="w-full min-w-[520px] text-sm">
                    <caption className="sr-only">Scheduled savings totals by year</caption>
                    <thead>
                      <tr className="border-b border-[var(--border)] text-left text-xs text-[var(--text-3)]">
                        <th scope="col" className="py-2 pr-3 font-medium">Year</th>
                        <th scope="col" className="py-2 pr-3 text-right font-medium">Months</th>
                        <th scope="col" className="py-2 pr-3 text-right font-medium">Cost Reduction</th>
                        <th scope="col" className="py-2 pr-3 text-right font-medium">Cost Avoidance</th>
                        <th scope="col" className="py-2 text-right font-medium">Total</th>
                      </tr>
                    </thead>
                    <tbody>
                      {savedByYear.map(y => (
                        <tr key={y.year} className="border-b border-[var(--border)] last:border-0">
                          <td className="py-2 pr-3 font-medium text-[var(--text)]">{y.year}</td>
                          <td className="py-2 pr-3 text-right tabular-nums text-[var(--text-2)]">{y.months}</td>
                          <td className="py-2 pr-3 text-right tabular-nums text-[var(--text-2)]">{money(y.reduction)}</td>
                          <td className="py-2 pr-3 text-right tabular-nums text-[var(--text-2)]">{formatCurrency(y.avoidance)}</td>
                          <td className="py-2 text-right font-semibold tabular-nums text-[var(--text)]">{formatCurrency(y.total)}</td>
                        </tr>
                      ))}
                    </tbody>
                    <tfoot>
                      <tr className="border-t-2 border-[var(--border-strong)] font-semibold">
                        <td className="py-2 pr-3 text-[var(--text)]">All years</td>
                        <td className="py-2 pr-3 text-right tabular-nums text-[var(--text-2)]">{savedTotals.months}</td>
                        <td className="py-2 pr-3 text-right tabular-nums text-[var(--text)]">
                          {money(savedTotals.reduction)}
                        </td>
                        <td className="py-2 pr-3 text-right tabular-nums text-[var(--text)]">{formatCurrency(savedTotals.avoidance)}</td>
                        <td className="py-2 text-right tabular-nums text-green-600 dark:text-green-400">{formatCurrency(savedTotals.total)}</td>
                      </tr>
                    </tfoot>
                  </table>
                </div>

                <p className={clsx('mt-3 text-xs',
                  Math.abs(drift) < 1 ? 'text-[var(--text-3)]' : 'text-amber-600 dark:text-amber-400')}>
                  {Math.abs(drift) < 1
                    ? `Reconciles with the deal: ${formatCurrency(dealChain.total)} over the ${dealMonths}-month term.`
                    : `This schedule books ${formatCurrency(Math.abs(drift))} ${drift > 0 ? 'more' : 'less'} than the ` +
                      `${formatCurrency(dealChain.total)} the anchors are worth over the ${dealMonths}-month term` +
                      (editedCount > 0 ? ', which hand-edited rows can legitimately cause.' : '.')}
                </p>
              </Card>

              {/* ---- The schedule ---------------------------------------- */}
              <Card className="p-4">
                <div className="mb-3 flex flex-wrap items-center justify-between gap-2">
                  <h3 className="text-sm font-semibold text-[var(--text)]">Periods</h3>
                  {editedCount > 0 && (
                    <span className="rounded-full bg-amber-100 px-2 py-0.5 text-[11px] font-medium text-amber-700 dark:bg-amber-500/15 dark:text-amber-300">
                      {editedCount} edited by hand
                    </span>
                  )}
                </div>
                <div className="overflow-x-auto">
                  <table className="w-full min-w-[980px] text-sm">
                    <caption className="sr-only">Savings schedule periods</caption>
                    <thead>
                      <tr className="border-b border-[var(--border)] text-left text-xs text-[var(--text-3)]">
                        <th scope="col" className="py-2 pr-3 font-medium">#</th>
                        <th scope="col" className="py-2 pr-3 font-medium">Period</th>
                        <th scope="col" className="py-2 pr-3 text-right font-medium">Baseline</th>
                        <th scope="col" className="py-2 pr-3 text-right font-medium">Opening</th>
                        <th scope="col" className="py-2 pr-3 text-right font-medium">Final</th>
                        <th scope="col" className="py-2 pr-3 text-right font-medium">Cost Reduction</th>
                        <th scope="col" className="py-2 pr-3 text-right font-medium">Cost Avoidance</th>
                        <th scope="col" className="py-2 pr-3 text-right font-medium">Estimated</th>
                        <th scope="col" className="py-2 pr-3 text-right font-medium">Executed</th>
                        <th scope="col" aria-label="Actions" className="py-2 w-20" />
                      </tr>
                    </thead>
                    <tbody>
                      {rows.map(r => {
                        const editing = editingId === r.id
                        const p = toSchedulePeriods([r])[0]
                        return (
                          <tr key={r.id} className={clsx(
                            'border-b border-[var(--border)] last:border-0',
                            r.is_edited && 'bg-amber-50/50 dark:bg-amber-500/5',
                            Number(r.period_months) === 0 && 'opacity-60',
                          )}>
                            <td className="py-2 pr-3 text-[var(--text-3)]">{r.period_number}</td>
                            <td className="py-2 pr-3 whitespace-nowrap text-[var(--text)]">
                              {monthName(r.period_month)} {r.period_year}
                              <span className="ml-1 text-[11px] text-[var(--text-3)]">
                                {Number(r.period_months) === 0
                                  ? '(past term)'
                                  : `(${Number(r.period_months)} mo)`}
                              </span>
                            </td>
                            {editing ? (
                              <>
                                <td className="py-1 pr-3">
                                  <Input aria-label={`Baseline for ${monthName(r.period_month)} ${r.period_year}`} type="number" step="0.01" value={draft.baseline} placeholder="none"
                                    onChange={e => setDraft(d => ({ ...d, baseline: e.target.value }))}
                                    className="px-2 py-1 text-right text-xs" />
                                </td>
                                <td className="py-1 pr-3">
                                  <Input aria-label={`Opening amount for ${monthName(r.period_month)} ${r.period_year}`} type="number" step="0.01" value={draft.opening} placeholder="none"
                                    onChange={e => setDraft(d => ({ ...d, opening: e.target.value }))}
                                    className="px-2 py-1 text-right text-xs" />
                                </td>
                                <td className="py-1 pr-3">
                                  <Input
                                    aria-label={`Final amount for ${monthName(r.period_month)} ${r.period_year}`}
                                    aria-invalid={Boolean(finalError)}
                                    aria-describedby={finalError ? `final-error-${r.id}` : undefined}
                                    type="number"
                                    min="0"
                                    step="0.01"
                                    value={draft.final}
                                    onChange={e => {
                                      setDraft(d => ({ ...d, final: e.target.value }))
                                      setFinalError(null)
                                    }}
                                    className="px-2 py-1 text-right text-xs" />
                                  {finalError && (
                                    <p id={`final-error-${r.id}`} role="alert" className="mt-1 max-w-48 text-left text-[11px] text-red-600 dark:text-red-400">
                                      {finalError}
                                    </p>
                                  )}
                                </td>
                                <td className="py-2 pr-3 text-right tabular-nums text-[var(--text-2)]">
                                  {draftFinal.status === 'valid' ? money(draftChain.reduction) : '—'}
                                </td>
                                <td className="py-2 pr-3 text-right tabular-nums text-[var(--text-2)]">{formatCurrency(draftChain.avoidance)}</td>
                                <td className="py-2 pr-3 text-right font-semibold tabular-nums text-[var(--text)]">
                                  {draftFinal.status === 'valid' ? formatCurrency(draftChain.total) : '—'}
                                </td>
                                <td className="py-2 pr-3 text-right tabular-nums text-[var(--text-3)]">—</td>
                                <td className="py-2">
                                  <div className="flex justify-end gap-1">
                                    <Button size="sm" variant="ghost" disabled={busy}
                                      onClick={() => saveRow(r)} title="Save this period" aria-label="Save this period">
                                      <Check className="h-3.5 w-3.5" />
                                    </Button>
                                    <Button size="sm" variant="ghost" onClick={() => { setEditingId(null); setFinalError(null) }}
                                      title="Cancel" aria-label="Cancel">
                                      <X className="h-3.5 w-3.5" />
                                    </Button>
                                  </div>
                                </td>
                              </>
                            ) : (
                              <>
                                <td className="py-2 pr-3 text-right tabular-nums text-[var(--text-2)]">{money(p.baseline)}</td>
                                <td className="py-2 pr-3 text-right tabular-nums text-[var(--text-2)]">{money(p.opening)}</td>
                                <td className="py-2 pr-3 text-right tabular-nums text-[var(--text-2)]">{formatCurrency(p.final)}</td>
                                <td className={clsx('py-2 pr-3 text-right tabular-nums',
                                  p.reduction !== null && p.reduction < 0 ? 'text-red-600 dark:text-red-400' : 'text-[var(--text-2)]')}>
                                  {money(p.reduction)}
                                </td>
                                <td className="py-2 pr-3 text-right tabular-nums text-[var(--text-2)]">{formatCurrency(p.avoidance)}</td>
                                <td className="py-2 pr-3 text-right font-semibold tabular-nums text-[var(--text)]">{formatCurrency(p.total)}</td>
                                <td className="py-2 pr-3 text-right font-semibold tabular-nums text-[var(--text)]">
                                  {r.executed_total_savings_amount === null ? '—' : formatCurrency(r.executed_total_savings_amount)}
                                </td>
                                <td className="py-2">
                                  <div className="flex justify-end gap-1">
                                    <Button size="sm" variant="ghost" onClick={() => startEdit(r)} disabled={!canEdit || (isExecuted && !correctionMode)}
                                      title="Edit this period" aria-label="Edit this period">
                                      <Pencil className="h-3.5 w-3.5" />
                                    </Button>
                                    {r.is_edited && (
                                      <Button size="sm" variant="ghost" disabled={busy || !canEdit || (isExecuted && !correctionMode)}
                                        onClick={() => resetRow(r)} title="Reset to the generated figures"
                                        aria-label="Reset to the generated figures">
                                        <RotateCcw className="h-3.5 w-3.5" />
                                      </Button>
                                    )}
                                  </div>
                                </td>
                              </>
                            )}
                          </tr>
                        )
                      })}
                    </tbody>
                    <tfoot>
                      <tr className="border-t-2 border-[var(--border-strong)] font-semibold">
                        <td className="py-2 pr-3" />
                        <td className="py-2 pr-3 text-[var(--text)]">Grand total</td>
                        <td className="py-2 pr-3 text-right tabular-nums text-[var(--text)]">{formatCurrency(savedTotals.baseline)}</td>
                        <td className="py-2 pr-3 text-right tabular-nums text-[var(--text)]">{formatCurrency(savedTotals.opening)}</td>
                        <td className="py-2 pr-3 text-right tabular-nums text-[var(--text)]">{formatCurrency(savedTotals.final)}</td>
                        <td className="py-2 pr-3 text-right tabular-nums text-[var(--text)]">
                          {money(savedTotals.reduction)}
                        </td>
                        <td className="py-2 pr-3 text-right tabular-nums text-[var(--text)]">{formatCurrency(savedTotals.avoidance)}</td>
                        <td className="py-2 pr-3 text-right tabular-nums text-green-600 dark:text-green-400">{formatCurrency(savedTotals.total)}</td>
                        <td className="py-2 pr-3 text-right tabular-nums text-[var(--text)]">{isExecuted ? formatCurrency(executedTotal) : '—'}</td>
                        <td className="py-2" />
                      </tr>
                    </tfoot>
                  </table>
                </div>
                <p className="mt-3 text-xs text-[var(--text-3)]">
                  A blank Baseline or Opening means the anchor was not captured for that period —
                  Cost Reduction then reads <strong>n/a</strong>, which is not the same as zero.
                  Negative reductions are real cost increases and are shown in parentheses.
                </p>
              </Card>
            </>
          )}
        </>
      )}
      {showRegenerateConfirm && (
        <ConfirmDialog
          title="Regenerate this schedule?"
          description={`${editedCount} row${editedCount === 1 ? ' has' : 's have'} been edited by hand. Regenerating discards those edits and replaces the saved schedule.`}
          confirmLabel="Regenerate Schedule"
          pendingLabel="Regenerating..."
          onConfirm={generate}
          onCancel={() => setShowRegenerateConfirm(false)}
        />
      )}
      {showExecuteConfirm && (
        <ConfirmDialog
          title="Mark this savings schedule executed?"
          description="This preserves the estimate and copies every period into the executed column. Executed schedules become read-only so the confirmed result cannot be silently rewritten."
          confirmLabel="Mark executed"
          pendingLabel="Marking executed..."
          onConfirm={executeSchedule}
          onCancel={() => setShowExecuteConfirm(false)}
        />
      )}
      {showReverseConfirm && (
        <ConfirmDialog
          title="Reverse this execution?"
          description="This removes the executed snapshot and returns the schedule to Estimated. The reason and the prior values remain in the audit history. A reversal is permanently refused once realization evidence exists."
          confirmLabel="Reverse execution"
          pendingLabel="Reversing execution..."
          onConfirm={reverseExecution}
          onCancel={() => setShowReverseConfirm(false)}
        />
      )}
      {pendingZeroFinalRow && (
        <ConfirmDialog
          title="Confirm a $0.00 Final amount?"
          description="A zero Final books the full baseline as savings for this period. Continue only if the signed Final amount is truly $0.00."
          confirmLabel="Confirm $0.00 Final"
          pendingLabel="Saving..."
          onConfirm={() => saveRow(pendingZeroFinalRow, true)}
          onCancel={() => setPendingZeroFinalRow(null)}
        />
      )}
    </div>
  )
}

// ---- helpers ----------------------------------------------------------

function lastPeriodLabel(rows: SchedulePeriod[]): string {
  const last = rows[rows.length - 1]
  return last ? `${monthName(last.month)} ${last.year}` : '—'
}

/**
 * The columns the dashboard, savings and reports read, taken from the schedule.
 * Once a schedule exists it IS the deal's published figure — one set of numbers,
 * so the yearly breakdown and the headline can never disagree.
 */
function publishable(rows: SchedulePeriod[], startMonth: number, startYear: number, dealMonths: number) {
  const t = scheduleTotals(rows)
  const end = addMonths(startMonth, startYear, Math.max(1, Math.round(t.months)))
  const endDate = new Date(end.year, end.month - 1, 1)
  endDate.setDate(endDate.getDate() - 1)   // inclusive of the final day
  // Denominator is BASELINE spend, never the opening ask; null without one.

  return {
    baseline_total_amount: t.baseline,
    opening_proposal_amount: t.opening,
    award_total_amount: t.final,
    gross_savings_amount: t.total,
    net_savings_amount: t.total,
    cost_reduction_amount: t.reduction,
    cost_avoidance_amount: t.avoidance,
    // Derived the same way the Calculations tab derives it, so republishing
    // cannot leave a stale label behind.
    savings_type: (t.reduction ?? 0) >= t.avoidance ? 'Cost Reduction' : 'Cost Avoidance',
    savings_percentage: reportableSavingsPct(t.total, t.baseline),
    savings_start_date: `${startYear}-${String(startMonth).padStart(2, '0')}-01`,
    savings_end_date: localDateKey(endDate),
    calculation_name: `${rows.length}-period savings schedule`,
    recognition_notes: `Published from the savings schedule: ${rows.length} periods covering ${Math.round(t.months)} of ${dealMonths} deal months.`,
  }
}
