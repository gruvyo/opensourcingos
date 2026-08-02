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
import { Input, Select } from '@/components/ui/input'

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
  const [periods, setPeriods] = useState<any[]>([])
  const [calculations, setCalculations] = useState<any[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const supabase = createClient()

  const fetchPeriods = useCallback(async () => {
    const { data } = await supabase
      .from('realization_periods')
      .select(`
        *,
        savings_calculation:savings_calculations(calculation_name, savings_type)
      `)
      .eq('event_id', eventId)
      .order('period_start_date', { ascending: true })
    setPeriods(data || [])
    setLoading(false)
  }, [eventId, supabase])

  useEffect(() => {
    fetchPeriods()
    const fetchCalcs = async () => {
      const { data } = await supabase
        .from('savings_calculations')
        .select('id, calculation_name, savings_type, gross_savings_amount, baseline_total_amount')
        .eq('event_id', eventId)
      setCalculations(data || [])
    }
    fetchCalcs()
  }, [fetchPeriods, eventId, supabase])

  const updateActualAmount = async (periodId: string, actualAmount: string) => {
    const actual = parseFloat(actualAmount) || 0
    const period = periods.find(p => p.id === periodId)
    if (!period) return

    const realized = period.baseline_amount - actual
    const leakage = period.projected_savings - realized

    let status = 'Pending'
    if (actual > 0) {
      if (leakage <= 0) status = 'Realized'
      else if (leakage < period.projected_savings) status = 'Partially Realized'
      else status = 'Leaked'
    }

    await supabase
      .from('realization_periods')
      .update({
        actual_amount: actual,
        realized_savings: realized,
        leakage_amount: leakage,
        realization_status: status,
      })
      .eq('id', periodId)
    fetchPeriods()
  }

  const updateStatus = async (periodId: string, status: string) => {
    await supabase.from('realization_periods').update({ realization_status: status }).eq('id', periodId)
    fetchPeriods()
  }

  const toggleFinanceValidated = async (period: any) => {
    const { data: { user } } = await supabase.auth.getUser()
    const updates: any = { finance_validated: !period.finance_validated }
    if (!period.finance_validated) {
      updates.finance_validated_by = user?.id
      updates.finance_validation_date = new Date().toISOString()
    }
    await supabase.from('realization_periods').update(updates).eq('id', period.id)
    fetchPeriods()
  }

  const handleDelete = async (periodId: string) => {
    if (!confirm('Delete this realization period?')) return
    await supabase.from('realization_periods').delete().eq('id', periodId)
    setPeriods(periods.filter(p => p.id !== periodId))
  }

  const handleAdd = async (form: any) => {
    const { data: { user } } = await supabase.auth.getUser()
    const { data: profile } = await supabase
      .from('profiles')
      .select('organization_id')
      .eq('id', user!.id)
      .single()

    const baseline = parseFloat(form.baseline_amount) || 0
    const projected = parseFloat(form.projected_savings) || 0

    await supabase.from('realization_periods').insert({
      organization_id: profile?.organization_id,
      event_id: eventId,
      savings_calculation_id: form.savings_calculation_id || null,
      period_name: form.period_name,
      period_start_date: form.period_start_date,
      period_end_date: form.period_end_date,
      baseline_amount: baseline,
      projected_savings: projected,
      actual_amount: 0,
      realized_savings: 0,
      leakage_amount: 0,
      realization_status: 'Pending',
      created_by: user?.id,
    })
    setShowForm(false)
    fetchPeriods()
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
      {/* Header */}
      <div className="mb-4 flex items-center justify-between">
        <div>
          <h3 className="text-lg font-semibold text-[var(--text)]">Realization Tracking</h3>
          <p className="text-sm text-[var(--text-2)]">Track actual savings vs projected savings over time</p>
        </div>
        <Button onClick={() => setShowForm(!showForm)} className="flex items-center gap-2">
          <Plus className="h-4 w-4" />
          Add Period
        </Button>
      </div>

      {/* Summary Cards */}
      <div className="mb-4 grid grid-cols-2 gap-4 lg:grid-cols-4">
        <Card className="p-4">
          <p className="text-xs text-[var(--text-3)]">Projected Savings</p>
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

      {/* Add Period Form */}
      {showForm && (
        <AddPeriodForm
          calculations={calculations}
          onSaved={handleAdd}
          onCancel={() => setShowForm(false)}
        />
      )}

      {/* Periods Table */}
      {periods.length === 0 ? (
        <Card className="p-12 text-center">
          <TrendingUp className="mx-auto mb-3 h-10 w-10 text-[var(--text-3)]" />
          <h3 className="text-sm font-medium text-[var(--text)]">No realization periods yet</h3>
          <p className="mt-1 text-sm text-[var(--text-3)]">Click &quot;Add Period&quot; to track savings over time.</p>
        </Card>
      ) : (
        <Card className="overflow-hidden">
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-[var(--border)] bg-[var(--surface-2)] text-left text-xs uppercase text-[var(--text-3)]">
                  <th className="px-4 py-3">Period</th>
                  <th className="px-4 py-3 text-right">Baseline</th>
                  <th className="px-4 py-3 text-right">Projected</th>
                  <th className="px-4 py-3 text-right">Actual</th>
                  <th className="px-4 py-3 text-right">Realized</th>
                  <th className="px-4 py-3 text-right">Leakage</th>
                  <th className="px-4 py-3 text-center">Status</th>
                  <th className="px-4 py-3 text-center">Finance</th>
                  <th className="px-4 py-3"></th>
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
                    </td>
                    <td className="px-4 py-3 text-right text-sm text-[var(--text-2)]">
                      {formatCurrency(period.baseline_amount)}
                    </td>
                    <td className="px-4 py-3 text-right text-sm font-medium text-[var(--text)]">
                      {formatCurrency(period.projected_savings)}
                    </td>
                    <td className="px-4 py-3 text-right">
                      <Input
                        type="number"
                        step="0.01"
                        defaultValue={period.actual_amount || ''}
                        onBlur={(e) => updateActualAmount(period.id, e.target.value)}
                        placeholder="0"
                        className="w-28"
                      />
                    </td>
                    <td className="px-4 py-3 text-right text-sm font-medium text-green-600 dark:text-green-400">
                      {formatCurrency(period.realized_savings)}
                    </td>
                    <td className={clsx('px-4 py-3 text-right text-sm font-medium',
                      period.leakage_amount > 0 ? 'text-red-600 dark:text-red-400' : 'text-[var(--text-2)]'
                    )}>
                      {period.leakage_amount > 0 ? formatCurrency(period.leakage_amount) : '—'}
                    </td>
                    <td className="px-4 py-3 text-center">
                      <Select
                        value={period.realization_status}
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
                      <button onClick={() => toggleFinanceValidated(period)}
                        className={clsx(
                          'inline-flex items-center justify-center rounded-full p-1',
                          period.finance_validated
                            ? 'bg-emerald-100 text-emerald-600 dark:bg-emerald-500/15 dark:text-emerald-400'
                            : 'bg-[var(--surface-2)] text-[var(--text-3)] hover:bg-[var(--border)]'
                        )}
                        title="Toggle Finance Validation"
                      >
                        {period.finance_validated ? <ShieldCheck className="h-4 w-4" /> : <Clock className="h-4 w-4" />}
                      </button>
                    </td>
                    <td className="px-4 py-3 text-right">
                      <button onClick={() => handleDelete(period.id)}
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
            <h4 className="text-sm font-semibold text-blue-900 dark:text-blue-300">Realization Formula</h4>
            <p className="mt-1 text-xs text-blue-700 dark:text-blue-300">
              <strong>Realized Savings</strong> = Baseline − Actual Invoice Amount<br/>
              <strong>Leakage</strong> = Projected Savings − Realized Savings (if &gt; 0, savings leaked)<br/>
              Enter the actual invoice amount in the &quot;Actual&quot; column to auto-calculate realized savings and leakage.
            </p>
          </div>
        </div>
      </div>
    </div>
  )
}

// ============================================
// Add Period Form
// ============================================
function AddPeriodForm({ calculations, onSaved, onCancel }: {
  calculations: any[]
  onSaved: (form: any) => void
  onCancel: () => void
}) {
  const [form, setForm] = useState({
    savings_calculation_id: '',
    period_name: '',
    period_start_date: '',
    period_end_date: '',
    baseline_amount: '',
    projected_savings: '',
  })

  const labelClass = 'block text-xs font-medium text-[var(--text-2)]'

  return (
    <form onSubmit={(e) => { e.preventDefault(); onSaved(form) }}
      className="mb-6 rounded-lg border border-indigo-200 bg-indigo-50 p-6 dark:border-indigo-900 dark:bg-indigo-500/10">
      <h4 className="mb-4 font-medium text-[var(--text)]">New Realization Period</h4>
      <div className="grid grid-cols-1 gap-4 md:grid-cols-2">
        <div className="md:col-span-2">
          <label className={labelClass}>Period Name *</label>
          <Input type="text" required value={form.period_name}
            onChange={(e) => setForm({ ...form, period_name: e.target.value })}
            className="mt-1" placeholder="e.g. Q1 FY2026 (Apr-Jun)" />
        </div>
        <div>
          <label className={labelClass}>Linked Calculation</label>
          <Select value={form.savings_calculation_id}
            onChange={(e) => {
              const id = e.target.value
              const calc = calculations.find((c) => c.id === id)
              // Auto-fill baseline + projected from the linked calculation
              // (still editable afterward).
              setForm((prev) => ({
                ...prev,
                savings_calculation_id: id,
                baseline_amount: calc?.baseline_total_amount != null ? String(calc.baseline_total_amount) : prev.baseline_amount,
                projected_savings: calc?.gross_savings_amount != null ? String(calc.gross_savings_amount) : prev.projected_savings,
              }))
            }}
            className="mt-1">
            <option value="">None</option>
            {calculations.map((c) => (
              <option key={c.id} value={c.id}>{c.calculation_name}</option>
            ))}
          </Select>
          <p className="mt-1 text-xs text-[var(--text-3)]">Linking a calculation fills in baseline &amp; projected below.</p>
        </div>
        <div></div>
        <div>
          <label className={labelClass}>Period Start Date *</label>
          <Input type="date" required value={form.period_start_date}
            onChange={(e) => setForm({ ...form, period_start_date: e.target.value })}
            className="mt-1" />
        </div>
        <div>
          <label className={labelClass}>Period End Date *</label>
          <Input type="date" required value={form.period_end_date}
            onChange={(e) => setForm({ ...form, period_end_date: e.target.value })}
            className="mt-1" />
        </div>
        <div>
          <label className={labelClass}>Baseline Amount *</label>
          <Input type="number" step="0.01" required value={form.baseline_amount}
            onChange={(e) => setForm({ ...form, baseline_amount: e.target.value })}
            className="mt-1" placeholder="0.00" />
        </div>
        <div>
          <label className={labelClass}>Projected Savings *</label>
          <Input type="number" step="0.01" required value={form.projected_savings}
            onChange={(e) => setForm({ ...form, projected_savings: e.target.value })}
            className="mt-1" placeholder="0.00" />
        </div>
      </div>
      <div className="mt-4 flex justify-end gap-2">
        <Button type="button" variant="secondary" onClick={onCancel}>
          Cancel
        </Button>
        <Button type="submit">
          Add Period
        </Button>
      </div>
    </form>
  )
}
