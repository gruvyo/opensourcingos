'use client'

import { useState, useEffect, useCallback } from 'react'
import { createClient } from '@/lib/supabase/client'
import {
  TrendingUp, Plus, Trash2, AlertTriangle,
  ShieldCheck, Clock,
} from 'lucide-react'
import { formatCurrency, formatDate } from '@/lib/utils'
import { clsx } from 'clsx'
import { Card } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { ConfirmDialog } from '@/components/ui/confirm-dialog'
import { Input, Select } from '@/components/ui/input'
import type { Tables, TablesUpdate } from '@/lib/database.types'

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
  'executed_baseline_amount' | 'executed_total_savings_amount'
>

const REALIZATION_STATUS_COLORS: Record<string, string> = {
  'Pending': 'bg-gray-100 text-gray-700 dark:bg-gray-500/20 dark:text-gray-300',
  'In Progress': 'bg-blue-100 text-blue-700 dark:bg-blue-500/15 dark:text-blue-300',
  'Realized': 'bg-green-100 text-green-700 dark:bg-green-500/15 dark:text-green-300',
  'Partially Realized': 'bg-amber-100 text-amber-700 dark:bg-amber-500/15 dark:text-amber-300',
  'Not Realized': 'bg-red-100 text-red-700 dark:bg-red-500/15 dark:text-red-300',
  'Leaked': 'bg-red-100 text-red-700 dark:bg-red-500/15 dark:text-red-300',
}

const REALIZATION_STATUSES = ['Pending', 'In Progress', 'Realized', 'Partially Realized', 'Not Realized', 'Leaked']

export function RealizationTab({ eventId }: { eventId: string }) {
  const [periods, setPeriods] = useState<RealizationPeriod[]>([])
  const [scheduleRows, setScheduleRows] = useState<ExecutedScheduleRow[]>([])
  const [loading, setLoading] = useState(true)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [periodToDelete, setPeriodToDelete] = useState<RealizationPeriod | null>(null)
  const supabase = createClient()

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
          .select('id, savings_calculation_id, period_month, period_year, period_months, executed_baseline_amount, executed_total_savings_amount')
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
    const actual = hasActual ? (parseFloat(actualAmount) || 0) : null

    if (!hasActual) {
      setBusy(true); setError(null)
      const { error: clearError } = await supabase.from('realization_periods')
        .update({ actual_amount: null }).eq('id', periodId)
      if (clearError) { setError(`Actual spend could not be cleared: ${clearError.message}`); setBusy(false); return false }
      const refreshed = await fetchPeriods('Actual spend was cleared, but realization data could not be refreshed')
      setBusy(false)
      return refreshed
    }

    const realized = period.baseline_amount > 0
      ? period.baseline_amount - Number(actual)
      : Number(period.realized_savings ?? 0)
    const leakage = period.projected_savings - realized

    let status = 'Pending'
    if (Number(actual) > 0) {
      if (leakage <= 0) status = 'Realized'
      else if (leakage < period.projected_savings) status = 'Partially Realized'
      else status = 'Leaked'
    }

    setBusy(true)
    setError(null)
    const { data: updatedPeriod, error: updateError } = await supabase
      .from('realization_periods')
      .update({
        actual_amount: actual,
        realized_savings: realized,
        leakage_amount: leakage,
        realization_status: status,
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

  const updateRealizedSavings = async (periodId: string, realizedAmount: string) => {
    const period = periods.find(candidate => candidate.id === periodId)
    if (!period) return false
    const realized = parseFloat(realizedAmount) || 0
    const leakage = period.projected_savings - realized
    const status = realized <= 0 ? 'Not Realized'
      : leakage <= 0 ? 'Realized'
      : 'Partially Realized'

    setBusy(true); setError(null)
    const { data: updatedPeriod, error: updateError } = await supabase
      .from('realization_periods')
      .update({ realized_savings: realized, leakage_amount: leakage, realization_status: status })
      .eq('id', periodId)
      .select('id')
      .maybeSingle()
    if (updateError || !updatedPeriod) {
      setError(`Realized savings could not be saved: ${updateError?.message || 'The realization period was not updated'}`)
      setBusy(false)
      return false
    }
    const refreshed = await fetchPeriods('Realized savings was saved, but realization data could not be refreshed')
    setBusy(false)
    return refreshed
  }

  const updateStatus = async (periodId: string, status: string) => {
    setBusy(true)
    setError(null)
    const { data: updatedPeriod, error: updateError } = await supabase
      .from('realization_periods')
      .update({ realization_status: status })
      .eq('id', periodId)
      .select('id')
      .maybeSingle()
    if (updateError || !updatedPeriod) {
      setError(`Realization status could not be saved: ${updateError?.message || 'The realization period was not updated'}`)
      setBusy(false)
      return
    }

    await fetchPeriods('Realization status was saved, but realization data could not be refreshed')
    setBusy(false)
  }

  const toggleFinanceValidated = async (period: RealizationPeriod) => {
    setBusy(true)
    setError(null)
    const { data: { user }, error: userError } = await supabase.auth.getUser()
    if (userError || !user) {
      setError(`Finance validation could not be saved: ${userError?.message || 'Not logged in'}`)
      setBusy(false)
      return
    }

    const updates: TablesUpdate<'realization_periods'> = { finance_validated: !period.finance_validated }
    if (!period.finance_validated) {
      updates.finance_validated_by = user.id
      updates.finance_validation_date = new Date().toISOString()
    }
    const { data: updatedPeriod, error: updateError } = await supabase
      .from('realization_periods')
      .update(updates)
      .eq('id', period.id)
      .select('id')
      .maybeSingle()
    if (updateError || !updatedPeriod) {
      setError(`Finance validation could not be saved: ${updateError?.message || 'The realization period was not updated'}`)
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
    const { data: { user }, error: userError } = await supabase.auth.getUser()
    if (userError || !user) {
      setError(`Realization period could not be added: ${userError?.message || 'Not logged in'}`)
      setBusy(false)
      return
    }

    const { data: profile, error: profileError } = await supabase
      .from('profiles')
      .select('organization_id')
      .eq('id', user.id)
      .single()
    if (profileError || !profile?.organization_id) {
      setError(`Realization period could not be added: ${profileError?.message || 'Workspace not found'}`)
      setBusy(false)
      return
    }

    const existingScheduleIds = new Set(periods.map(period => period.savings_period_id).filter(Boolean))
    const missingRows = scheduleRows.filter(row => !existingScheduleIds.has(row.id))
    if (missingRows.length === 0) { setBusy(false); return }

    const payload = missingRows.map(row => {
      const start = new Date(Date.UTC(row.period_year, row.period_month - 1, 1))
      const end = new Date(start)
      end.setUTCMonth(end.getUTCMonth() + Math.max(1, Math.round(Number(row.period_months))))
      end.setUTCDate(end.getUTCDate() - 1)
      return {
        organization_id: profile.organization_id,
        event_id: eventId,
        savings_calculation_id: row.savings_calculation_id,
        savings_period_id: row.id,
        period_name: start.toLocaleDateString('en-US', { month: 'short', year: 'numeric', timeZone: 'UTC' }),
        period_start_date: start.toISOString().slice(0, 10),
        period_end_date: end.toISOString().slice(0, 10),
        baseline_amount: Number(row.executed_baseline_amount ?? 0),
        projected_savings: Number(row.executed_total_savings_amount ?? 0),
        actual_amount: null,
        realized_savings: null,
        leakage_amount: null,
        realization_status: 'Pending',
        created_by: user.id,
      }
    })

    const { error: insertError } = await supabase.from('realization_periods').insert(payload)
    if (insertError) {
      setError(`Savings Realization periods could not be created: ${insertError.message}`)
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
        <Button disabled={busy || scheduleRows.length === 0 || periods.length === scheduleRows.length} onClick={syncExecutedSchedule} className="flex items-center gap-2">
          <Plus className="h-4 w-4" />
          Create tracking periods
        </Button>
      </div>

      {/* Summary Cards */}
      <div className="mb-4 grid grid-cols-2 gap-4 lg:grid-cols-4">
        <Card className="p-4">
          <p className="text-xs text-[var(--text-3)]">Executed Savings</p>
          <p className="mt-1 text-xl font-bold text-[var(--text)]">{formatCurrency(totalProjected)}</p>
        </Card>
        <Card className="p-4">
          <p className="text-xs text-[var(--text-3)]">Realized Savings</p>
          <p className="mt-1 text-xl font-bold text-green-600 dark:text-green-400">{formatCurrency(totalRealized)}</p>
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
                  <th scope="col" className="px-4 py-3 text-right">Executed</th>
                  <th scope="col" className="px-4 py-3 text-right">Actual</th>
                  <th scope="col" className="px-4 py-3 text-right">Realized</th>
                  <th scope="col" className="px-4 py-3 text-right">Leakage</th>
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
                      {formatCurrency(period.projected_savings)}
                    </td>
                    <td className="px-4 py-3 text-right">
                      <Input
                        aria-label={`Actual spend for ${period.period_name}`}
                        type="number"
                        step="0.01"
        defaultValue={period.actual_amount ?? ''}
                        disabled={busy}
                        onBlur={async (e) => {
                          const input = e.currentTarget
                          const saved = await updateActualAmount(period.id, input.value)
                          if (!saved) input.value = period.actual_amount == null ? '' : String(period.actual_amount)
                        }}
                        placeholder="0"
                        className="w-28"
                      />
                    </td>
                    <td className="px-4 py-3 text-right">
                      <Input
                        aria-label={`Realized savings for ${period.period_name}`}
                        type="number"
                        step="0.01"
                        defaultValue={period.realized_savings ?? ''}
                        disabled={busy}
                        onBlur={async event => {
                          const input = event.currentTarget
                          const saved = await updateRealizedSavings(period.id, input.value)
                          if (!saved) input.value = period.realized_savings == null ? '' : String(period.realized_savings)
                        }}
                        placeholder="0"
                        className="w-28"
                      />
                    </td>
                    <td className={clsx('px-4 py-3 text-right text-sm font-medium',
                      period.leakage_amount > 0 ? 'text-red-600 dark:text-red-400' : 'text-[var(--text-2)]'
                    )}>
                      {period.leakage_amount > 0 ? formatCurrency(period.leakage_amount) : '—'}
                    </td>
                    <td className="px-4 py-3 text-center">
                      <Select
                        aria-label={`Status for ${period.period_name}`}
                        value={period.realization_status}
                        disabled={busy}
                        onChange={(e) => updateStatus(period.id, e.target.value)}
                        className={clsx('w-auto rounded-full border-0 px-2.5 py-1 text-xs font-medium',
                          REALIZATION_STATUS_COLORS[period.realization_status]
                        )}
                      >
                        {REALIZATION_STATUSES.map((s) => (
                          <option key={s} value={s}>{s}</option>
                        ))}
                      </Select>
                    </td>
                    <td className="px-4 py-3 text-center">
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
                    </td>
                    <td className="px-4 py-3 text-right">
                      <button type="button" onClick={() => setPeriodToDelete(period)}
                        disabled={busy}
                        aria-label={`Delete realization period ${period.period_name}`}
                        className="text-[var(--text-3)] hover:text-red-600 dark:hover:text-red-400">
                        <Trash2 className="h-4 w-4" />
                      </button>
                    </td>
                  </tr>
                ))}
              </tbody>
              <tfoot>
                <tr className="border-t-2 border-[var(--border)] bg-[var(--surface-2)] font-semibold">
                  <td className="px-4 py-3 text-sm text-[var(--text)]">Totals</td>
                  <td className="px-4 py-3"></td>
                  <td className="px-4 py-3 text-right text-sm text-[var(--text)]">{formatCurrency(totalProjected)}</td>
                  <td className="px-4 py-3"></td>
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
              For a defensible spend baseline, entering actual spend calculates realized savings as Baseline − Actual Spend.
              You may also enter realized savings directly when the result is finance-approved or cost avoidance cannot be derived safely from spend.
              Leakage is Executed Savings − Realized Savings.
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
