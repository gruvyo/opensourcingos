'use client'

import { useState, useEffect, useCallback } from 'react'
import { createClient } from '@/lib/supabase/client'
import {
  TrendingUp, Plus, Trash2, AlertTriangle,
  ShieldCheck, Clock,
} from 'lucide-react'
import { useWorkspaceFormat } from '@/components/workspace-format-provider'
import { clsx } from 'clsx'
import { Card } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { ConfirmDialog } from '@/components/ui/confirm-dialog'
import { Input } from '@/components/ui/input'
import { syncRealizationPeriodsAtomically } from '@/lib/atomic-money-writers'
import { hasCentPrecision, moneyInputChanged } from '@/lib/money'
import type { Tables } from '@/lib/database.types'
import { reductionFromActualSpend } from '@/lib/realization'

type RealizationPeriod = Omit<
  Tables<'realization_periods'>,
  'baseline_amount' | 'projected_savings' | 'leakage_amount' | 'realization_status' | 'finance_validated'
> & {
  baseline_amount: number
  projected_savings: number
  leakage_amount: number
  realization_status: string
  finance_validated: boolean
  savings_calculation: Pick<Tables<'savings_calculations'>, 'calculation_name' | 'savings_type'> | null
}

type ExecutedScheduleRow = Pick<Tables<'savings_periods'>,
  'id' | 'savings_calculation_id' | 'period_month' | 'period_year' | 'period_months' |
  'executed_baseline_amount' | 'executed_cost_reduction_amount' |
  'executed_cost_avoidance_amount' | 'executed_total_savings_amount'
>

const REALIZATION_STATUS_COLORS: Record<string, string> = {
  'Pending': 'bg-gray-100 text-gray-700 dark:bg-gray-500/20 dark:text-gray-300',
  'In Progress': 'bg-blue-100 text-blue-700 dark:bg-blue-500/15 dark:text-blue-300',
  'Realized': 'bg-green-100 text-green-700 dark:bg-green-500/15 dark:text-green-300',
  'Partially Realized': 'bg-amber-100 text-amber-700 dark:bg-amber-500/15 dark:text-amber-300',
  'Not Realized': 'bg-red-100 text-red-700 dark:bg-red-500/15 dark:text-red-300',
  'Leaked': 'bg-red-100 text-red-700 dark:bg-red-500/15 dark:text-red-300',
}

export function RealizationTab({
  eventId,
  currentUserRole,
}: {
  eventId: string
  currentUserRole: string | null
}) {
  const { formatCurrency, formatDate } = useWorkspaceFormat()
  const [periods, setPeriods] = useState<RealizationPeriod[]>([])
  const [scheduleRows, setScheduleRows] = useState<ExecutedScheduleRow[]>([])
  const [loading, setLoading] = useState(true)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [periodToDelete, setPeriodToDelete] = useState<RealizationPeriod | null>(null)
  const supabase = createClient()
  const canEdit = currentUserRole === 'admin' || currentUserRole === 'procurement_user'
  const canDelete = currentUserRole === 'admin'

  const fetchPeriods = useCallback(async (failureMessage = 'Realization data could not be refreshed') => {
    const { data, error: loadError } = await supabase
      .from('realization_periods')
      .select(`
        *,
        savings_calculation:savings_calculations(calculation_name, savings_type)
      `)
      .eq('event_id', eventId)
      .order('period_start_date', { ascending: true })

    if (loadError) {
      setError(`${failureMessage}: ${loadError.message}`)
      setLoading(false)
      return false
    }

    setPeriods((data || []) as RealizationPeriod[])
    setLoading(false)
    return true
  }, [eventId, supabase])

  useEffect(() => {
    let cancelled = false

    const loadInitialData = async () => {
      const [periodResult, scheduleResult] = await Promise.all([
        supabase
          .from('realization_periods')
          .select(`
            *,
            savings_calculation:savings_calculations(calculation_name, savings_type)
          `)
          .eq('event_id', eventId)
          .order('period_start_date', { ascending: true }),
        supabase.from('savings_periods')
          .select('id, savings_calculation_id, period_month, period_year, period_months, executed_baseline_amount, executed_cost_reduction_amount, executed_cost_avoidance_amount, executed_total_savings_amount')
          .eq('event_id', eventId)
          .not('executed_total_savings_amount', 'is', null)
          .order('period_number'),
      ])

      if (cancelled) return

      const loadError = periodResult.error || scheduleResult.error
      if (loadError) {
        setError(`Realization data could not be loaded: ${loadError.message}`)
        setLoading(false)
        return
      }

      setPeriods((periodResult.data || []) as RealizationPeriod[])
      setScheduleRows(scheduleResult.data || [])
      setLoading(false)
    }

    void loadInitialData()

    return () => { cancelled = true }
  }, [eventId, supabase])

  const updateActualAmount = async (periodId: string, actualAmount: string) => {
    const period = periods.find(p => p.id === periodId)
    if (!period) return false
    const hasActual = actualAmount.trim() !== ''
    const actual = hasActual ? Number(actualAmount) : null

    if (actual !== null && (!Number.isFinite(actual) || actual < 0 || !hasCentPrecision(actual))) {
      setError('Actual spend must be a valid non-negative amount with no more than two decimal places.')
      return false
    }

    if (!hasActual) {
      setBusy(true); setError(null)
      const { error: clearError } = await supabase.from('realization_periods')
        .update({ actual_amount: null, realized_reduction_amount: null }).eq('id', periodId)
      if (clearError) { setError(`Actual spend could not be cleared: ${clearError.message}`); setBusy(false); return false }
      const refreshed = await fetchPeriods('Actual spend was cleared, but realization data could not be refreshed')
      setBusy(false)
      return refreshed
    }

    const realizedReduction = reductionFromActualSpend(
      period.baseline_amount,
      actual,
      period.projected_reduction_amount,
    )
    if (realizedReduction === null) {
      setError('Actual spend cannot derive reduction for this period because there is no executed reduction comparator. Enter the realized legs directly.')
      return false
    }

    setBusy(true)
    setError(null)
    const { data: updatedPeriod, error: updateError } = await supabase
      .from('realization_periods')
      .update({
        actual_amount: actual,
        realized_reduction_amount: realizedReduction,
      })
      .eq('id', periodId)
      .select('id')
      .maybeSingle()
    if (updateError || !updatedPeriod) {
      setError(`Actual spend could not be saved: ${updateError?.message || 'The realization period was not updated'}`)
      setBusy(false)
      return false
    }

    const refreshed = await fetchPeriods('Actual spend was saved, but realization data could not be refreshed')
    setBusy(false)
    return refreshed
  }

  const updateRealizedLeg = async (
    periodId: string,
    leg: 'reduction' | 'avoidance',
    realizedAmount: string,
  ) => {
    const period = periods.find(candidate => candidate.id === periodId)
    if (!period) return false
    const hasValue = realizedAmount.trim() !== ''
    const realized = hasValue ? Number(realizedAmount) : null
    if (realized !== null && (!Number.isFinite(realized) || !hasCentPrecision(realized))) {
      setError(`Realized ${leg} must be a valid amount with no more than two decimal places.`)
      return false
    }

    const update = leg === 'reduction'
      ? { realized_reduction_amount: realized, actual_amount: null }
      : { realized_avoidance_amount: realized }

    setBusy(true); setError(null)
    const { data: updatedPeriod, error: updateError } = await supabase
      .from('realization_periods')
      .update(update)
      .eq('id', periodId)
      .select('id')
      .maybeSingle()
    if (updateError || !updatedPeriod) {
      setError(`Realized ${leg} could not be saved: ${updateError?.message || 'The realization period was not updated'}`)
      setBusy(false)
      return false
    }
    const refreshed = await fetchPeriods(`Realized ${leg} was saved, but realization data could not be refreshed`)
    setBusy(false)
    return refreshed
  }

  const toggleFinanceValidated = async (period: RealizationPeriod) => {
    setBusy(true)
    setError(null)
    const { error: updateError } = await supabase.rpc('set_finance_validation', {
      p_realization_period_id: period.id,
      p_validated: !period.finance_validated,
    })
    if (updateError) {
      setError(`Finance validation could not be saved: ${updateError.message}`)
      setBusy(false)
      return
    }

    await fetchPeriods('Finance validation was saved, but realization data could not be refreshed')
    setBusy(false)
  }

  const handleDelete = async (periodId: string) => {
    setBusy(true)
    setError(null)
    const { data: deletedPeriod, error: deleteError } = await supabase
      .from('realization_periods')
      .delete()
      .eq('id', periodId)
      .select('id')
      .maybeSingle()
    if (deleteError || !deletedPeriod) {
      setError(`Realization period could not be deleted: ${deleteError?.message || 'The realization period was not deleted'}`)
      setBusy(false)
      return
    }

    setPeriods(current => current.filter(period => period.id !== periodId))
    setBusy(false)
  }

  const syncExecutedSchedule = async () => {
    setBusy(true)
    setError(null)
    const { error: syncError } = await syncRealizationPeriodsAtomically(supabase, eventId)
    if (syncError) {
      setError(`Savings Realization periods could not be created: ${syncError.message}`)
      setBusy(false)
      return
    }

    await fetchPeriods('Savings Realization periods were created, but the data could not be refreshed')
    setBusy(false)
  }

  if (loading) {
    return <div className="p-8 text-center text-sm text-[var(--text-3)]">Loading realization data...</div>
  }

  // Summary stats
  const totalProjected = periods.reduce((sum, p) => sum + (p.projected_savings || 0), 0)
  const totalRealized = periods.reduce((sum, p) => sum + (p.realized_savings || 0), 0)
  const totalLeakage = periods.reduce((sum, p) => sum + (p.leakage_amount || 0), 0)
  const totalProjectedReduction = periods.reduce((sum, p) => sum + (p.projected_reduction_amount || 0), 0)
  const totalProjectedAvoidance = periods.reduce((sum, p) => sum + (p.projected_avoidance_amount || 0), 0)
  const totalRealizedReduction = periods.reduce((sum, p) => sum + (p.realized_reduction_amount || 0), 0)
  const totalRealizedAvoidance = periods.reduce((sum, p) => sum + (p.realized_avoidance_amount || 0), 0)
  const realizationRate = totalProjected > 0 ? (totalRealized / totalProjected) * 100 : 0

  return (
    <div>
      {error && (
        <div role="alert" className="mb-4 rounded bg-red-50 p-3 text-sm text-red-700 dark:bg-red-900/30 dark:text-red-300">
          {error}
        </div>
      )}

      {/* Header */}
      <div className="mb-4 flex items-center justify-between">
        <div>
          <h2 className="text-lg font-semibold text-[var(--text)]">Savings Realization</h2>
          <p className="text-sm text-[var(--text-2)]">Compare executed savings with actual results on the same schedule</p>
        </div>
        {canEdit && (
          <Button disabled={busy || scheduleRows.length === 0 || periods.length === scheduleRows.length} onClick={syncExecutedSchedule} className="flex items-center gap-2">
            <Plus className="h-4 w-4" />
            Create tracking periods
          </Button>
        )}
      </div>

      {/* Summary Cards */}
      <div className="mb-4 grid grid-cols-2 gap-4 lg:grid-cols-4">
        <Card className="p-4">
          <p className="text-xs text-[var(--text-3)]">Executed Savings</p>
          <p className="mt-1 text-xl font-bold text-[var(--text)]">{formatCurrency(totalProjected)}</p>
          <p className="mt-1 text-[11px] text-[var(--text-3)]">{formatCurrency(totalProjectedReduction)} reduction + {formatCurrency(totalProjectedAvoidance)} avoidance</p>
        </Card>
        <Card className="p-4">
          <p className="text-xs text-[var(--text-3)]">Realized Savings</p>
          <p className="mt-1 text-xl font-bold text-green-600 dark:text-green-400">{formatCurrency(totalRealized)}</p>
          <p className="mt-1 text-[11px] text-[var(--text-3)]">{formatCurrency(totalRealizedReduction)} reduction + {formatCurrency(totalRealizedAvoidance)} avoidance</p>
        </Card>
        <Card className="p-4">
          <p className="text-xs text-[var(--text-3)]">Leakage</p>
          <p className="mt-1 text-xl font-bold text-red-600 dark:text-red-400">{formatCurrency(totalLeakage)}</p>
        </Card>
        <Card className="p-4">
          <p className="text-xs text-[var(--text-3)]">Realization Rate</p>
          <p className="mt-1 text-xl font-bold text-indigo-600 dark:text-indigo-400">{realizationRate.toFixed(1)}%</p>
        </Card>
      </div>

      {/* Periods Table */}
      {periods.length === 0 ? (
        <Card className="p-12 text-center">
          <TrendingUp className="mx-auto mb-3 h-10 w-10 text-[var(--text-3)]" />
          <h3 className="text-sm font-medium text-[var(--text)]">No Savings Realization periods yet</h3>
          <p className="mt-1 text-sm text-[var(--text-3)]">
            {scheduleRows.length > 0
              ? 'Create tracking periods from the executed savings schedule.'
              : 'Mark the savings schedule executed before tracking realized savings.'}
          </p>
        </Card>
      ) : (
        <Card className="overflow-hidden">
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <caption className="sr-only">Project savings realization periods</caption>
              <thead>
                <tr className="border-b border-[var(--border)] bg-[var(--surface-2)] text-left text-xs uppercase text-[var(--text-3)]">
                  <th scope="col" className="px-4 py-3">Period</th>
                  <th scope="col" className="px-4 py-3 text-right">Baseline</th>
                  <th scope="col" className="px-4 py-3 text-right">Executed Reduction</th>
                  <th scope="col" className="px-4 py-3 text-right">Executed Avoidance</th>
                  <th scope="col" className="px-4 py-3 text-right">Actual Spend</th>
                  <th scope="col" className="px-4 py-3 text-right">Realized Reduction</th>
                  <th scope="col" className="px-4 py-3 text-right">Realized Avoidance</th>
                  <th scope="col" className="px-4 py-3 text-right">Total Realized</th>
                  <th scope="col" className="px-4 py-3 text-right">Reduction Leakage</th>
                  <th scope="col" className="px-4 py-3 text-center">Status</th>
                  <th scope="col" className="px-4 py-3 text-center">Finance</th>
                  <th scope="col" aria-label="Actions" className="px-4 py-3"></th>
                </tr>
              </thead>
              <tbody className="divide-y divide-[var(--border)]">
                {periods.map((period) => (
                  <tr key={period.id} className="hover:bg-[var(--surface-2)]">
                    <td className="px-4 py-3">
                      <div className="text-sm font-medium text-[var(--text)]">{period.period_name}</div>
                      <div className="text-xs text-[var(--text-3)]">
                        {formatDate(period.period_start_date)} → {formatDate(period.period_end_date)}
                      </div>
                      {period.savings_calculation && (
                        <div className="text-xs text-[var(--text-3)]">{period.savings_calculation.calculation_name}</div>
                      )}
                      {period.comparison_rebased_at && (
                        <div className={clsx(
                          'mt-1 text-[11px]',
                          period.finance_validated
                            ? 'text-[var(--text-3)]'
                            : 'font-medium text-amber-700 dark:text-amber-300',
                        )}>
                          Re-based by an executed-savings correction on {formatDate(period.comparison_rebased_at)}
                          {!period.finance_validated && ' · Finance revalidation required'}
                        </div>
                      )}
                    </td>
                    <td className="px-4 py-3 text-right text-sm text-[var(--text-2)]">
                      {formatCurrency(period.baseline_amount)}
                    </td>
                    <td className="px-4 py-3 text-right text-sm font-medium text-[var(--text)]">
                      {period.projected_reduction_amount === null ? 'n/a' : formatCurrency(period.projected_reduction_amount)}
                    </td>
                    <td className="px-4 py-3 text-right text-sm font-medium text-[var(--text)]">
                      {formatCurrency(period.projected_avoidance_amount)}
                    </td>
                    <td className="px-4 py-3 text-right">
                      <Input
                        aria-label={`Actual spend for ${period.period_name}`}
                        type="number"
                        step="0.01"
                        defaultValue={period.actual_amount == null ? '' : period.actual_amount.toFixed(2)}
                        disabled={busy || !canEdit || period.projected_reduction_amount === null}
                        title={period.projected_reduction_amount === null ? 'Actual spend cannot derive reduction without an executed reduction comparator' : undefined}
                        onBlur={async (e) => {
                          const input = e.currentTarget
                          if (!moneyInputChanged(input.value, period.actual_amount)) return
                          const saved = await updateActualAmount(period.id, input.value)
                          if (!saved) input.value = period.actual_amount == null ? '' : period.actual_amount.toFixed(2)
                        }}
                        placeholder="0"
                        className="w-28"
                      />
                    </td>
                    <td className="px-4 py-3 text-right">
                      <Input
                        aria-label={`Realized reduction for ${period.period_name}`}
                        type="number"
                        step="0.01"
                        defaultValue={period.realized_reduction_amount == null ? '' : period.realized_reduction_amount.toFixed(2)}
                        disabled={busy || !canEdit}
                        onBlur={async event => {
                          const input = event.currentTarget
                          if (!moneyInputChanged(input.value, period.realized_reduction_amount)) return
                          const saved = await updateRealizedLeg(period.id, 'reduction', input.value)
                          if (!saved) input.value = period.realized_reduction_amount == null ? '' : period.realized_reduction_amount.toFixed(2)
                        }}
                        placeholder="0"
                        className="w-28"
                      />
                    </td>
                    <td className="px-4 py-3 text-right">
                      <Input
                        aria-label={`Realized avoidance for ${period.period_name}`}
                        type="number"
                        step="0.01"
                        defaultValue={period.realized_avoidance_amount == null ? '' : period.realized_avoidance_amount.toFixed(2)}
                        disabled={busy || !canEdit}
                        onBlur={async event => {
                          const input = event.currentTarget
                          if (!moneyInputChanged(input.value, period.realized_avoidance_amount)) return
                          const saved = await updateRealizedLeg(period.id, 'avoidance', input.value)
                          if (!saved) input.value = period.realized_avoidance_amount == null ? '' : period.realized_avoidance_amount.toFixed(2)
                        }}
                        placeholder="0"
                        className="w-28"
                      />
                    </td>
                    <td className="px-4 py-3 text-right text-sm font-medium text-green-600 dark:text-green-400">
                      {period.realized_savings === null ? '—' : formatCurrency(period.realized_savings)}
                    </td>
                    <td className={clsx('px-4 py-3 text-right text-sm font-medium',
                      period.leakage_amount > 0 ? 'text-red-600 dark:text-red-400' : 'text-[var(--text-2)]'
                    )}>
                      {period.leakage_amount === null ? 'Unknown' : period.leakage_amount > 0 ? formatCurrency(period.leakage_amount) : '—'}
                    </td>
                    <td className="px-4 py-3 text-center">
                      <span className={clsx(
                        'inline-flex rounded-full px-2.5 py-1 text-xs font-medium',
                        REALIZATION_STATUS_COLORS[period.realization_status],
                      )}>
                        {period.realization_status}
                      </span>
                    </td>
                    <td className="px-4 py-3 text-center">
                      {currentUserRole === 'admin' ? (
                        <button type="button" onClick={() => toggleFinanceValidated(period)}
                          disabled={busy}
                          aria-pressed={period.finance_validated}
                          aria-label={`${period.finance_validated ? 'Remove' : 'Mark'} finance validation for ${period.period_name}`}
                          className={clsx(
                            'inline-flex items-center justify-center rounded-full p-1',
                            period.finance_validated
                              ? 'bg-emerald-100 text-emerald-600 dark:bg-emerald-500/15 dark:text-emerald-400'
                              : 'bg-[var(--surface-2)] text-[var(--text-3)] hover:bg-[var(--border)]'
                          )}
                        >
                          {period.finance_validated ? <ShieldCheck className="h-4 w-4" /> : <Clock className="h-4 w-4" />}
                        </button>
                      ) : period.finance_validated ? (
                        <ShieldCheck className="mx-auto h-4 w-4 text-emerald-600 dark:text-emerald-400" aria-label="Finance validated" />
                      ) : (
                        <Clock className="mx-auto h-4 w-4 text-[var(--text-3)]" aria-label="Awaiting finance validation" />
                      )}
                    </td>
                    <td className="px-4 py-3 text-right">
                      {canDelete && (
                        <button type="button" onClick={() => setPeriodToDelete(period)}
                          disabled={busy || period.finance_validated}
                          title={period.finance_validated ? 'Remove finance validation before deleting this period' : undefined}
                          aria-label={`Delete realization period ${period.period_name}`}
                          className="text-[var(--text-3)] enabled:hover:text-red-600 disabled:cursor-not-allowed disabled:opacity-40 dark:enabled:hover:text-red-400">
                          <Trash2 className="h-4 w-4" />
                        </button>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
              <tfoot>
                <tr className="border-t-2 border-[var(--border)] bg-[var(--surface-2)] font-semibold">
                  <td className="px-4 py-3 text-sm text-[var(--text)]">Totals</td>
                  <td className="px-4 py-3"></td>
                  <td className="px-4 py-3 text-right text-sm text-[var(--text)]">{formatCurrency(totalProjectedReduction)}</td>
                  <td className="px-4 py-3 text-right text-sm text-[var(--text)]">{formatCurrency(totalProjectedAvoidance)}</td>
                  <td className="px-4 py-3"></td>
                  <td className="px-4 py-3 text-right text-sm text-green-600 dark:text-green-400">{formatCurrency(totalRealizedReduction)}</td>
                  <td className="px-4 py-3 text-right text-sm text-green-600 dark:text-green-400">{formatCurrency(totalRealizedAvoidance)}</td>
                  <td className="px-4 py-3 text-right text-sm font-bold text-green-600 dark:text-green-400">{formatCurrency(totalRealized)}</td>
                  <td className="px-4 py-3 text-right text-sm font-bold text-red-600 dark:text-red-400">{formatCurrency(totalLeakage)}</td>
                  <td colSpan={3} className="px-4 py-3"></td>
                </tr>
              </tfoot>
            </table>
          </div>
        </Card>
      )}

      {/* Info */}
      <div className="mt-4 rounded-lg border border-blue-200 bg-blue-50 p-4 dark:border-blue-900 dark:bg-blue-500/10">
        <div className="flex items-start gap-3">
          <AlertTriangle className="mt-0.5 h-5 w-5 flex-shrink-0 text-blue-600 dark:text-blue-400" />
          <div>
            <h3 className="text-sm font-semibold text-blue-900 dark:text-blue-300">How realized savings are captured</h3>
            <p className="mt-1 text-xs text-blue-700 dark:text-blue-300">
              Actual spend derives only realized reduction as Baseline − Actual Spend when the executed reduction comparator is defensible.
              Reduction and avoidance remain separate; avoidance is entered directly because it cannot be inferred safely from spend.
              Total realized savings adds the two legs exactly once. Leakage compares executed reduction with realized reduction only, so unconfirmed avoidance is never reported as leakage.
            </p>
          </div>
        </div>
      </div>
      {periodToDelete && (
        <ConfirmDialog
          title="Delete this realization period?"
          description={`This permanently removes ${periodToDelete.period_name} and its recorded realization amounts. This cannot be undone.`}
          confirmLabel="Delete Period"
          pendingLabel="Deleting Period..."
          onConfirm={() => handleDelete(periodToDelete.id)}
          onCancel={() => setPeriodToDelete(null)}
        />
      )}
    </div>
  )
}
