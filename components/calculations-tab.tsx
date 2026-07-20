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
      .eq('id', user!.id)
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
