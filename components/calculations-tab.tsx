'use client'

import { useState, useEffect, useCallback } from 'react'
import { createClient } from '@/lib/supabase/client'
import {
  Calculator, Plus, Trash2, ChevronDown, ChevronRight,
  FileCheck, TrendingDown, ArrowRight,
} from 'lucide-react'
import { formatCurrency, formatDate } from '@/lib/utils'
import { chainSavings } from '@/lib/savings'
import { clsx } from 'clsx'
import { Card } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input, Select } from '@/components/ui/input'

const SAVINGS_TYPES = [
  'Cost Reduction', 'Cost Avoidance', 'Demand Reduction',
  'TCO Improvement', 'Working Capital',
]

const CALC_STATUS_COLORS: Record<string, string> = {
  'identified': 'bg-gray-100 text-gray-700 dark:bg-gray-700 dark:text-gray-300',
  'negotiated': 'bg-amber-100 text-amber-700 dark:bg-amber-900/30 dark:text-amber-300',
  'contracted': 'bg-indigo-100 text-indigo-700 dark:bg-indigo-900/30 dark:text-indigo-300',
  'realized': 'bg-green-100 text-green-700 dark:bg-green-900/30 dark:text-green-300',
}

export function CalculationsTab({ eventId }: { eventId: string }) {
  const [calculations, setCalculations] = useState<any[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [expandedId, setExpandedId] = useState<string | null>(null)
  const [calcLines, setCalcLines] = useState<Record<string, any[]>>({})
  const [baselines, setBaselines] = useState<any[]>([])
  const [awards, setAwards] = useState<any[]>([])
  const [eventDates, setEventDates] = useState<{ contract_start_date: string | null; contract_end_date: string | null }>({
    contract_start_date: null,
    contract_end_date: null,
  })
  const [openingOffer, setOpeningOffer] = useState<any | null>(null)
  const supabase = createClient()

  const fetchCalculations = useCallback(async () => {
    const { data } = await supabase
      .from('savings_calculations')
      .select(`*, baseline:baselines(baseline_name), award:awards(award_name)`)
      .eq('event_id', eventId)
      .order('created_at', { ascending: true })
    setCalculations(data || [])
    setLoading(false)
  }, [eventId, supabase])

  const fetchBaselinesAndAwards = useCallback(async () => {
    // NOTE: contract_start_date / contract_end_date live on sourcing_events, NOT on awards.
    // Selecting them from `awards` made PostgREST return 400 ("column awards.contract_start_date
    // does not exist"), which left the award list empty — so the award picker never populated and
    // a saved calculation booked 100% of the baseline as savings. Fetch the dates from the event.
    const [{ data: baseData }, { data: awardData }, { data: eventData }, { data: offerData }] = await Promise.all([
      supabase.from('baselines').select('id, baseline_name, baseline_total_amount, official_for_hard_savings, official_for_cost_avoidance, baseline_lock_status').eq('event_id', eventId),
      supabase.from('awards').select('id, award_name, award_total_amount, award_status, award_date').eq('event_id', eventId),
      supabase.from('sourcing_events').select('contract_start_date, contract_end_date').eq('id', eventId).maybeSingle(),
      // The opening proposal is normally already captured on the Offers tab as the
      // first round. Offer it as a one-click default for the Opening field.
      supabase.from('supplier_offers').select('id, offer_total_amount, offer_type, offer_round').eq('event_id', eventId).order('offer_round', { ascending: true }),
    ])
    setBaselines(baseData || [])
    setAwards(awardData || [])
    setOpeningOffer(
      (offerData || []).find((o: any) => o.offer_type === 'Initial') ?? (offerData || [])[0] ?? null
    )
    setEventDates({
      contract_start_date: eventData?.contract_start_date ?? null,
      contract_end_date: eventData?.contract_end_date ?? null,
    })
  }, [eventId, supabase])

  useEffect(() => {
    fetchCalculations()
    fetchBaselinesAndAwards()
  }, [fetchCalculations, fetchBaselinesAndAwards])

  const fetchCalcLines = async (calcId: string) => {
    if (calcLines[calcId]) return
    const { data } = await supabase
      .from('savings_calculation_lines')
      .select(`*, scope_line:event_scope_lines(item_service_name, uom)`)
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

  const handleDelete = async (calcId: string) => {
    if (!confirm('Delete this savings calculation?')) return
    await supabase.from('savings_calculations').delete().eq('id', calcId)
    setCalculations(calculations.filter(c => c.id !== calcId))
  }

  if (loading) {
    return <div className="p-8 text-center text-sm text-[var(--text-3)]">Loading calculations...</div>
  }

  return (
    <div>
      <div className="mb-4 flex items-center justify-between">
        <div>
          <h3 className="text-lg font-semibold text-[var(--text)]">Savings Calculations</h3>
          <p className="text-sm text-[var(--text-2)]">Cost reduction and cost avoidance calculations</p>
        </div>
        <Button onClick={() => setShowForm(!showForm)}>
          <Plus className="h-4 w-4" />
          Add Calculation
        </Button>
      </div>

      <div className="mb-4 rounded-lg border border-blue-200 bg-blue-50 p-4 dark:border-blue-800 dark:bg-blue-900/20">
        <div className="flex items-start gap-3">
          <Calculator className="mt-0.5 h-5 w-5 flex-shrink-0 text-blue-600 dark:text-blue-400" />
          <div>
            <h4 className="text-sm font-semibold text-blue-900 dark:text-blue-300">Savings Formula</h4>
            <p className="mt-1 text-xs text-blue-700 dark:text-blue-400">
              <strong>Gross Savings</strong> = Baseline − Award Amount<br/>
              <strong>Savings %</strong> = (Gross Savings / Baseline) × 100<br/>
              <strong>Cost Reduction</strong> = Actual bottom-line reduction (price went down)<br/>
              <strong>Cost Avoidance</strong> = Value received at no cost (e.g. extra licenses included)
            </p>
          </div>
        </div>
      </div>

      {showForm && (
        <AddCalculationForm
          eventId={eventId}
          baselines={baselines}
          awards={awards}
          eventDates={eventDates}
          openingOffer={openingOffer}
          onSaved={() => { setShowForm(false); fetchCalculations() }}
          onCancel={() => setShowForm(false)}
        />
      )}

      {calculations.length === 0 ? (
        <Card className="p-12 text-center">
          <Calculator className="mx-auto mb-3 h-10 w-10 text-[var(--text-3)]" />
          <h3 className="text-sm font-medium text-[var(--text)]">No savings calculations yet</h3>
          <p className="mt-1 text-sm text-[var(--text-3)]">Click &quot;Add Calculation&quot; to calculate savings.</p>
        </Card>
      ) : (
        <div className="space-y-3">
          {calculations.map((calc) => {
            const isExpanded = expandedId === calc.id
            const lines = calcLines[calc.id] || []
            const isNegative = (calc.gross_savings_amount || 0) < 0

            return (
              <Card key={calc.id} className="overflow-hidden">
                <div className="flex items-center gap-4 p-4">
                  <button onClick={() => toggleExpand(calc.id)} className="text-[var(--text-3)] hover:text-[var(--text-2)]">
                    {isExpanded ? <ChevronDown className="h-5 w-5" /> : <ChevronRight className="h-5 w-5" />}
                  </button>

                  <div className="flex-1">
                    <div className="flex items-center gap-2">
                      <h4 className="text-sm font-semibold text-[var(--text)]">{calc.calculation_name}</h4>
                      <span className={clsx('rounded px-2 py-0.5 text-xs font-medium',
                        calc.savings_type === 'Cost Reduction' ? 'bg-green-100 text-green-700 dark:bg-green-900/30 dark:text-green-300' :
                        calc.savings_type === 'Cost Avoidance' ? 'bg-purple-100 text-purple-700 dark:bg-purple-900/30 dark:text-purple-300' :
                        calc.savings_type === 'Demand Reduction' ? 'bg-orange-100 text-orange-700 dark:bg-orange-900/30 dark:text-orange-300' :
                        'bg-blue-100 text-blue-700 dark:bg-blue-900/30 dark:text-blue-300'
                      )}>
                        {calc.savings_type}
                      </span>
                    </div>
                    <p className="mt-1 text-xs text-[var(--text-3)]">
                      Baseline: {calc.baseline?.baseline_name || '—'} • Award: {calc.award?.award_name || '—'}
                    </p>
                  </div>

                  <div className="text-right">
                    <p className="text-xs text-[var(--text-3)]">Gross Savings</p>
                    <p className={clsx('text-lg font-bold', isNegative ? 'text-red-600 dark:text-red-400' : 'text-green-600 dark:text-green-400')}>
                      {isNegative ? '-' : ''}{formatCurrency(Math.abs(calc.gross_savings_amount || 0))}
                    </p>
                    <p className="text-xs text-[var(--text-3)]">{calc.savings_percentage?.toFixed(1)}%</p>
                  </div>

                  <span className={clsx('rounded-full px-2.5 py-1 text-xs font-medium',
                    CALC_STATUS_COLORS[calc.calculation_status] || 'bg-gray-100 text-gray-700 dark:bg-gray-700 dark:text-gray-300'
                  )}>
                    {calc.calculation_status}
                  </span>
                </div>

                {isExpanded && (
                  <div className="border-t border-[var(--border)] bg-[var(--surface-2)]">
                    <div className="grid grid-cols-4 gap-px border-b border-[var(--border)] bg-[var(--border)]">
                      <div className="bg-[var(--surface)] px-4 py-3">
                        <p className="text-xs text-[var(--text-3)]">Baseline Total</p>
                        <p className="text-sm font-semibold text-[var(--text)]">{formatCurrency(calc.baseline_total_amount)}</p>
                      </div>
                      <div className="bg-[var(--surface)] px-4 py-3">
                        <p className="text-xs text-[var(--text-3)]">Award Total</p>
                        <p className="text-sm font-semibold text-[var(--text)]">{formatCurrency(calc.award_total_amount)}</p>
                      </div>
                      <div className="bg-[var(--surface)] px-4 py-3">
                        <p className="text-xs text-[var(--text-3)]">Gross Savings</p>
                        <p className={clsx('text-sm font-semibold', isNegative ? 'text-red-600 dark:text-red-400' : 'text-green-600 dark:text-green-400')}>
                          {formatCurrency(calc.gross_savings_amount)}
                        </p>
                      </div>
                      <div className="bg-[var(--surface)] px-4 py-3">
                        <p className="text-xs text-[var(--text-3)]">Savings Period</p>
                        <p className="text-sm font-semibold text-[var(--text)]">
                          {calc.savings_start_date ? formatDate(calc.savings_start_date) : '—'} – {calc.savings_end_date ? formatDate(calc.savings_end_date) : '—'}
                        </p>
                      </div>
                    </div>

                    <div className="flex flex-wrap items-center gap-2 border-b border-[var(--border)] bg-[var(--surface)] px-4 py-3">
                      <span className="text-xs font-medium text-[var(--text-3)]">Workflow:</span>
                      <Select
                        value={calc.calculation_status || 'identified'}
                        onChange={(e) => updateStatus(calc.id, e.target.value)}
                        className="px-2.5 py-1 text-xs font-medium"
                      >
                        <option value="identified">Identified</option>
                        <option value="negotiated">Negotiated</option>
                        <option value="contracted">Contracted</option>
                        <option value="realized">Realized</option>
                      </Select>
                      <button onClick={() => handleDelete(calc.id)}
                        className="ml-auto text-[var(--text-3)] hover:text-red-600 dark:hover:text-red-400">
                        <Trash2 className="h-4 w-4" />
                      </button>
                    </div>

                    <div className="p-4">
                      <h5 className="mb-3 text-sm font-medium text-[var(--text-2)]">Line-Level Savings Breakdown</h5>
                      {lines.length === 0 ? (
                        <p className="py-6 text-center text-xs text-[var(--text-3)]">
                          No line-level breakdown available. Add savings calculation lines for detailed tracking.
                        </p>
                      ) : (
                        <div className="overflow-x-auto">
                          <table className="w-full text-sm">
                            <thead>
                              <tr className="border-b border-[var(--border)] text-left text-xs uppercase text-[var(--text-3)]">
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
                            <tbody className="divide-y divide-[var(--border)]">
                              {lines.map((line) => (
                                <tr key={line.id} className="hover:bg-[var(--surface-2)]">
                                  <td className="px-2 py-2 text-xs text-[var(--text-3)]">{line.line_number}</td>
                                  <td className="px-2 py-2 text-xs font-medium text-[var(--text)]">
                                    {line.scope_line?.item_service_name || '—'}
                                  </td>
                                  <td className="px-2 py-2 text-right text-xs text-[var(--text-2)]">{formatCurrency(line.baseline_unit_price)}</td>
                                  <td className="px-2 py-2 text-right text-xs text-[var(--text-2)]">{formatCurrency(line.baseline_extended_amount)}</td>
                                  <td className="px-2 py-2 text-right text-xs text-[var(--text-2)]">{formatCurrency(line.awarded_unit_price)}</td>
                                  <td className="px-2 py-2 text-right text-xs text-[var(--text-2)]">{formatCurrency(line.awarded_extended_amount)}</td>
                                  <td className={clsx('px-2 py-2 text-right text-xs font-medium',
                                    line.savings_amount < 0 ? 'text-red-600 dark:text-red-400' : 'text-green-600 dark:text-green-400'
                                  )}>{formatCurrency(line.savings_amount)}</td>
                                  <td className="px-2 py-2 text-right text-xs text-[var(--text-2)]">{line.savings_percentage?.toFixed(1)}%</td>
                                </tr>
                              ))}
                            </tbody>
                            <tfoot>
                              <tr className="border-t-2 border-[var(--border)] bg-[var(--surface-2)] font-medium">
                                <td colSpan={6} className="px-2 py-2 text-right text-xs text-[var(--text-2)]">Total Savings:</td>
                                <td className={clsx('px-2 py-2 text-right text-xs font-bold',
                                  isNegative ? 'text-red-600 dark:text-red-400' : 'text-green-600 dark:text-green-400'
                                )}>{formatCurrency(calc.gross_savings_amount)}</td>
                                <td className="px-2 py-2 text-right text-xs text-[var(--text-2)]">{calc.savings_percentage?.toFixed(1)}%</td>
                              </tr>
                            </tfoot>
                          </table>
                        </div>
                      )}
                    </div>
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

// ============================================
// Add Calculation Form
// ============================================
function AddCalculationForm({ eventId, baselines, awards, eventDates, openingOffer, onSaved, onCancel }: {
  eventId: string
  baselines: any[]
  awards: any[]
  eventDates: { contract_start_date: string | null; contract_end_date: string | null }
  openingOffer: any | null
  onSaved: () => void
  onCancel: () => void
}) {
  const supabase = createClient()
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [form, setForm] = useState({
    calculation_name: '',
    savings_type: 'Cost Reduction',
    baseline_id: '',
    award_id: '',
    opening_proposal_amount: '',
    baseline_amount: '',
    final_amount: '',
    savings_start_date: '',
    savings_end_date: '',
  })

  // THE CHAIN: Opening -> Baseline -> Final. The three typed amounts ARE the
  // calculation; linking a baseline/award record only pre-fills them. Reduction
  // and Avoidance are derived, never typed, so they sum to the total exactly.
  const chain = chainSavings({
    opening: form.opening_proposal_amount === '' ? null : form.opening_proposal_amount,
    baseline: form.baseline_amount === '' ? null : form.baseline_amount,
    final: form.final_amount === '' ? 0 : form.final_amount,
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

    const baselineAmount = form.baseline_amount === '' ? null : parseFloat(form.baseline_amount)
    const awardAmount = form.final_amount === '' ? 0 : parseFloat(form.final_amount)
    const openingAmount = form.opening_proposal_amount === '' ? null : parseFloat(form.opening_proposal_amount)

    // Derive the three figures from the chain. They are never hand-typed, so
    // reduction + avoidance === total by construction.
    const { reduction, avoidance, total } = chainSavings({
      opening: openingAmount,
      baseline: baselineAmount,
      final: awardAmount,
    })

    // Savings % denominator is the baseline when there is one, else the opening.
    // Never the award. Returns 0 when there is no meaningful denominator.
    const denominator = baselineAmount ?? openingAmount ?? 0
    const savingsPct = denominator > 0 ? (total / denominator) * 100 : 0

    // gross_savings_amount carries THE CHAIN TOTAL, so every existing card,
    // table, chart and export reports the headline without further change.
    const grossSavings = total
    const costReduction = reduction
    const costAvoidance = avoidance

    // Fall back to the event's contract dates for the savings period (they live on
    // sourcing_events, not awards). Keeps prorateByYear and the Realized/Accrued
    // classification working when the user leaves the period blank.
    const savingsStart = form.savings_start_date || eventDates.contract_start_date || null
    const savingsEnd = form.savings_end_date || eventDates.contract_end_date || null

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
        opening_proposal_amount: openingAmount,
        award_total_amount: awardAmount,
        gross_savings_amount: grossSavings,
        savings_percentage: Math.round(savingsPct * 100) / 100,
        net_savings_amount: grossSavings,
        cost_reduction_amount: costReduction,
        cost_avoidance_amount: costAvoidance,
        savings_start_date: savingsStart,
        savings_end_date: savingsEnd,
        calculation_status: 'identified',
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
    <form onSubmit={handleSubmit} className="mb-6 rounded-lg border border-indigo-200 bg-indigo-50 p-6 dark:border-indigo-800 dark:bg-indigo-900/20">
      <h4 className="mb-4 font-medium text-[var(--text)]">New Savings Calculation</h4>
      {error && <div className="mb-4 rounded bg-red-50 p-3 text-sm text-red-700 dark:bg-red-900/20 dark:text-red-400">{error}</div>}
      <div className="grid grid-cols-1 gap-4 md:grid-cols-2">
        <div className="md:col-span-2">
          <label className={labelClass}>Calculation Name *</label>
          <Input type="text" required value={form.calculation_name}
            onChange={(e) => setForm({ ...form, calculation_name: e.target.value })}
            className="mt-1" placeholder="e.g. Cost Reduction — Unit Price Negotiation" />
        </div>
        <div>
          <label className={labelClass}>Savings Type</label>
          <Select value={form.savings_type}
            onChange={(e) => setForm({ ...form, savings_type: e.target.value })}
            className="mt-1">
            {SAVINGS_TYPES.map((t) => <option key={t} value={t}>{t}</option>)}
          </Select>
        </div>
        <div>
          <label className={labelClass}>Link a baseline record (optional)</label>
          <Select value={form.baseline_id}
            onChange={(e) => {
              const b = baselines.find(x => x.id === e.target.value)
              setForm({
                ...form,
                baseline_id: e.target.value,
                // Pre-fill the amount from the linked record; still editable.
                baseline_amount: b ? String(b.baseline_total_amount ?? '') : form.baseline_amount,
              })
            }}
            className="mt-1">
            <option value="">Not linked — I&apos;ll type the amount</option>
            {baselines.map((b) => (
              <option key={b.id} value={b.id}>
                {b.baseline_name} ({formatCurrency(b.baseline_total_amount)})
              </option>
            ))}
          </Select>
        </div>
        <div>
          <label className={labelClass}>Link an award record (optional)</label>
          <Select value={form.award_id}
            onChange={(e) => {
              const a = awards.find(x => x.id === e.target.value)
              setForm({
                ...form,
                award_id: e.target.value,
                final_amount: a ? String(a.award_total_amount ?? '') : form.final_amount,
              })
            }}
            className="mt-1">
            <option value="">Not linked — I&apos;ll type the amount</option>
            {awards.map((a) => (
              <option key={a.id} value={a.id}>
                {a.award_name} ({formatCurrency(a.award_total_amount)})
              </option>
            ))}
          </Select>
        </div>

        {/* THE THREE ANCHORS. Type them directly — linking records above just
            pre-fills these. This is the whole calculation. */}
        <div className="md:col-span-2 rounded-lg border border-[var(--border-strong)] bg-[var(--surface)] p-4">
          <p className="mb-3 text-sm font-semibold text-[var(--text)]">The three anchors</p>
          <div className="grid grid-cols-1 gap-3 md:grid-cols-3">
            <div>
              <label className={labelClass}>Opening proposal ($)</label>
              <Input type="number" step="0.01" value={form.opening_proposal_amount}
                onChange={(e) => setForm({ ...form, opening_proposal_amount: e.target.value })}
                className="mt-1" placeholder="vendor's first ask" />
              <p className="mt-1 text-[11px] text-[var(--text-3)]">
                Blank = not captured.
                {openingOffer != null && (
                  <button type="button"
                    onClick={() => setForm({ ...form, opening_proposal_amount: String(openingOffer.offer_total_amount ?? '') })}
                    className="ml-1 font-medium text-[var(--brand-ink)] hover:underline">
                    use {formatCurrency(openingOffer.offer_total_amount)}
                  </button>
                )}
              </p>
            </div>
            <div>
              <label className={labelClass}>Baseline / current spend ($)</label>
              <Input type="number" step="0.01" value={form.baseline_amount}
                onChange={(e) => setForm({ ...form, baseline_amount: e.target.value })}
                className="mt-1" placeholder="what you pay today" />
              <p className="mt-1 text-[11px] text-[var(--text-3)]">Blank = no baseline anchor.</p>
            </div>
            <div>
              <label className={labelClass}>Final offer ($) *</label>
              <Input type="number" step="0.01" required value={form.final_amount}
                onChange={(e) => setForm({ ...form, final_amount: e.target.value })}
                className="mt-1" placeholder="what you signed" />
              <p className="mt-1 text-[11px] text-[var(--text-3)]">What you actually committed to.</p>
            </div>
          </div>
        </div>
        <div>
          <label className={labelClass}>Savings Start Date</label>
          <Input type="date" value={form.savings_start_date}
            onChange={(e) => setForm({ ...form, savings_start_date: e.target.value })}
            className="mt-1" />
        </div>
        <div>
          <label className={labelClass}>Savings End Date</label>
          <Input type="date" value={form.savings_end_date}
            onChange={(e) => setForm({ ...form, savings_end_date: e.target.value })}
            className="mt-1" />
        </div>
        {form.final_amount !== '' && (
          <div className="md:col-span-2 rounded-lg border border-[var(--border)] bg-[var(--surface)] p-4">
            {/* The chain, left to right, exactly as the methodology states it. */}
            <div className="mb-3 flex flex-wrap items-center justify-around gap-2 text-center">
              <div>
                <p className="text-xs text-[var(--text-3)]">Opening proposal</p>
                <p className="text-base font-bold text-[var(--text)]">
                  {form.opening_proposal_amount === ''
                    ? <span className="text-[var(--text-3)]">not captured</span>
                    : formatCurrency(Number(form.opening_proposal_amount))}
                </p>
              </div>
              <ArrowRight className="h-4 w-4 text-[var(--text-3)]" />
              <div>
                <p className="text-xs text-[var(--text-3)]">Baseline (current spend)</p>
                <p className="text-base font-bold text-[var(--text)]">
                  {form.baseline_amount === ''
                    ? <span className="text-[var(--text-3)]">no baseline</span>
                    : formatCurrency(Number(form.baseline_amount))}
                </p>
              </div>
              <ArrowRight className="h-4 w-4 text-[var(--text-3)]" />
              <div>
                <p className="text-xs text-[var(--text-3)]">Final offer</p>
                <p className="text-base font-bold text-[var(--text)]">
                  {formatCurrency(Number(form.final_amount))}
                </p>
              </div>
            </div>

            <div className="grid grid-cols-3 gap-3 border-t border-[var(--border)] pt-3 text-center">
              <div>
                <p className="text-xs text-[var(--text-3)]">Cost Reduction</p>
                <p className={clsx('text-base font-bold',
                  chain.reduction === null ? 'text-[var(--text-3)]'
                    : chain.reduction < 0 ? 'text-red-600 dark:text-red-400'
                    : 'text-[var(--text)]')}>
                  {chain.reduction === null
                    ? 'n/a'
                    : chain.reduction < 0
                      ? `(${formatCurrency(Math.abs(chain.reduction))})`
                      : formatCurrency(chain.reduction)}
                </p>
                <p className="text-[10px] text-[var(--text-3)]">Baseline − Final · hard</p>
              </div>
              <div>
                <p className="text-xs text-[var(--text-3)]">Cost Avoidance</p>
                <p className="text-base font-bold text-[var(--text)]">{formatCurrency(chain.avoidance)}</p>
                <p className="text-[10px] text-[var(--text-3)]">Opening − Baseline · soft</p>
              </div>
              <div>
                <p className="text-xs text-[var(--text-3)]">Total performance</p>
                <p className="text-lg font-bold text-green-600 dark:text-green-400">{formatCurrency(chain.total)}</p>
                <p className="text-[10px] text-[var(--text-3)]">Opening − Final · the headline</p>
              </div>
            </div>

            {chain.reduction === null && form.opening_proposal_amount !== '' && (
              <p className="mt-2 text-xs text-[var(--text-3)]">
                No baseline anchor, so the whole span books as avoidance and Cost Reduction is
                not applicable.
              </p>
            )}
            {form.opening_proposal_amount === '' && form.baseline_id && (
              <p className="mt-2 text-xs text-[var(--text-3)]">
                No opening captured, so Total collapses to Cost Reduction.
              </p>
            )}
            {chain.reduction !== null && chain.reduction < 0 && (
              <p className="mt-2 text-xs text-amber-600 dark:text-amber-400">
                This is a genuine cost increase against the baseline, shown in parentheses. It is
                not relabelled as savings.
              </p>
            )}
          </div>
        )}
      </div>
      <div className="mt-4 flex justify-end gap-2">
        <Button type="button" variant="secondary" onClick={onCancel}>
          Cancel
        </Button>
        <Button type="submit" disabled={loading}>
          {loading ? 'Creating...' : 'Create Calculation'}
        </Button>
      </div>
    </form>
  )
}