#!/bin/bash

# Create the calculations tab component
cat > components/calculations-tab.tsx << 'EOF'
'use client'

import { useState, useEffect, useCallback } from 'react'
import { createClient } from '@/lib/supabase/client'
import {
  Calculator, Plus, Trash2, ChevronDown, ChevronRight,
  CheckCircle, FileCheck, TrendingDown, Award, ShieldCheck, Lock,
} from 'lucide-react'
import { formatCurrency, formatDate } from '@/lib/utils'
import { clsx } from 'clsx'

const SAVINGS_TYPES = ['Hard Savings', 'Cost Avoidance', 'Demand Reduction', 'TCO Improvement', 'Working Capital']
const CALC_STATUS_COLORS: Record<string, string> = {
  'Draft': 'bg-gray-100 text-gray-700',
  'Submitted': 'bg-amber-100 text-amber-700',
  'Approved': 'bg-green-100 text-green-700',
  'Rejected': 'bg-red-100 text-red-700',
}

export function CalculationsTab({ eventId }: { eventId: string }) {
  const [calculations, setCalculations] = useState<any[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [expandedId, setExpandedId] = useState<string | null>(null)
  const [calcLines, setCalcLines] = useState<Record<string, any[]>>({})
  const [baselines, setBaselines] = useState<any[]>([])
  const [awards, setAwards] = useState<any[]>([])
  const supabase = createClient()

  const fetchCalculations = useCallback(async () => {
    const { data } = await supabase
      .from('savings_calculations')
      .select(`
        *,
        baseline:baselines(baseline_name),
        award:awards(award_name)
      `)
      .eq('event_id', eventId)
      .order('created_at', { ascending: true })
    setCalculations(data || [])
    setLoading(false)
  }, [eventId, supabase])

  const fetchBaselinesAndAwards = useCallback(async () => {
    const [{ data: baseData }, { data: awardData }] = await Promise.all([
      supabase.from('baselines').select('id, baseline_name, baseline_total_amount, official_for_hard_savings, official_for_cost_avoidance, official_for_demand_reduction, baseline_lock_status').eq('event_id', eventId),
      supabase.from('awards').select('id, award_name, award_total_amount, award_status').eq('event_id', eventId),
    ])
    setBaselines(baseData || [])
    setAwards(awardData || [])
  }, [eventId, supabase])

  useEffect(() => {
    fetchCalculations()
    fetchBaselinesAndAwards()
  }, [fetchCalculations, fetchBaselinesAndAwards])

  const fetchCalcLines = async (calcId: string) => {
    if (calcLines[calcId]) return
    const { data } = await supabase
      .from('savings_calculation_lines')
      .select(`
        *,
        scope_line:event_scope_lines(item_service_name, uom)
      `)
      .eq('savings_calculation_id', calcId)
      .order('line_number', { ascending: true })
    setCalcLines(prev => ({ ...prev, [calcId]: data || [] }))
  }

  const toggleExpand = (calcId: string) => {
    if (expandedId === calcId) {
      setExpandedId(null)
    } else {
      setExpandedId(calcId)
      fetchCalcLines(calcId)
    }
  }

  const updateStatus = async (calcId: string, newStatus: string) => {
    await supabase.from('savings_calculations').update({ calculation_status: newStatus }).eq('id', calcId)
    fetchCalculations()
  }

  const toggleFinanceValidated = async (calc: any) => {
    const { data: { user } } = await supabase.auth.getUser()
    const updates: any = {
      finance_validated: !calc.finance_validated,
    }
    if (!calc.finance_validated) {
      updates.finance_validated_by = user?.id
      updates.finance_validation_date = new Date().toISOString()
    }
    await supabase.from('savings_calculations').update(updates).eq('id', calc.id)
    fetchCalculations()
  }

  const handleDelete = async (calcId: string) => {
    if (!confirm('Delete this savings calculation?')) return
    await supabase.from('savings_calculations').delete().eq('id', calcId)
    setCalculations(calculations.filter(c => c.id !== calcId))
  }

  if (loading) {
    return <div className="p-8 text-center text-sm text-gray-500">Loading calculations...</div>
  }

  return (
    <div>
      {/* Header */}
      <div className="mb-4 flex items-center justify-between">
        <div>
          <h3 className="text-lg font-semibold text-gray-900">Savings Calculations</h3>
          <p className="text-sm text-gray-600">Calculate savings by comparing official baseline vs award</p>
        </div>
        <button
          onClick={() => setShowForm(!showForm)}
          className="flex items-center gap-2 rounded-lg bg-indigo-600 px-4 py-2 text-sm font-medium text-white hover:bg-indigo-700"
        >
          <Plus className="h-4 w-4" />
          Add Calculation
        </button>
      </div>

      {/* Info Banner */}
      <div className="mb-4 rounded-lg border border-blue-200 bg-blue-50 p-4">
        <div className="flex items-start gap-3">
          <Calculator className="mt-0.5 h-5 w-5 flex-shrink-0 text-blue-600" />
          <div>
            <h4 className="text-sm font-semibold text-blue-900">Savings Formula</h4>
            <p className="mt-1 text-xs text-blue-700">
              <strong>Gross Savings</strong> = Official Baseline − Award Amount<br/>
              <strong>Savings %</strong> = (Gross Savings / Baseline) × 100<br/>
              <strong>Net Savings</strong> = Gross Savings (minus any implementation costs if applicable)
            </p>
          </div>
        </div>
      </div>

      {/* Add Form */}
      {showForm && (
        <AddCalculationForm
          eventId={eventId}
          baselines={baselines}
          awards={awards}
          onSaved={() => { setShowForm(false); fetchCalculations() }}
          onCancel={() => setShowForm(false)}
        />
      )}

      {/* Calculations List */}
      {calculations.length === 0 ? (
        <div className="rounded-lg border border-gray-200 bg-white p-12 text-center shadow-sm">
          <Calculator className="mx-auto mb-3 h-10 w-10 text-gray-300" />
          <h3 className="text-sm font-medium text-gray-900">No savings calculations yet</h3>
          <p className="mt-1 text-sm text-gray-500">Click "Add Calculation" to calculate savings.</p>
        </div>
      ) : (
        <div className="space-y-3">
          {calculations.map((calc) => {
            const isExpanded = expandedId === calc.id
            const lines = calcLines[calc.id] || []
            const isNegative = calc.gross_savings_amount < 0

            return (
              <div key={calc.id} className="overflow-hidden rounded-lg border border-gray-200 bg-white shadow-sm">
                {/* Calc Header */}
                <div className="flex items-center gap-4 p-4">
                  <button onClick={() => toggleExpand(calc.id)} className="text-gray-400 hover:text-gray-600">
                    {isExpanded ? <ChevronDown className="h-5 w-5" /> : <ChevronRight className="h-5 w-5" />}
                  </button>

                  <div className="flex-1">
                    <div className="flex items-center gap-2">
                      <h4 className="text-sm font-semibold text-gray-900">{calc.calculation_name}</h4>
                      <span className={clsx('rounded px-2 py-0.5 text-xs font-medium',
                        calc.savings_type === 'Hard Savings' ? 'bg-green-100 text-green-700' :
                        calc.savings_type === 'Cost Avoidance' ? 'bg-purple-100 text-purple-700' :
                        calc.savings_type === 'Demand Reduction' ? 'bg-orange-100 text-orange-700' :
                        'bg-blue-100 text-blue-700'
                      )}>
                        {calc.savings_type}
                      </span>
                      {calc.finance_validated && (
                        <span className="flex items-center gap-1 rounded bg-emerald-100 px-2 py-0.5 text-xs font-medium text-emerald-700">
                          <ShieldCheck className="h-3 w-3" /> Finance Validated
                        </span>
                      )}
                    </div>
                    <p className="mt-1 text-xs text-gray-500">
                      Baseline: {calc.baseline?.baseline_name || '—'} • Award: {calc.award?.award_name || '—'}
                    </p>
                  </div>

                  {/* Savings Amount */}
                  <div className="text-right">
                    <p className="text-xs text-gray-500">Gross Savings</p>
                    <p className={clsx('text-lg font-bold', isNegative ? 'text-red-600' : 'text-green-600')}>
                      {isNegative ? '-' : ''}{formatCurrency(Math.abs(calc.gross_savings_amount || 0))}
                    </p>
                    <p className="text-xs text-gray-500">{calc.savings_percentage?.toFixed(1)}%</p>
                  </div>

                  {/* Status */}
                  <span className={clsx('rounded-full px-2.5 py-1 text-xs font-medium',
                    CALC_STATUS_COLORS[calc.calculation_status] || 'bg-gray-100 text-gray-700'
                  )}>
                    {calc.calculation_status}
                  </span>
                </div>

                {/* Expanded View */}
                {isExpanded && (
                  <div className="border-t border-gray-200 bg-gray-50">
                    {/* Summary Stats */}
                    <div className="grid grid-cols-2 gap-px border-b border-gray-200 bg-gray-200 md:grid-cols-4">
                      <div className="bg-white px-4 py-3">
                        <p className="text-xs text-gray-500">Baseline Total</p>
                        <p className="text-sm font-semibold text-gray-900">{formatCurrency(calc.baseline_total_amount)}</p>
                      </div>
                      <div className="bg-white px-4 py-3">
                        <p className="text-xs text-gray-500">Award Total</p>
                        <p className="text-sm font-semibold text-gray-900">{formatCurrency(calc.award_total_amount)}</p>
                      </div>
                      <div className="bg-white px-4 py-3">
                        <p className="text-xs text-gray-500">Gross Savings</p>
                        <p className={clsx('text-sm font-semibold', isNegative ? 'text-red-600' : 'text-green-600')}>
                          {formatCurrency(calc.gross_savings_amount)}
                        </p>
                      </div>
                      <div className="bg-white px-4 py-3">
                        <p className="text-xs text-gray-500">Current-Year Recognized</p>
                        <p className="text-sm font-semibold text-indigo-700">{formatCurrency(calc.current_year_recognized_amount)}</p>
                      </div>
                    </div>

                    {/* Actions */}
                    <div className="flex flex-wrap items-center gap-2 border-b border-gray-200 bg-white px-4 py-3">
                      <span className="text-xs font-medium text-gray-500">Workflow:</span>
                      {calc.calculation_status === 'Draft' && (
                        <button onClick={() => updateStatus(calc.id, 'Submitted')}
                          className="flex items-center gap-1 rounded bg-amber-50 px-2.5 py-1 text-xs font-medium text-amber-700 hover:bg-amber-100">
                          <FileCheck className="h-3 w-3" /> Submit for Review
                        </button>
                      )}
                      {calc.calculation_status === 'Submitted' && (
                        <>
                          <button onClick={() => updateStatus(calc.id, 'Approved')}
                            className="flex items-center gap-1 rounded bg-green-50 px-2.5 py-1 text-xs font-medium text-green-700 hover:bg-green-100">
                            <CheckCircle className="h-3 w-3" /> Approve
                          </button>
                          <button onClick={() => updateStatus(calc.id, 'Rejected')}
                            className="flex items-center gap-1 rounded bg-red-50 px-2.5 py-1 text-xs font-medium text-red-700 hover:bg-red-100">
                            Reject
                          </button>
                        </>
                      )}
                      <button onClick={() => toggleFinanceValidated(calc)}
                        className={clsx(
                          'flex items-center gap-1 rounded px-2.5 py-1 text-xs font-medium',
                          calc.finance_validated
                            ? 'bg-emerald-100 text-emerald-700'
                            : 'bg-gray-100 text-gray-600 hover:bg-gray-200'
                        )}>
                        <ShieldCheck className="h-3 w-3" />
                        {calc.finance_validated ? 'Finance Validated' : 'Mark Finance Validated'}
                      </button>
                      {calc.calculation_status === 'Draft' && (
                        <button onClick={() => handleDelete(calc.id)}
                          className="ml-auto text-gray-400 hover:text-red-600">
                          <Trash2 className="h-4 w-4" />
                        </button>
                      )}
                    </div>

                    {/* Line-Level Breakdown */}
                    <div className="p-4">
                      <h5 className="mb-3 text-sm font-medium text-gray-700">Line-Level Savings Breakdown</h5>
                      {lines.length === 0 ? (
                        <p className="py-6 text-center text-xs text-gray-500">
                          No line-level breakdown available. Add savings calculation lines for detailed tracking.
                        </p>
                      ) : (
                        <div className="overflow-x-auto">
                          <table className="w-full text-sm">
                            <thead>
                              <tr className="border-b border-gray-200 text-left text-xs uppercase text-gray-500">
                                <th className="px-2 py-2">#</th>
                                <th className="px-2 py-2">Scope Line</th>
                                <th className="px-2 py-2 text-right">Baseline Unit Price</th>
                                <th className="px-2 py-2 text-right">Baseline Ext.</th>
                                <th className="px-2 py-2 text-right">Award Unit Price</th>
                                <th className="px-2 py-2 text-right">Award Ext.</th>
                                <th className="px-2 py-2 text-right">Savings</th>
                                <th className="px-2 py-2 text-right">Savings %</th>
                              </tr>
                            </thead>
                            <tbody className="divide-y divide-gray-100">
                              {lines.map((line) => (
                                <tr key={line.id} className="hover:bg-gray-50">
                                  <td className="px-2 py-2 text-xs text-gray-500">{line.line_number}</td>
                                  <td className="px-2 py-2 text-xs font-medium text-gray-900">
                                    {line.scope_line?.item_service_name || '—'}
                                  </td>
                                  <td className="px-2 py-2 text-right text-xs text-gray-700">
                                    {formatCurrency(line.baseline_unit_price)}
                                  </td>
                                  <td className="px-2 py-2 text-right text-xs text-gray-700">
                                    {formatCurrency(line.baseline_extended_amount)}
                                  </td>
                                  <td className="px-2 py-2 text-right text-xs text-gray-700">
                                    {formatCurrency(line.awarded_unit_price)}
                                  </td>
                                  <td className="px-2 py-2 text-right text-xs text-gray-700">
                                    {formatCurrency(line.awarded_extended_amount)}
                                  </td>
                                  <td className={clsx('px-2 py-2 text-right text-xs font-medium',
                                    line.savings_amount < 0 ? 'text-red-600' : 'text-green-600'
                                  )}>
                                    {formatCurrency(line.savings_amount)}
                                  </td>
                                  <td className="px-2 py-2 text-right text-xs text-gray-700">
                                    {line.savings_percentage?.toFixed(1)}%
                                  </td>
                                </tr>
                              ))}
                            </tbody>
                            <tfoot>
                              <tr className="border-t-2 border-gray-200 bg-gray-50 font-medium">
                                <td colSpan={6} className="px-2 py-2 text-right text-xs text-gray-600">Total Savings:</td>
                                <td className={clsx('px-2 py-2 text-right text-xs font-bold',
                                  calc.gross_savings_amount < 0 ? 'text-red-600' : 'text-green-600'
                                )}>
                                  {formatCurrency(calc.gross_savings_amount)}
                                </td>
                                <td className="px-2 py-2 text-right text-xs text-gray-700">
                                  {calc.savings_percentage?.toFixed(1)}%
                                </td>
                              </tr>
                            </tfoot>
                          </table>
                        </div>
                      )}
                    </div>
                  </div>
                )}
              </div>
            )
          })}
        </div>
      )}
    </div>
  )
}

// ============================================
// Add Calculation Form
// ============================================
function AddCalculationForm({ eventId, baselines, awards, onSaved, onCancel }: {
  eventId: string
  baselines: any[]
  awards: any[]
  onSaved: () => void
  onCancel: () => void
}) {
  const supabase = createClient()
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [form, setForm] = useState({
    calculation_name: '',
    savings_type: 'Hard Savings',
    baseline_id: '',
    award_id: '',
  })

  const selectedBaseline = baselines.find(b => b.id === form.baseline_id)

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    setLoading(true)
    setError(null)

    const { data: { user } } = await supabase.auth.getUser()
    if (!user) { setError('Not logged in'); setLoading(false); return }

    const { data: profile } = await supabase
      .from('profiles')
      .select('organization_id')
      .eq('id', user.id)
      .single()

    const baseline = baselines.find(b => b.id === form.baseline_id)
    const award = awards.find(a => a.id === form.award_id)
    const baselineAmount = baseline?.baseline_total_amount || 0
    const awardAmount = award?.award_total_amount || 0
    const grossSavings = baselineAmount - awardAmount
    const savingsPct = baselineAmount > 0 ? (grossSavings / baselineAmount) * 100 : 0

    const { error: insertError } = await supabase
      .from('savings_calculations')
      .insert({
        organization_id: profile?.organization_id,
        event_id: eventId,
        baseline_id: form.baseline_id || null,
        award_id: form.award_id || null,
        calculation_name: form.calculation_name,
        savings_type: form.savings_type,
        baseline_total_amount: baselineAmount,
        award_total_amount: awardAmount,
        gross_savings_amount: grossSavings,
        savings_percentage: Math.round(savingsPct * 100) / 100,
        net_savings_amount: grossSavings,
        created_by: user.id,
      })

    if (insertError) {
      setError(insertError.message)
      setLoading(false)
      return
    }
    onSaved()
  }

  const inputClass = 'mt-1 block w-full rounded-lg border border-gray-300 px-3 py-2 text-sm focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500'
  const labelClass = 'block text-xs font-medium text-gray-600'

  return (
    <form onSubmit={handleSubmit} className="mb-6 rounded-lg border border-indigo-200 bg-indigo-50 p-6">
      <h4 className="mb-4 font-medium text-gray-900">New Savings Calculation</h4>
      {error && <div className="mb-4 rounded bg-red-50 p-3 text-sm text-red-700">{error}</div>}
      <div className="grid grid-cols-1 gap-4 md:grid-cols-2">
        <div className="md:col-span-2">
          <label className={labelClass}>Calculation Name *</label>
          <input type="text" required value={form.calculation_name}
            onChange={(e) => setForm({ ...form, calculation_name: e.target.value })}
            className={inputClass} placeholder="e.g. Hard Savings - Current Contract vs Award" />
        </div>
        <div>
          <label className={labelClass}>Savings Type</label>
          <select value={form.savings_type}
            onChange={(e) => setForm({ ...form, savings_type: e.target.value })}
            className={inputClass}>
            {SAVINGS_TYPES.map((t) => <option key={t} value={t}>{t}</option>)}
          </select>
        </div>
        <div>
          <label className={labelClass}>Official Baseline *</label>
          <select required value={form.baseline_id}
            onChange={(e) => setForm({ ...form, baseline_id: e.target.value })}
            className={inputClass}>
            <option value="">Select baseline...</option>
            {baselines.map((b) => (
              <option key={b.id} value={b.id}>
                {b.baseline_name} ({formatCurrency(b.baseline_total_amount)})
                {b.official_for_hard_savings ? ' ★Hard$' : ''}
                {b.official_for_cost_avoidance ? ' ★Avoid' : ''}
              </option>
            ))}
          </select>
        </div>
        <div>
          <label className={labelClass}>Award</label>
          <select value={form.award_id}
            onChange={(e) => setForm({ ...form, award_id: e.target.value })}
            className={inputClass}>
            <option value="">Select award...</option>
            {awards.map((a) => (
              <option key={a.id} value={a.id}>
                {a.award_name} ({formatCurrency(a.award_total_amount)})
              </option>
            ))}
          </select>
        </div>
        {form.baseline_id && form.award_id && (
          <div className="md:col-span-2 rounded-lg bg-white p-4">
            <div className="flex items-center justify-around text-center">
              <div>
                <p className="text-xs text-gray-500">Baseline</p>
                <p className="text-lg font-bold text-gray-900">{formatCurrency(selectedBaseline?.baseline_total_amount || 0)}</p>
              </div>
              <TrendingDown className="h-6 w-6 text-gray-400" />
              <div>
                <p className="text-xs text-gray-500">Award</p>
                <p className="text-lg font-bold text-gray-900">
                  {formatCurrency(awards.find(a => a.id === form.award_id)?.award_total_amount || 0)}
                </p>
              </div>
              <div className="text-2xl font-bold text-gray-400">=</div>
              <div>
                <p className="text-xs text-gray-500">Gross Savings</p>
                <p className="text-lg font-bold text-green-600">
                  {formatCurrency(
                    (selectedBaseline?.baseline_total_amount || 0) -
                    (awards.find(a => a.id === form.award_id)?.award_total_amount || 0)
                  )}
                </p>
              </div>
            </div>
          </div>
        )}
      </div>
      <div className="mt-4 flex justify-end gap-2">
        <button type="button" onClick={onCancel}
          className="rounded-lg border border-gray-300 px-4 py-2 text-sm font-medium text-gray-700 hover:bg-gray-50">
          Cancel
        </button>
        <button type="submit" disabled={loading}
          className="rounded-lg bg-indigo-600 px-4 py-2 text-sm font-medium text-white hover:bg-indigo-700 disabled:opacity-50">
          {loading ? 'Creating...' : 'Create Calculation'}
        </button>
      </div>
    </form>
  )
}
EOF

# Create the realization tab component
cat > components/realization-tab.tsx << 'EOF'
'use client'

import { useState, useEffect, useCallback } from 'react'
import { createClient } from '@/lib/supabase/client'
import {
  TrendingUp, Plus, Trash2, CheckCircle, AlertTriangle,
  ShieldCheck, Clock,
} from 'lucide-react'
import { formatCurrency, formatDate } from '@/lib/utils'
import { clsx } from 'clsx'

const REALIZATION_STATUS_COLORS: Record<string, string> = {
  'Pending': 'bg-gray-100 text-gray-700',
  'In Progress': 'bg-blue-100 text-blue-700',
  'Realized': 'bg-green-100 text-green-700',
  'Partially Realized': 'bg-amber-100 text-amber-700',
  'Not Realized': 'bg-red-100 text-red-700',
  'Leaked': 'bg-red-100 text-red-700',
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
        .select('id, calculation_name, savings_type, gross_savings_amount')
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
      .eq('id', user.id)
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
    return <div className="p-8 text-center text-sm text-gray-500">Loading realization data...</div>
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
          <h3 className="text-lg font-semibold text-gray-900">Realization Tracking</h3>
          <p className="text-sm text-gray-600">Track actual savings vs projected savings over time</p>
        </div>
        <button
          onClick={() => setShowForm(!showForm)}
          className="flex items-center gap-2 rounded-lg bg-indigo-600 px-4 py-2 text-sm font-medium text-white hover:bg-indigo-700"
        >
          <Plus className="h-4 w-4" />
          Add Period
        </button>
      </div>

      {/* Summary Cards */}
      <div className="mb-4 grid grid-cols-2 gap-4 lg:grid-cols-4">
        <div className="rounded-lg border border-gray-200 bg-white p-4 shadow-sm">
          <p className="text-xs text-gray-500">Projected Savings</p>
          <p className="mt-1 text-xl font-bold text-gray-900">{formatCurrency(totalProjected)}</p>
        </div>
        <div className="rounded-lg border border-gray-200 bg-white p-4 shadow-sm">
          <p className="text-xs text-gray-500">Realized Savings</p>
          <p className="mt-1 text-xl font-bold text-green-600">{formatCurrency(totalRealized)}</p>
        </div>
        <div className="rounded-lg border border-gray-200 bg-white p-4 shadow-sm">
          <p className="text-xs text-gray-500">Leakage</p>
          <p className="mt-1 text-xl font-bold text-red-600">{formatCurrency(totalLeakage)}</p>
        </div>
        <div className="rounded-lg border border-gray-200 bg-white p-4 shadow-sm">
          <p className="text-xs text-gray-500">Realization Rate</p>
          <p className="mt-1 text-xl font-bold text-indigo-600">{realizationRate.toFixed(1)}%</p>
        </div>
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
        <div className="rounded-lg border border-gray-200 bg-white p-12 text-center shadow-sm">
          <TrendingUp className="mx-auto mb-3 h-10 w-10 text-gray-300" />
          <h3 className="text-sm font-medium text-gray-900">No realization periods yet</h3>
          <p className="mt-1 text-sm text-gray-500">Click "Add Period" to track savings over time.</p>
        </div>
      ) : (
        <div className="overflow-hidden rounded-lg border border-gray-200 bg-white shadow-sm">
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-gray-200 bg-gray-50 text-left text-xs uppercase text-gray-500">
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
              <tbody className="divide-y divide-gray-200">
                {periods.map((period) => (
                  <tr key={period.id} className="hover:bg-gray-50">
                    <td className="px-4 py-3">
                      <div className="text-sm font-medium text-gray-900">{period.period_name}</div>
                      <div className="text-xs text-gray-500">
                        {formatDate(period.period_start_date)} → {formatDate(period.period_end_date)}
                      </div>
                      {period.savings_calculation && (
                        <div className="text-xs text-gray-400">{period.savings_calculation.calculation_name}</div>
                      )}
                    </td>
                    <td className="px-4 py-3 text-right text-sm text-gray-700">
                      {formatCurrency(period.baseline_amount)}
                    </td>
                    <td className="px-4 py-3 text-right text-sm font-medium text-gray-900">
                      {formatCurrency(period.projected_savings)}
                    </td>
                    <td className="px-4 py-3 text-right">
                      <input
                        type="number"
                        step="0.01"
                        defaultValue={period.actual_amount || ''}
                        onBlur={(e) => updateActualAmount(period.id, e.target.value)}
                        placeholder="0"
                        className="w-28 rounded border border-gray-300 px-2 py-1 text-sm focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500"
                      />
                    </td>
                    <td className="px-4 py-3 text-right text-sm font-medium text-green-600">
                      {formatCurrency(period.realized_savings)}
                    </td>
                    <td className={clsx('px-4 py-3 text-right text-sm font-medium',
                      period.leakage_amount > 0 ? 'text-red-600' : 'text-gray-700'
                    )}>
                      {period.leakage_amount > 0 ? formatCurrency(period.leakage_amount) : '—'}
                    </td>
                    <td className="px-4 py-3 text-center">
                      <select
                        value={period.realization_status}
                        onChange={(e) => updateStatus(period.id, e.target.value)}
                        className={clsx('rounded-full border-0 px-2.5 py-1 text-xs font-medium',
                          REALIZATION_STATUS_COLORS[period.realization_status]
                        )}
                      >
                        {REALIZATION_STATUSES.map((s) => (
                          <option key={s} value={s}>{s}</option>
                        ))}
                      </select>
                    </td>
                    <td className="px-4 py-3 text-center">
                      <button onClick={() => toggleFinanceValidated(period)}
                        className={clsx(
                          'inline-flex items-center justify-center rounded-full p-1',
                          period.finance_validated
                            ? 'bg-emerald-100 text-emerald-600'
                            : 'bg-gray-100 text-gray-400 hover:bg-gray-200'
                        )}
                        title="Toggle Finance Validation"
                      >
                        {period.finance_validated ? <ShieldCheck className="h-4 w-4" /> : <Clock className="h-4 w-4" />}
                      </button>
                    </td>
                    <td className="px-4 py-3 text-right">
                      <button onClick={() => handleDelete(period.id)}
                        className="text-gray-400 hover:text-red-600">
                        <Trash2 className="h-4 w-4" />
                      </button>
                    </td>
                  </tr>
                ))}
              </tbody>
              <tfoot>
                <tr className="border-t-2 border-gray-200 bg-gray-50 font-semibold">
                  <td className="px-4 py-3 text-sm text-gray-900">Totals</td>
                  <td className="px-4 py-3"></td>
                  <td className="px-4 py-3 text-right text-sm text-gray-900">{formatCurrency(totalProjected)}</td>
                  <td className="px-4 py-3"></td>
                  <td className="px-4 py-3 text-right text-sm font-bold text-green-600">{formatCurrency(totalRealized)}</td>
                  <td className="px-4 py-3 text-right text-sm font-bold text-red-600">{formatCurrency(totalLeakage)}</td>
                  <td colSpan={3} className="px-4 py-3"></td>
                </tr>
              </tfoot>
            </table>
          </div>
        </div>
      )}

      {/* Info */}
      <div className="mt-4 rounded-lg border border-blue-200 bg-blue-50 p-4">
        <div className="flex items-start gap-3">
          <AlertTriangle className="mt-0.5 h-5 w-5 flex-shrink-0 text-blue-600" />
          <div>
            <h4 className="text-sm font-semibold text-blue-900">Realization Formula</h4>
            <p className="mt-1 text-xs text-blue-700">
              <strong>Realized Savings</strong> = Baseline − Actual Invoice Amount<br/>
              <strong>Leakage</strong> = Projected Savings − Realized Savings (if &gt; 0, savings leaked)<br/>
              Enter the actual invoice amount in the "Actual" column to auto-calculate realized savings and leakage.
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

  const inputClass = 'mt-1 block w-full rounded-lg border border-gray-300 px-3 py-2 text-sm focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500'
  const labelClass = 'block text-xs font-medium text-gray-600'

  return (
    <form onSubmit={(e) => { e.preventDefault(); onSaved(form) }}
      className="mb-6 rounded-lg border border-indigo-200 bg-indigo-50 p-6">
      <h4 className="mb-4 font-medium text-gray-900">New Realization Period</h4>
      <div className="grid grid-cols-1 gap-4 md:grid-cols-2">
        <div className="md:col-span-2">
          <label className={labelClass}>Period Name *</label>
          <input type="text" required value={form.period_name}
            onChange={(e) => setForm({ ...form, period_name: e.target.value })}
            className={inputClass} placeholder="e.g. Q1 FY2026 (Apr-Jun)" />
        </div>
        <div>
          <label className={labelClass}>Linked Calculation</label>
          <select value={form.savings_calculation_id}
            onChange={(e) => setForm({ ...form, savings_calculation_id: e.target.value })}
            className={inputClass}>
            <option value="">None</option>
            {calculations.map((c) => (
              <option key={c.id} value={c.id}>{c.calculation_name}</option>
            ))}
          </select>
        </div>
        <div></div>
        <div>
          <label className={labelClass}>Period Start Date *</label>
          <input type="date" required value={form.period_start_date}
            onChange={(e) => setForm({ ...form, period_start_date: e.target.value })}
            className={inputClass} />
        </div>
        <div>
          <label className={labelClass}>Period End Date *</label>
          <input type="date" required value={form.period_end_date}
            onChange={(e) => setForm({ ...form, period_end_date: e.target.value })}
            className={inputClass} />
        </div>
        <div>
          <label className={labelClass}>Baseline Amount *</label>
          <input type="number" step="0.01" required value={form.baseline_amount}
            onChange={(e) => setForm({ ...form, baseline_amount: e.target.value })}
            className={inputClass} placeholder="0.00" />
        </div>
        <div>
          <label className={labelClass}>Projected Savings *</label>
          <input type="number" step="0.01" required value={form.projected_savings}
            onChange={(e) => setForm({ ...form, projected_savings: e.target.value })}
            className={inputClass} placeholder="0.00" />
        </div>
      </div>
      <div className="mt-4 flex justify-end gap-2">
        <button type="button" onClick={onCancel}
          className="rounded-lg border border-gray-300 px-4 py-2 text-sm font-medium text-gray-700 hover:bg-gray-50">
          Cancel
        </button>
        <button type="submit"
          className="rounded-lg bg-indigo-600 px-4 py-2 text-sm font-medium text-white hover:bg-indigo-700">
          Add Period
        </button>
      </div>
    </form>
  )
}
EOF

# Update event-detail component to use the new tabs
cat > components/event-detail.tsx << 'EOF'
'use client'

import { useState } from 'react'
import {
  FileText, List, BarChart2, Users, FileCheck,
  Calculator, TrendingUp, FolderKanban, Clock, CheckCircle,
} from 'lucide-react'
import { clsx } from 'clsx'
import { formatDate, statusColor } from '@/lib/utils'
import { ScopeLinesTab } from './scope-lines-tab'
import { BaselinesTab } from './baselines-tab'
import { OffersTab } from './offers-tab'
import { CalculationsTab } from './calculations-tab'
import { RealizationTab } from './realization-tab'

type Event = {
  id: string
  event_name: string
  event_description: string | null
  event_type: string
  sourcing_method: string | null
  event_status: string
  event_start_date: string | null
  event_close_date: string | null
  contract_start_date: string | null
  contract_end_date: string | null
  recognition_start_date: string | null
  recognition_end_date: string | null
  official_reporting_basis: string | null
  currency_code: string
  category: { category_name: string } | null
  business_unit: { business_unit_name: string } | null
  cost_center: { cost_center_name: string } | null
  incumbent_supplier: { supplier_name: string } | null
  awarded_supplier: { supplier_name: string } | null
}

const TABS = [
  { id: 'overview', label: 'Overview', icon: FileText },
  { id: 'scope', label: 'Scope Lines', icon: List },
  { id: 'baselines', label: 'Baselines', icon: BarChart2 },
  { id: 'offers', label: 'Supplier Offers', icon: Users },
  { id: 'awards', label: 'Awards', icon: FileCheck },
  { id: 'calculations', label: 'Calculations', icon: Calculator },
  { id: 'realization', label: 'Realization', icon: TrendingUp },
]

export function EventDetail({
  event,
  scopeLines,
  suppliers,
}: {
  event: Event
  scopeLines: any[]
  suppliers: any[]
}) {
  const [activeTab, setActiveTab] = useState('overview')

  return (
    <div>
      <div className="mb-6">
        <div className="flex items-start justify-between">
          <div>
            <h1 className="text-2xl font-bold text-gray-900">{event.event_name}</h1>
            <p className="mt-1 text-sm text-gray-600">
              {event.event_type} • {event.sourcing_method || '—'}
            </p>
          </div>
          <span className={clsx('inline-flex rounded-full px-3 py-1 text-sm font-medium', statusColor(event.event_status))}>
            {event.event_status}
          </span>
        </div>
        {event.event_description && (
          <p className="mt-3 text-sm text-gray-600">{event.event_description}</p>
        )}
      </div>

      <div className="border-b border-gray-200">
        <nav className="flex gap-1 overflow-x-auto">
          {TABS.map((tab) => {
            const Icon = tab.icon
            return (
              <button key={tab.id} onClick={() => setActiveTab(tab.id)}
                className={clsx(
                  'flex items-center gap-2 border-b-2 px-4 py-3 text-sm font-medium transition-colors whitespace-nowrap',
                  activeTab === tab.id
                    ? 'border-indigo-600 text-indigo-600'
                    : 'border-transparent text-gray-500 hover:text-gray-700'
                )}>
                <Icon className="h-4 w-4" />
                {tab.label}
              </button>
            )
          })}
        </nav>
      </div>

      <div className="mt-6">
        {activeTab === 'overview' && <OverviewTab event={event} />}
        {activeTab === 'scope' && <ScopeLinesTab eventId={event.id} scopeLines={scopeLines} />}
        {activeTab === 'baselines' && <BaselinesTab eventId={event.id} scopeLines={scopeLines} />}
        {activeTab === 'offers' && <OffersTab eventId={event.id} scopeLines={scopeLines} suppliers={suppliers} />}
        {activeTab === 'awards' && <AwardsTab eventId={event.id} />}
        {activeTab === 'calculations' && <CalculationsTab eventId={event.id} />}
        {activeTab === 'realization' && <RealizationTab eventId={event.id} />}
      </div>
    </div>
  )
}

function OverviewTab({ event }: { event: Event }) {
  const details = [
    { label: 'Category', value: event.category?.category_name },
    { label: 'Business Unit', value: event.business_unit?.business_unit_name },
    { label: 'Cost Center', value: event.cost_center?.cost_center_name },
    { label: 'Incumbent Supplier', value: event.incumbent_supplier?.supplier_name },
    { label: 'Awarded Supplier', value: event.awarded_supplier?.supplier_name },
    { label: 'Currency', value: event.currency_code },
    { label: 'Reporting Basis', value: event.official_reporting_basis },
  ]

  const dates = [
    { label: 'Event Start', value: event.event_start_date },
    { label: 'Event Close', value: event.event_close_date },
    { label: 'Contract Start', value: event.contract_start_date },
    { label: 'Contract End', value: event.contract_end_date },
    { label: 'Recognition Start', value: event.recognition_start_date },
    { label: 'Recognition End', value: event.recognition_end_date },
  ]

  return (
    <div className="grid grid-cols-1 gap-6 md:grid-cols-2">
      <div className="rounded-lg border border-gray-200 bg-white p-6 shadow-sm">
        <h3 className="mb-4 text-sm font-semibold uppercase tracking-wider text-gray-500">Event Details</h3>
        <dl className="space-y-3">
          {details.map((d) => (
            <div key={d.label} className="flex justify-between">
              <dt className="text-sm text-gray-600">{d.label}</dt>
              <dd className="text-sm font-medium text-gray-900">{d.value || '—'}</dd>
            </div>
          ))}
        </dl>
      </div>
      <div className="rounded-lg border border-gray-200 bg-white p-6 shadow-sm">
        <h3 className="mb-4 text-sm font-semibold uppercase tracking-wider text-gray-500">Key Dates</h3>
        <dl className="space-y-3">
          {dates.map((d) => (
            <div key={d.label} className="flex justify-between">
              <dt className="flex items-center gap-2 text-sm text-gray-600">
                <Clock className="h-3 w-3" />
                {d.label}
              </dt>
              <dd className="text-sm font-medium text-gray-900">{formatDate(d.value)}</dd>
            </div>
          ))}
        </dl>
      </div>
    </div>
  )
}

function AwardsTab({ eventId }: { eventId: string }) {
  return (
    <div className="rounded-lg border border-gray-200 bg-white p-12 text-center shadow-sm">
      <FileCheck className="mx-auto mb-3 h-10 w-10 text-gray-300" />
      <h3 className="text-lg font-medium text-gray-900">Awards</h3>
      <p className="mt-1 text-sm text-gray-500">
        Create awards from the Supplier Offers tab by expanding an offer and clicking "Create Award from Offer."
      </p>
    </div>
  )
}
EOF

# Clear build cache
rm -rf .next

echo "DONE"
