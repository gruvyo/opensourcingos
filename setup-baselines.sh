#!/bin/bash

# Create the baselines tab component
cat > components/baselines-tab.tsx << 'EOF'
'use client'

import { useState, useEffect, useCallback } from 'react'
import { createClient } from '@/lib/supabase/client'
import {
  Plus, Lock, FileCheck, Star, Trash2, ChevronDown,
  ChevronRight, AlertCircle, Shield, TrendingUp, Calculator
} from 'lucide-react'
import { formatCurrency, formatDate } from '@/lib/utils'
import { clsx } from 'clsx'

type Baseline = {
  id: string
  baseline_name: string
  baseline_type: string
  baseline_source: string | null
  baseline_period_start: string | null
  baseline_period_end: string | null
  baseline_total_amount: number
  baseline_normalized_amount: number
  baseline_lock_status: string
  baseline_lock_date: string | null
  official_for_hard_savings: boolean
  official_for_cost_avoidance: boolean
  official_for_demand_reduction: boolean
}

type ScopeLine = {
  id: string
  line_number: number
  item_service_name: string
  uom: string | null
}

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

const LOCK_STATUS_COLORS: Record<string, string> = {
  'Draft': 'bg-gray-100 text-gray-700',
  'Locked': 'bg-blue-100 text-blue-700',
  'Submitted': 'bg-amber-100 text-amber-700',
  'Approved': 'bg-green-100 text-green-700',
  'Rejected': 'bg-red-100 text-red-700',
}

export function BaselinesTab({ eventId, scopeLines }: { eventId: string; scopeLines: ScopeLine[] }) {
  const [baselines, setBaselines] = useState<Baseline[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [expandedId, setExpandedId] = useState<string | null>(null)
  const [baselineLines, setBaselineLines] = useState<Record<string, any[]>>({})
  const supabase = createClient()

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

  const updateLockStatus = async (baselineId: string, newStatus: string) => {
    const updates: any = { baseline_lock_status: newStatus }
    if (newStatus === 'Locked' || newStatus === 'Approved') {
      updates.baseline_lock_date = new Date().toISOString()
    }
    if (newStatus === 'Approved') {
      const { data: { user } } = await supabase.auth.getUser()
      if (user) updates.baseline_approved_by = user.id
      updates.baseline_approval_date = new Date().toISOString()
    }

    await supabase.from('baselines').update(updates).eq('id', baselineId)
    fetchBaselines()
  }

  const toggleOfficial = async (baseline: Baseline, field: 'official_for_hard_savings' | 'official_for_cost_avoidance' | 'official_for_demand_reduction') => {
    // Only approved baselines can be marked official
    if (baseline.baseline_lock_status !== 'Approved') return

    // Only one baseline can be official for each type — unset others first
    const others = baselines.filter(b => b.id !== baseline.id && b[field])
    for (const other of others) {
      await supabase.from('baselines').update({ [field]: false }).eq('id', other.id)
    }

    await supabase
      .from('baselines')
      .update({ [field]: !baseline[field] })
      .eq('id', baseline.id)
    fetchBaselines()
  }

  const handleDelete = async (baselineId: string) => {
    if (!confirm('Delete this baseline and all its lines? This cannot be undone.')) return
    await supabase.from('baselines').delete().eq('id', baselineId)
    setBaselines(baselines.filter(b => b.id !== baselineId))
  }

  if (loading) {
    return <div className="p-8 text-center text-sm text-gray-500">Loading baselines...</div>
  }

  return (
    <div>
      {/* Header */}
      <div className="mb-4 flex items-center justify-between">
        <div>
          <h3 className="text-lg font-semibold text-gray-900">Baselines</h3>
          <p className="text-sm text-gray-600">Establish what the company would have paid without procurement action</p>
        </div>
        <button
          onClick={() => setShowForm(!showForm)}
          className="flex items-center gap-2 rounded-lg bg-indigo-600 px-4 py-2 text-sm font-medium text-white hover:bg-indigo-700"
        >
          <Plus className="h-4 w-4" />
          Add Baseline
        </button>
      </div>

      {/* Baseline Hierarchy Info */}
      <div className="mb-4 rounded-lg border border-blue-200 bg-blue-50 p-4">
        <div className="flex items-start gap-3">
          <Shield className="mt-0.5 h-5 w-5 flex-shrink-0 text-blue-600" />
          <div>
            <h4 className="text-sm font-semibold text-blue-900">Baseline Defensibility Hierarchy</h4>
            <p className="mt-1 text-xs text-blue-700">
              Most defensible → Least defensible: Current Contract → Prior 12-Month Actual → Approved Budget → Supplier Renewal Quote → Competitive Bid → Market Index → Should-Cost Model → Initial Supplier Quote
            </p>
          </div>
        </div>
      </div>

      {/* Add Baseline Form */}
      {showForm && (
        <AddBaselineForm
          eventId={eventId}
          scopeLines={scopeLines}
          onSaved={() => { setShowForm(false); fetchBaselines() }}
          onCancel={() => setShowForm(false)}
        />
      )}

      {/* Baselines List */}
      {baselines.length === 0 ? (
        <div className="rounded-lg border border-gray-200 bg-white p-12 text-center shadow-sm">
          <Calculator className="mx-auto mb-3 h-10 w-10 text-gray-300" />
          <h3 className="text-sm font-medium text-gray-900">No baselines yet</h3>
          <p className="mt-1 text-sm text-gray-500">Click "Add Baseline" to establish the baseline for this event.</p>
        </div>
      ) : (
        <div className="space-y-3">
          {baselines.map((baseline) => {
            const isExpanded = expandedId === baseline.id
            const defensibility = BASELINE_TYPE_DEFENSIBILITY[baseline.baseline_type] || '—'
            const lines = baselineLines[baseline.id] || []

            return (
              <div key={baseline.id} className="overflow-hidden rounded-lg border border-gray-200 bg-white shadow-sm">
                {/* Baseline Header Row */}
                <div className="flex items-center gap-4 p-4">
                  <button onClick={() => toggleExpand(baseline.id)} className="text-gray-400 hover:text-gray-600">
                    {isExpanded ? <ChevronDown className="h-5 w-5" /> : <ChevronRight className="h-5 w-5" />}
                  </button>

                  <div className="flex-1">
                    <div className="flex items-center gap-2">
                      <h4 className="text-sm font-semibold text-gray-900">{baseline.baseline_name}</h4>
                      <span className="rounded bg-gray-100 px-2 py-0.5 text-xs text-gray-600">
                        {baseline.baseline_type}
                      </span>
                      <span className="rounded bg-blue-50 px-2 py-0.5 text-xs text-blue-600">
                        {defensibility} defensibility
                      </span>
                    </div>
                    {baseline.baseline_source && (
                      <p className="mt-1 text-xs text-gray-500">{baseline.baseline_source}</p>
                    )}
                  </div>

                  {/* Total Amount */}
                  <div className="text-right">
                    <p className="text-xs text-gray-500">Total Baseline</p>
                    <p className="text-lg font-bold text-gray-900">{formatCurrency(baseline.baseline_total_amount)}</p>
                  </div>

                  {/* Lock Status Badge */}
                  <span className={clsx('rounded-full px-2.5 py-1 text-xs font-medium', LOCK_STATUS_COLORS[baseline.baseline_lock_status])}>
                    {baseline.baseline_lock_status}
                  </span>

                  {/* Official badges */}
                  <div className="flex gap-1">
                    {baseline.official_for_hard_savings && (
                      <span className="flex items-center gap-1 rounded bg-green-100 px-2 py-1 text-xs font-medium text-green-700" title="Official for Hard Savings">
                        <Star className="h-3 w-3 fill-current" /> Hard $
                      </span>
                    )}
                    {baseline.official_for_cost_avoidance && (
                      <span className="flex items-center gap-1 rounded bg-purple-100 px-2 py-1 text-xs font-medium text-purple-700" title="Official for Cost Avoidance">
                        <Star className="h-3 w-3 fill-current" /> Avoid
                      </span>
                    )}
                    {baseline.official_for_demand_reduction && (
                      <span className="flex items-center gap-1 rounded bg-orange-100 px-2 py-1 text-xs font-medium text-orange-700" title="Official for Demand Reduction">
                        <Star className="h-3 w-3 fill-current" /> Demand
                      </span>
                    )}
                  </div>
                </div>

                {/* Expanded View */}
                {isExpanded && (
                  <div className="border-t border-gray-200 bg-gray-50">
                    {/* Actions Bar */}
                    <div className="flex flex-wrap items-center gap-2 border-b border-gray-200 bg-white px-4 py-3">
                      <span className="text-xs font-medium text-gray-500">Workflow:</span>
                      {baseline.baseline_lock_status === 'Draft' && (
                        <button onClick={() => updateLockStatus(baseline.id, 'Locked')}
                          className="flex items-center gap-1 rounded bg-blue-50 px-2.5 py-1 text-xs font-medium text-blue-700 hover:bg-blue-100">
                          <Lock className="h-3 w-3" /> Lock Baseline
                        </button>
                      )}
                      {baseline.baseline_lock_status === 'Locked' && (
                        <button onClick={() => updateLockStatus(baseline.id, 'Submitted')}
                          className="flex items-center gap-1 rounded bg-amber-50 px-2.5 py-1 text-xs font-medium text-amber-700 hover:bg-amber-100">
                          <FileCheck className="h-3 w-3" /> Submit for Approval
                        </button>
                      )}
                      {baseline.baseline_lock_status === 'Submitted' && (
                        <>
                          <button onClick={() => updateLockStatus(baseline.id, 'Approved')}
                            className="flex items-center gap-1 rounded bg-green-50 px-2.5 py-1 text-xs font-medium text-green-700 hover:bg-green-100">
                            <FileCheck className="h-3 w-3" /> Approve
                          </button>
                          <button onClick={() => updateLockStatus(baseline.id, 'Rejected')}
                            className="flex items-center gap-1 rounded bg-red-50 px-2.5 py-1 text-xs font-medium text-red-700 hover:bg-red-100">
                            Reject
                          </button>
                        </>
                      )}
                      {baseline.baseline_lock_status === 'Approved' && (
                        <div className="flex items-center gap-3">
                          <span className="text-xs font-medium text-gray-500">Mark Official:</span>
                          <button onClick={() => toggleOfficial(baseline, 'official_for_hard_savings')}
                            className={clsx(
                              'flex items-center gap-1 rounded px-2.5 py-1 text-xs font-medium',
                              baseline.official_for_hard_savings
                                ? 'bg-green-100 text-green-700'
                                : 'bg-gray-100 text-gray-600 hover:bg-gray-200'
                            )}>
                            <Star className="h-3 w-3" /> Hard Savings
                          </button>
                          <button onClick={() => toggleOfficial(baseline, 'official_for_cost_avoidance')}
                            className={clsx(
                              'flex items-center gap-1 rounded px-2.5 py-1 text-xs font-medium',
                              baseline.official_for_cost_avoidance
                                ? 'bg-purple-100 text-purple-700'
                                : 'bg-gray-100 text-gray-600 hover:bg-gray-200'
                            )}>
                            <Star className="h-3 w-3" /> Cost Avoidance
                          </button>
                          <button onClick={() => toggleOfficial(baseline, 'official_for_demand_reduction')}
                            className={clsx(
                              'flex items-center gap-1 rounded px-2.5 py-1 text-xs font-medium',
                              baseline.official_for_demand_reduction
                                ? 'bg-orange-100 text-orange-700'
                                : 'bg-gray-100 text-gray-600 hover:bg-gray-200'
                            )}>
                            <Star className="h-3 w-3" /> Demand Reduction
                          </button>
                        </div>
                      )}
                      <div className="ml-auto">
                        {baseline.baseline_lock_status === 'Draft' && (
                          <button onClick={() => handleDelete(baseline.id)}
                            className="text-gray-400 hover:text-red-600">
                            <Trash2 className="h-4 w-4" />
                          </button>
                        )}
                      </div>
                    </div>

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
              </div>
            )
          })}
        </div>
      )}
    </div>
  )
}

// ============================================
// Add Baseline Form
// ============================================
function AddBaselineForm({ eventId, scopeLines, onSaved, onCancel }: {
  eventId: string
  scopeLines: ScopeLine[]
  onSaved: () => void
  onCancel: () => void
}) {
  const supabase = createClient()
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [form, setForm] = useState({
    baseline_name: '',
    baseline_type: '',
    baseline_source: '',
    baseline_period_start: '',
    baseline_period_end: '',
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
      .eq('id', user.id)
      .single()

    const { error: insertError } = await supabase
      .from('baselines')
      .insert({
        organization_id: profile?.organization_id,
        event_id: eventId,
        baseline_name: form.baseline_name,
        baseline_type: form.baseline_type,
        baseline_source: form.baseline_source || null,
        baseline_period_start: form.baseline_period_start || null,
        baseline_period_end: form.baseline_period_end || null,
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
      <h4 className="mb-4 font-medium text-gray-900">New Baseline</h4>
      {error && <div className="mb-4 rounded bg-red-50 p-3 text-sm text-red-700">{error}</div>}
      <div className="grid grid-cols-1 gap-4 md:grid-cols-2">
        <div className="md:col-span-2">
          <label className={labelClass}>Baseline Name *</label>
          <input type="text" required value={form.baseline_name}
            onChange={(e) => setForm({ ...form, baseline_name: e.target.value })}
            className={inputClass} placeholder="e.g. Current Contract Baseline" />
        </div>
        <div>
          <label className={labelClass}>Baseline Type *</label>
          <select required value={form.baseline_type}
            onChange={(e) => setForm({ ...form, baseline_type: e.target.value })}
            className={inputClass}>
            <option value="">Select type...</option>
            {BASELINE_TYPES.map((t) => (
              <option key={t} value={t}>{t} ({BASELINE_TYPE_DEFENSIBILITY[t]})</option>
            ))}
          </select>
        </div>
        <div>
          <label className={labelClass}>Source</label>
          <input type="text" value={form.baseline_source}
            onChange={(e) => setForm({ ...form, baseline_source: e.target.value })}
            className={inputClass} placeholder="e.g. Existing contract rate card" />
        </div>
        <div>
          <label className={labelClass}>Period Start</label>
          <input type="date" value={form.baseline_period_start}
            onChange={(e) => setForm({ ...form, baseline_period_start: e.target.value })}
            className={inputClass} />
        </div>
        <div>
          <label className={labelClass}>Period End</label>
          <input type="date" value={form.baseline_period_end}
            onChange={(e) => setForm({ ...form, baseline_period_end: e.target.value })}
            className={inputClass} />
        </div>
      </div>
      <div className="mt-4 flex justify-end gap-2">
        <button type="button" onClick={onCancel}
          className="rounded-lg border border-gray-300 px-4 py-2 text-sm font-medium text-gray-700 hover:bg-gray-50">
          Cancel
        </button>
        <button type="submit" disabled={loading}
          className="rounded-lg bg-indigo-600 px-4 py-2 text-sm font-medium text-white hover:bg-indigo-700 disabled:opacity-50">
          {loading ? 'Creating...' : 'Create Baseline'}
        </button>
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
  lines: any[]
  onLinesChanged: () => void
  isLocked: boolean
}) {
  const supabase = createClient()
  const [lines, setLines] = useState(initialLines)
  const [showAddLine, setShowAddLine] = useState(false)
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

  const handleAddLine = async (e: React.FormEvent) => {
    e.preventDefault()

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
      .eq('id', user.id)
      .single()

    const lineNumber = lines.length + 1

    const { data, error } = await supabase
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

    if (!error && data) {
      setLines([...lines, data])
      setNewLine({
        scope_line_id: '', baseline_unit_price: '', baseline_quantity: '',
        baseline_term_months: '12', baseline_recurring_amount: '', baseline_one_time_amount: '',
      })
      setShowAddLine(false)
      onLinesChanged()
      // Update baseline total
      updateBaselineTotal()
    }
  }

  const handleDeleteLine = async (lineId: string) => {
    await supabase.from('baseline_lines').delete().eq('id', lineId)
    setLines(lines.filter(l => l.id !== lineId))
    onLinesChanged()
    updateBaselineTotal()
  }

  const updateBaselineTotal = async () => {
    const total = lines.reduce((sum, l) => sum + (l.baseline_extended_amount || 0), 0)
    await supabase.from('baselines').update({ baseline_total_amount: total }).eq('id', baselineId)
  }

  const inputClass = 'block w-full rounded border border-gray-300 px-2 py-1 text-xs focus:border-indigo-500 focus:outline-none'
  const labelClass = 'block text-xs font-medium text-gray-500 mb-1'

  const totalExtended = lines.reduce((sum, l) => sum + (l.baseline_extended_amount || 0), 0)
  const totalAnnualized = lines.reduce((sum, l) => sum + (l.annualized_baseline_amount || 0), 0)

  return (
    <div className="p-4">
      <div className="mb-3 flex items-center justify-between">
        <h5 className="text-sm font-medium text-gray-700">Baseline Lines</h5>
        {!isLocked && (
          <button onClick={() => setShowAddLine(!showAddLine)}
            className="flex items-center gap-1 rounded bg-white px-2.5 py-1 text-xs font-medium text-indigo-600 hover:bg-indigo-50">
            <Plus className="h-3 w-3" /> Add Line
          </button>
        )}
      </div>

      {/* Add Line Form */}
      {showAddLine && !isLocked && (
        <form onSubmit={handleAddLine} className="mb-4 rounded border border-indigo-200 bg-white p-4">
          <div className="grid grid-cols-1 gap-3 md:grid-cols-4">
            <div className="md:col-span-4">
              <label className={labelClass}>Scope Line (optional — link to existing scope)</label>
              <select value={newLine.scope_line_id}
                onChange={(e) => setNewLine({ ...newLine, scope_line_id: e.target.value })}
                className={inputClass}>
                <option value="">None</option>
                {scopeLines.map((sl) => (
                  <option key={sl.id} value={sl.id}>
                    {sl.line_number}. {sl.item_service_name} ({sl.uom || '—'})
                  </option>
                ))}
              </select>
            </div>
            <div>
              <label className={labelClass}>Unit Price</label>
              <input type="number" step="0.0001" required value={newLine.baseline_unit_price}
                onChange={(e) => setNewLine({ ...newLine, baseline_unit_price: e.target.value })}
                className={inputClass} placeholder="0.00" />
            </div>
            <div>
              <label className={labelClass}>Quantity</label>
              <input type="number" step="0.01" required value={newLine.baseline_quantity}
                onChange={(e) => setNewLine({ ...newLine, baseline_quantity: e.target.value })}
                className={inputClass} placeholder="0" />
            </div>
            <div>
              <label className={labelClass}>Term (months)</label>
              <input type="number" step="0.01" value={newLine.baseline_term_months}
                onChange={(e) => setNewLine({ ...newLine, baseline_term_months: e.target.value })}
                className={inputClass} placeholder="12" />
            </div>
            <div>
              <label className={labelClass}>Extended (auto)</label>
              <div className="rounded border border-gray-200 bg-gray-50 px-2 py-1 text-xs text-gray-700">
                {formatCurrency(calcExtended(
                  parseFloat(newLine.baseline_unit_price) || 0,
                  parseFloat(newLine.baseline_quantity) || 0
                ))}
              </div>
            </div>
            <div>
              <label className={labelClass}>One-Time Amount</label>
              <input type="number" step="0.01" value={newLine.baseline_one_time_amount}
                onChange={(e) => setNewLine({ ...newLine, baseline_one_time_amount: e.target.value })}
                className={inputClass} placeholder="0" />
            </div>
          </div>
          <div className="mt-3 flex justify-end gap-2">
            <button type="button" onClick={() => setShowAddLine(false)}
              className="rounded border border-gray-300 px-3 py-1 text-xs font-medium text-gray-700 hover:bg-gray-50">
              Cancel
            </button>
            <button type="submit"
              className="rounded bg-indigo-600 px-3 py-1 text-xs font-medium text-white hover:bg-indigo-700">
              Add Line
            </button>
          </div>
        </form>
      )}

      {/* Lines Table */}
      {lines.length === 0 ? (
        <p className="py-6 text-center text-xs text-gray-500">
          No baseline lines yet. {!isLocked && 'Click "Add Line" to add pricing.'}
        </p>
      ) : (
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b border-gray-200 text-left text-xs uppercase text-gray-500">
                <th className="px-2 py-2">#</th>
                <th className="px-2 py-2">Scope Line</th>
                <th className="px-2 py-2 text-right">Unit Price</th>
                <th className="px-2 py-2 text-right">Qty</th>
                <th className="px-2 py-2 text-right">Extended</th>
                <th className="px-2 py-2 text-right">Recurring</th>
                <th className="px-2 py-2 text-right">One-Time</th>
                <th className="px-2 py-2 text-right">Term (mo)</th>
                <th className="px-2 py-2 text-right">Annualized</th>
                {!isLocked && <th className="px-2 py-2"></th>}
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-100">
              {lines.map((line) => (
                <tr key={line.id} className="hover:bg-gray-50">
                  <td className="px-2 py-2 text-xs text-gray-500">{line.line_number}</td>
                  <td className="px-2 py-2 text-xs">
                    <div className="font-medium text-gray-900">
                      {line.scope_line?.item_service_name || '—'}
                    </div>
                    {line.scope_line?.uom && (
                      <div className="text-gray-500">{line.scope_line.uom}</div>
                    )}
                  </td>
                  <td className="px-2 py-2 text-right text-xs text-gray-700">
                    {line.baseline_unit_price ? formatCurrency(line.baseline_unit_price) : '—'}
                  </td>
                  <td className="px-2 py-2 text-right text-xs text-gray-700">{line.baseline_quantity ?? '—'}</td>
                  <td className="px-2 py-2 text-right text-xs font-medium text-gray-900">
                    {formatCurrency(line.baseline_extended_amount)}
                  </td>
                  <td className="px-2 py-2 text-right text-xs text-gray-700">
                    {formatCurrency(line.baseline_recurring_amount)}
                  </td>
                  <td className="px-2 py-2 text-right text-xs text-gray-700">
                    {formatCurrency(line.baseline_one_time_amount)}
                  </td>
                  <td className="px-2 py-2 text-right text-xs text-gray-700">{line.baseline_term_months ?? '—'}</td>
                  <td className="px-2 py-2 text-right text-xs font-medium text-indigo-700">
                    {formatCurrency(line.annualized_baseline_amount)}
                  </td>
                  {!isLocked && (
                    <td className="px-2 py-2 text-right">
                      <button onClick={() => handleDeleteLine(line.id)}
                        className="text-gray-400 hover:text-red-600">
                        <Trash2 className="h-3.5 w-3.5" />
                      </button>
                    </td>
                  )}
                </tr>
              ))}
            </tbody>
            <tfoot>
              <tr className="border-t-2 border-gray-200 bg-gray-50 font-medium">
                <td colSpan={4} className="px-2 py-2 text-right text-xs text-gray-600">Totals:</td>
                <td className="px-2 py-2 text-right text-xs font-bold text-gray-900">{formatCurrency(totalExtended)}</td>
                <td colSpan={2} className="px-2 py-2"></td>
                <td className="px-2 py-2 text-right text-xs text-gray-600">Annual:</td>
                <td className="px-2 py-2 text-right text-xs font-bold text-indigo-700">{formatCurrency(totalAnnualized)}</td>
                {!isLocked && <td className="px-2 py-2"></td>}
              </tr>
            </tfoot>
          </table>
        </div>
      )}
    </div>
  )
}
EOF

# Update event-detail.tsx to use the baselines tab
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
  { id: 'contracts', label: 'Contracts', icon: FolderKanban },
  { id: 'calculations', label: 'Calculations', icon: Calculator },
  { id: 'realization', label: 'Realization', icon: TrendingUp },
]

export function EventDetail({ event, scopeLines }: { event: Event; scopeLines: any[] }) {
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
        {activeTab === 'offers' && <PlaceholderTab label="Supplier Offers" message="Supplier offers will be built in Phase 4." />}
        {activeTab === 'awards' && <PlaceholderTab label="Awards" message="Awards will be built in Phase 4." />}
        {activeTab === 'contracts' && <PlaceholderTab label="Contracts" message="Contracts will be built in a future phase." />}
        {activeTab === 'calculations' && <PlaceholderTab label="Calculations" message="Savings calculations will be built in Phase 5." />}
        {activeTab === 'realization' && <PlaceholderTab label="Realization" message="Realization tracking will be built in Phase 5." />}
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

function PlaceholderTab({ label, message }: { label: string; message: string }) {
  return (
    <div className="rounded-lg border border-gray-200 bg-white p-12 text-center shadow-sm">
      <CheckCircle className="mx-auto mb-3 h-10 w-10 text-gray-300" />
      <h3 className="text-lg font-medium text-gray-900">{label}</h3>
      <p className="mt-1 text-sm text-gray-500">{message}</p>
    </div>
  )
}
EOF

# Clear build cache
rm -rf .next

echo "DONE"
