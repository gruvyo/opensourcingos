'use client'

import { useState, useEffect, useCallback } from 'react'
import { createClient } from '@/lib/supabase/client'
import {
  Plus, Trash2, ChevronDown, ChevronRight, CheckCircle, XCircle,
  Award, GitCompare, Users, FileText, Pencil
} from 'lucide-react'
import { formatCurrency, formatDate } from '@/lib/utils'
import { grossSavings, savingsPct as savingsPctOf } from '@/lib/savings'
import { clsx } from 'clsx'
import { Card } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { Input, Select } from '@/components/ui/input'

type Supplier = { id: string; supplier_name: string }

type Offer = {
  id: string
  supplier_id: string
  offer_type: string
  offer_round: number
  offer_date: string | null
  offer_total_amount: number
  offer_valid_until: string | null
  compliant_bid_flag: boolean
  selected_for_award_flag: boolean
  notes: string | null
  supplier: { supplier_name: string } | null
}

type ScopeLine = {
  id: string
  line_number: number
  item_service_name: string
  uom: string | null
}

const OFFER_TYPES = ['Initial', 'Revised', 'Best and Final (BAFO)', 'Counter', 'Final']
const COMPLIANCE_STATUS_COLORS: Record<string, string> = {
  'Compliant': 'bg-green-100 dark:bg-green-900/30 text-green-700 dark:text-green-300',
  'Non-Compliant': 'bg-red-100 dark:bg-red-900/30 text-red-700 dark:text-red-300',
  'Conditional': 'bg-amber-100 dark:bg-amber-900/30 text-amber-700 dark:text-amber-300',
  'Pending Review': 'bg-[var(--surface-2)] text-[var(--text-2)]',
}

export function OffersTab({
  eventId,
  scopeLines,
  suppliers,
}: {
  eventId: string
  scopeLines: ScopeLine[]
  suppliers: Supplier[]
}) {
  const [offers, setOffers] = useState<Offer[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [showCompare, setShowCompare] = useState(false)
  const [expandedId, setExpandedId] = useState<string | null>(null)
  const [offerLines, setOfferLines] = useState<Record<string, any[]>>({})
  const [selectedForAward, setSelectedForAward] = useState<string | null>(null)
  const [editingOffer, setEditingOffer] = useState<any | null>(null)
  const [editingTotalId, setEditingTotalId] = useState<string | null>(null)
  const [editTotalValue, setEditTotalValue] = useState('')
  const supabase = createClient()

  const saveOfferTotal = async (offerId: string) => {
    const v = parseFloat(editTotalValue)
    setEditingTotalId(null)
    if (!Number.isFinite(v)) return
    await supabase.from('supplier_offers').update({ offer_total_amount: v }).eq('id', offerId)
    fetchOffers()
  }

  const fetchOffers = useCallback(async () => {
    const { data } = await supabase
      .from('supplier_offers')
      .select(`
        *,
        supplier:suppliers(supplier_name)
      `)
      .eq('event_id', eventId)
      .order('offer_round', { ascending: true })
    setOffers(data || [])
    setLoading(false)
  }, [eventId, supabase])

  useEffect(() => {
    fetchOffers()
  }, [fetchOffers])

  const fetchOfferLines = async (offerId: string) => {
    if (offerLines[offerId]) return
    const { data } = await supabase
      .from('supplier_offer_lines')
      .select(`
        *,
        scope_line:event_scope_lines(item_service_name, uom)
      `)
      .eq('offer_id', offerId)
      .order('line_number', { ascending: true })
    setOfferLines(prev => ({ ...prev, [offerId]: data || [] }))
  }

  const toggleExpand = (offerId: string) => {
    if (expandedId === offerId) {
      setExpandedId(null)
    } else {
      setExpandedId(offerId)
      fetchOfferLines(offerId)
    }
  }

  const toggleCompliance = async (offer: Offer) => {
    await supabase
      .from('supplier_offers')
      .update({ compliant_bid_flag: !offer.compliant_bid_flag })
      .eq('id', offer.id)
    fetchOffers()
  }

  const selectForAward = async (offer: Offer) => {
    // Unselect all other offers
    const others = offers.filter(o => o.id !== offer.id && o.selected_for_award_flag)
    for (const other of others) {
      await supabase.from('supplier_offers').update({ selected_for_award_flag: false }).eq('id', other.id)
    }
    // Toggle this offer
    await supabase
      .from('supplier_offers')
      .update({ selected_for_award_flag: !offer.selected_for_award_flag })
      .eq('id', offer.id)
    fetchOffers()
  }

  const createAward = async (offer: Offer) => {
    if (!confirm(`Create award from ${offer.supplier?.supplier_name}'s offer?`)) return

    // Fetch offer lines
    const { data: lines } = await supabase
      .from('supplier_offer_lines')
      .select('*')
      .eq('offer_id', offer.id)
      .order('line_number', { ascending: true })

    const { data: { user } } = await supabase.auth.getUser()
    const { data: profile } = await supabase
      .from('profiles')
      .select('organization_id')
      .eq('id', user!.id)
      .single()

    const awardName = `Award - ${offer.supplier?.supplier_name || 'Supplier'}`

    const { data: award, error } = await supabase
      .from('awards')
      .insert({
        organization_id: profile?.organization_id,
        event_id: eventId,
        supplier_id: offer.supplier_id,
        offer_id: offer.id,
        award_name: awardName,
        award_date: new Date().toISOString().split('T')[0],
        award_total_amount: offer.offer_total_amount,
        award_status: 'Recommended',
        created_by: user?.id,
      })
      .select('id')
      .single()

    if (!error && award) {
      // Record WHO won on the project itself. sourcing_events.awarded_supplier_id is
      // read by the Projects list, event detail, Reports and Suppliers, but nothing
      // ever wrote it — so every post-award screen kept showing the incumbent.
      await supabase
        .from('sourcing_events')
        .update({ awarded_supplier_id: offer.supplier_id })
        .eq('id', eventId)
    }

    if (!error && award && lines) {
      // Create award lines from offer lines
      for (const line of lines) {
        await supabase.from('award_lines').insert({
          organization_id: profile?.organization_id,
          award_id: award.id,
          event_id: eventId,
          scope_line_id: line.scope_line_id,
          line_number: line.line_number,
          awarded_unit_price: line.offer_unit_price,
          awarded_quantity: line.offer_quantity,
          awarded_extended_amount: line.offer_extended_amount,
          awarded_recurring_amount: line.offer_recurring_amount,
          awarded_one_time_amount: line.offer_one_time_amount,
          awarded_term_months: line.offer_term_months,
          annualized_award_amount: line.annualized_offer_amount,
        })
      }
      // Mark offer as selected for award
      await supabase
        .from('supplier_offers')
        .update({ selected_for_award_flag: true })
        .eq('id', offer.id)
      fetchOffers()
      alert(`Award created: ${awardName}`)
    }
  }

  const handleDelete = async (offerId: string) => {
    if (!confirm('Delete this offer and all its lines?')) return
    await supabase.from('supplier_offers').delete().eq('id', offerId)
    setOffers(offers.filter(o => o.id !== offerId))
  }

  if (loading) {
    return <div className="p-8 text-center text-sm text-[var(--text-3)]">Loading offers...</div>
  }

  return (
    <div>
      {/* Header */}
      <div className="mb-4 flex items-center justify-between">
        <div>
          <h3 className="text-lg font-semibold text-[var(--text)]">Supplier Offers</h3>
          <p className="text-sm text-[var(--text-2)]">Capture and compare supplier pricing</p>
        </div>
        <div className="flex gap-2">
          {offers.length >= 2 && (
            <button
              onClick={() => setShowCompare(!showCompare)}
              className="flex items-center gap-2 rounded-lg border border-indigo-200 dark:border-indigo-800 bg-indigo-50 dark:bg-indigo-900/30 px-4 py-2 text-sm font-medium text-indigo-700 dark:text-indigo-300 hover:bg-indigo-100"
            >
              <GitCompare className="h-4 w-4" />
              {showCompare ? 'Hide Comparison' : 'Compare Offers'}
            </button>
          )}
          <Button onClick={() => setShowForm(!showForm)} className="flex items-center gap-2">
            <Plus className="h-4 w-4" />
            Add Offer
          </Button>
        </div>
      </div>

      {/* Add Offer Form */}
      {showForm && (
        <AddOfferForm
          eventId={eventId}
          scopeLines={scopeLines}
          suppliers={suppliers}
          onSaved={() => { setShowForm(false); fetchOffers() }}
          onCancel={() => setShowForm(false)}
        />
      )}

      {editingOffer && (
        <AddOfferForm
          eventId={eventId}
          scopeLines={scopeLines}
          suppliers={suppliers}
          existing={editingOffer}
          onSaved={() => { setEditingOffer(null); fetchOffers() }}
          onCancel={() => setEditingOffer(null)}
        />
      )}

      {/* Comparison View */}
      {showCompare && offers.length >= 2 && (
        <ComparisonView offers={offers} offerLines={offerLines} fetchOfferLines={fetchOfferLines} eventId={eventId} />
      )}

      {/* Offers List */}
      {offers.length === 0 ? (
        <Card className="p-12 text-center">
          <Users className="mx-auto mb-3 h-10 w-10 text-[var(--text-3)]" />
          <h3 className="text-sm font-medium text-[var(--text)]">No offers yet</h3>
          <p className="mt-1 text-sm text-[var(--text-3)]">Click "Add Offer" to capture supplier pricing.</p>
        </Card>
      ) : (
        <div className="space-y-3">
          {offers.map((offer) => {
            const isExpanded = expandedId === offer.id
            const lines = offerLines[offer.id] || []
            const isLowest = offers.length > 1 && offer.offer_total_amount === Math.min(...offers.map(o => o.offer_total_amount))

            return (
              <Card key={offer.id} className="overflow-hidden">
                {/* Offer Header */}
                <div className="flex items-center gap-4 p-4">
                  <button onClick={() => toggleExpand(offer.id)} className="text-[var(--text-3)] hover:text-[var(--text-2)]">
                    {isExpanded ? <ChevronDown className="h-5 w-5" /> : <ChevronRight className="h-5 w-5" />}
                  </button>

                  <div className="flex-1">
                    <div className="flex items-center gap-2">
                      <h4 className="text-sm font-semibold text-[var(--text)]">
                        {offer.supplier?.supplier_name || 'Unknown Supplier'}
                      </h4>
                      {isLowest && (
                        <Badge tone="success">Lowest Bid</Badge>
                      )}
                      {offer.selected_for_award_flag && (
                        <Badge tone="warning">
                          <Award className="h-3 w-3" /> Selected for Award
                        </Badge>
                      )}
                    </div>
                    <p className="mt-1 text-xs text-[var(--text-3)]">
                      {offer.offer_type} • Round {offer.offer_round}
                      {offer.offer_date && ` • ${formatDate(offer.offer_date)}`}
                      {offer.offer_valid_until && ` • Valid until ${formatDate(offer.offer_valid_until)}`}
                    </p>
                  </div>

                  {/* Total — click to edit. */}
                  <div className="text-right">
                    <p className="text-xs text-[var(--text-3)]">Total Offer</p>
                    {editingTotalId === offer.id ? (
                      <div className="mt-0.5 flex items-center gap-1">
                        <Input type="number" step="0.01" autoFocus value={editTotalValue}
                          onChange={(e) => setEditTotalValue(e.target.value)}
                          onKeyDown={(e) => {
                            if (e.key === 'Enter') { e.preventDefault(); saveOfferTotal(offer.id) }
                            if (e.key === 'Escape') setEditingTotalId(null)
                          }}
                          className="w-36 py-1 text-right text-sm" />
                        <Button type="button" size="sm" onClick={() => saveOfferTotal(offer.id)}>Save</Button>
                      </div>
                    ) : (
                      <button type="button" title="Click to edit"
                        onClick={() => { setEditingTotalId(offer.id); setEditTotalValue(String(offer.offer_total_amount ?? '')) }}
                        className="text-lg font-bold text-[var(--text)] underline decoration-dotted underline-offset-4 hover:text-[var(--brand-ink)]">
                        {formatCurrency(offer.offer_total_amount)}
                      </button>
                    )}
                  </div>

                  {/* Compliance Badge */}
                  <button
                    onClick={() => toggleCompliance(offer)}
                    className={clsx(
                      'flex items-center gap-1 rounded-full px-2.5 py-1 text-xs font-medium',
                      offer.compliant_bid_flag
                        ? 'bg-green-100 dark:bg-green-900/30 text-green-700 dark:text-green-300'
                        : 'bg-red-100 dark:bg-red-900/30 text-red-700 dark:text-red-300'
                    )}
                  >
                    {offer.compliant_bid_flag ? <CheckCircle className="h-3 w-3" /> : <XCircle className="h-3 w-3" />}
                    {offer.compliant_bid_flag ? 'Compliant' : 'Non-Compliant'}
                  </button>

                  {/* Delete */}
                  <button onClick={() => setEditingOffer(offer)} title="Edit offer"
                    className="text-[var(--text-3)] hover:text-[var(--brand-ink)]">
                    <Pencil className="h-4 w-4" />
                  </button>
                  <button onClick={() => handleDelete(offer.id)} className="text-[var(--text-3)] hover:text-red-600 dark:text-red-400">
                    <Trash2 className="h-4 w-4" />
                  </button>
                </div>

                {/* Expanded View */}
                {isExpanded && (
                  <div className="border-t border-[var(--border)] bg-[var(--surface-2)]">
                    {/* Actions */}
                    <div className="flex flex-wrap items-center gap-2 border-b border-[var(--border)] bg-[var(--surface)] px-4 py-3">
                      <button
                        onClick={() => selectForAward(offer)}
                        className={clsx(
                          'flex items-center gap-1 rounded px-2.5 py-1 text-xs font-medium',
                          offer.selected_for_award_flag
                            ? 'bg-amber-100 dark:bg-amber-900/30 text-amber-700 dark:text-amber-300'
                            : 'bg-[var(--surface-2)] text-[var(--text-2)] hover:bg-[var(--border)]'
                        )}
                      >
                        <Award className="h-3 w-3" />
                        {offer.selected_for_award_flag ? 'Selected for Award' : 'Select for Award'}
                      </button>
                      <button
                        onClick={() => createAward(offer)}
                        className="flex items-center gap-1 rounded bg-indigo-50 dark:bg-indigo-900/30 px-2.5 py-1 text-xs font-medium text-indigo-700 dark:text-indigo-300 hover:bg-indigo-100"
                      >
                        <FileText className="h-3 w-3" /> Create Award from Offer
                      </button>
                    </div>

                    {/* Offer Lines Table */}
                    <OfferLinesTable
                      offerId={offer.id}
                      eventId={eventId}
                      scopeLines={scopeLines}
                      lines={lines}
                      onLinesChanged={() => fetchOfferLines(offer.id)}
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

// ============================================
// Add Offer Form
// ============================================
function AddOfferForm({ eventId, scopeLines, suppliers, existing, onSaved, onCancel }: {
  eventId: string
  scopeLines: ScopeLine[]
  suppliers: Supplier[]
  /** When set, the form edits this offer instead of creating a new one. */
  existing?: any | null
  onSaved: () => void
  onCancel: () => void
}) {
  const isEdit = !!existing
  const supabase = createClient()
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  // Most projects involve a first-time vendor, so a supplier must be creatable
  // right here rather than only on the New Project screen.
  const [localSuppliers, setLocalSuppliers] = useState<Supplier[]>(suppliers)
  const [showNewSupplier, setShowNewSupplier] = useState(false)
  const [newSupplierName, setNewSupplierName] = useState('')
  const [addingSupplier, setAddingSupplier] = useState(false)

  useEffect(() => { setLocalSuppliers(suppliers) }, [suppliers])

  const handleAddSupplier = async () => {
    const name = newSupplierName.trim()
    if (!name) return
    setAddingSupplier(true)
    setError(null)

    const { data: { user } } = await supabase.auth.getUser()
    const { data: profile } = await supabase
      .from('profiles').select('organization_id').eq('id', user!.id).single()

    const { data, error: insertError } = await supabase
      .from('suppliers')
      .insert({
        supplier_name: name,
        organization_id: profile?.organization_id,
        supplier_status: 'Active',
      })
      .select('id, supplier_name')
      .single()

    setAddingSupplier(false)
    if (insertError) { setError(insertError.message); return }

    setLocalSuppliers(prev => [...prev, data as Supplier])
    setForm(prev => ({ ...prev, supplier_id: data.id }))
    setNewSupplierName('')
    setShowNewSupplier(false)
  }

  const [form, setForm] = useState({
    supplier_id: existing?.supplier_id ?? '',
    offer_type: existing?.offer_type ?? 'Initial',
    offer_round: existing ? String(existing.offer_round ?? '1') : '1',
    offer_date: existing?.offer_date ?? '',
    offer_valid_until: existing?.offer_valid_until ?? '',
    notes: existing?.notes ?? '',
    offer_total_amount: existing ? String(existing.offer_total_amount ?? '') : '',
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

    const payload: Record<string, any> = {
      supplier_id: form.supplier_id,
      offer_type: form.offer_type,
      offer_round: parseInt(form.offer_round) || 1,
      offer_date: form.offer_date || null,
      offer_valid_until: form.offer_valid_until || null,
      notes: form.notes || null,
      // Direct total entry (primary path). Offer lines are optional detail
      // and recompute this when present.
      offer_total_amount: form.offer_total_amount === '' ? 0 : parseFloat(form.offer_total_amount),
    }

    if (isEdit) {
      const { error: updateError } = await supabase
        .from('supplier_offers').update(payload).eq('id', existing.id)
      if (updateError) { setError(updateError.message); setLoading(false); return }
      onSaved()
      return
    }

    const { error: insertError } = await supabase
      .from('supplier_offers')
      .insert({
        ...payload,
        organization_id: profile?.organization_id,
        event_id: eventId,
        created_by: user.id,
      })

    if (insertError) {
      setError(insertError.message)
      setLoading(false)
      return
    }
    onSaved()
  }

  const inputClass = 'mt-1 block w-full rounded-lg border border-[var(--border-strong)] px-3 py-2 text-sm focus:border-indigo-500 dark:border-indigo-600 focus:outline-none focus:ring-1 focus:ring-indigo-500'
  const labelClass = 'block text-xs font-medium text-[var(--text-2)]'

  return (
    <form onSubmit={handleSubmit} className="mb-6 rounded-lg border border-indigo-200 dark:border-indigo-800 bg-indigo-50 dark:bg-indigo-900/30 p-6">
      <h4 className="mb-4 font-medium text-[var(--text)]">{isEdit ? 'Edit Supplier Offer' : 'New Supplier Offer'}</h4>
      {error && <div className="mb-4 rounded bg-red-50 dark:bg-red-900/30 p-3 text-sm text-red-700 dark:text-red-300">{error}</div>}
      <div className="grid grid-cols-1 gap-4 md:grid-cols-2">
        <div className="md:col-span-2">
          <div className="flex items-center justify-between">
            <label className={labelClass}>Supplier *</label>
            <button type="button" onClick={() => setShowNewSupplier(v => !v)}
              className="text-xs font-medium text-[var(--brand-ink)] hover:underline">
              {showNewSupplier ? 'Cancel' : '+ New supplier'}
            </button>
          </div>
          {showNewSupplier ? (
            <div className="mt-1 flex gap-2">
              <Input type="text" value={newSupplierName} autoFocus
                onChange={(e) => setNewSupplierName(e.target.value)}
                onKeyDown={(e) => { if (e.key === 'Enter') { e.preventDefault(); handleAddSupplier() } }}
                placeholder="New supplier name" />
              <Button type="button" size="sm" disabled={addingSupplier || !newSupplierName.trim()}
                onClick={handleAddSupplier}>
                {addingSupplier ? 'Adding...' : 'Add'}
              </Button>
            </div>
          ) : (
            <Select required value={form.supplier_id}
              onChange={(e) => setForm({ ...form, supplier_id: e.target.value })}
              className="mt-1">
              <option value="">Select supplier...</option>
              {localSuppliers.map((s) => (
                <option key={s.id} value={s.id}>{s.supplier_name}</option>
              ))}
            </Select>
          )}
        </div>
        <div>
          <label className={labelClass}>Offer Total ($) *</label>
          <Input type="number" step="0.01" required value={form.offer_total_amount}
            onChange={(e) => setForm({ ...form, offer_total_amount: e.target.value })}
            className="mt-1" placeholder="e.g. 1200000" />
        </div>
        <div>
          <label className={labelClass}>Offer Type</label>
          <Select value={form.offer_type}
            onChange={(e) => setForm({ ...form, offer_type: e.target.value })}
            className="mt-1">
            {OFFER_TYPES.map((t) => <option key={t} value={t}>{t}</option>)}
          </Select>
        </div>
        <div>
          <label className={labelClass}>Round</label>
          <Input type="number" min="1" value={form.offer_round}
            onChange={(e) => setForm({ ...form, offer_round: e.target.value })}
            className="mt-1" />
        </div>
        <div>
          <label className={labelClass}>Offer Date</label>
          <Input type="date" value={form.offer_date}
            onChange={(e) => setForm({ ...form, offer_date: e.target.value })}
            className="mt-1" />
        </div>
        <div>
          <label className={labelClass}>Valid Until</label>
          <Input type="date" value={form.offer_valid_until}
            onChange={(e) => setForm({ ...form, offer_valid_until: e.target.value })}
            className="mt-1" />
        </div>
        <div className="md:col-span-2">
          <label className={labelClass}>Notes</label>
          <textarea value={form.notes}
            onChange={(e) => setForm({ ...form, notes: e.target.value })}
            className={inputClass} rows={2} />
        </div>
      </div>
      <div className="mt-4 flex justify-end gap-2">
        <Button type="button" variant="secondary" onClick={onCancel}>
          Cancel
        </Button>
        <Button type="submit" disabled={loading}>
          {loading ? 'Saving...' : isEdit ? 'Save Changes' : 'Create Offer'}
        </Button>
      </div>
    </form>
  )
}

// ============================================
// Offer Lines Table
// ============================================
function OfferLinesTable({ offerId, eventId, scopeLines, lines: initialLines, onLinesChanged }: {
  offerId: string
  eventId: string
  scopeLines: ScopeLine[]
  lines: any[]
  onLinesChanged: () => void
}) {
  const supabase = createClient()
  const [lines, setLines] = useState(initialLines)
  const [showAddLine, setShowAddLine] = useState(false)
  const [newLine, setNewLine] = useState({
    scope_line_id: '',
    offer_unit_price: '',
    offer_quantity: '',
    offer_term_months: '12',
    offer_one_time_amount: '',
    compliance_status: 'Compliant',
  })

  useEffect(() => { setLines(initialLines) }, [initialLines])

  const calcExtended = (price: number, qty: number) => price * qty
  const calcAnnualized = (extended: number, termMonths: number) => {
    if (!termMonths || termMonths === 0) return 0
    return (extended * 12) / termMonths
  }

  const handleAddLine = async (e: React.FormEvent) => {
    e.preventDefault()
    const unitPrice = parseFloat(newLine.offer_unit_price) || 0
    const qty = parseFloat(newLine.offer_quantity) || 0
    const termMonths = parseFloat(newLine.offer_term_months) || 12
    const extended = calcExtended(unitPrice, qty)
    const annualized = calcAnnualized(extended, termMonths)
    const oneTime = parseFloat(newLine.offer_one_time_amount) || 0

    const { data: { user } } = await supabase.auth.getUser()
    const { data: profile } = await supabase
      .from('profiles')
      .select('organization_id')
      .eq('id', user!.id)
      .single()

    const lineNumber = lines.length + 1

    const { data, error } = await supabase
      .from('supplier_offer_lines')
      .insert({
        organization_id: profile?.organization_id,
        offer_id: offerId,
        event_id: eventId,
        scope_line_id: newLine.scope_line_id || null,
        line_number: lineNumber,
        offer_unit_price: unitPrice,
        offer_quantity: qty,
        offer_extended_amount: extended,
        offer_recurring_amount: extended,
        offer_one_time_amount: oneTime,
        offer_term_months: termMonths,
        annualized_offer_amount: annualized,
        compliance_status: newLine.compliance_status,
      })
      .select(`
        *,
        scope_line:event_scope_lines(item_service_name, uom)
      `)
      .single()

    if (!error && data) {
      const nextLines = [...lines, data]
      setLines(nextLines)
      setNewLine({
        scope_line_id: '', offer_unit_price: '', offer_quantity: '',
        offer_term_months: '12', offer_one_time_amount: '', compliance_status: 'Compliant',
      })
      setShowAddLine(false)
      onLinesChanged()
      // Same stale-closure fix as baselines-tab: total the NEXT array, not React state.
      updateOfferTotal(nextLines)
    }
  }

  const handleDeleteLine = async (lineId: string) => {
    if (!confirm('Delete this offer line? This cannot be undone.')) return
    await supabase.from('supplier_offer_lines').delete().eq('id', lineId)
    const nextLines = lines.filter(l => l.id !== lineId)
    setLines(nextLines)
    onLinesChanged()
    updateOfferTotal(nextLines)
  }

  const updateOfferTotal = async (currentLines: any[]) => {
    const total = currentLines.reduce((sum, l) => sum + (l.offer_extended_amount || 0), 0)
    await supabase.from('supplier_offers').update({ offer_total_amount: total }).eq('id', offerId)
  }

  const labelClass = 'block text-xs font-medium text-[var(--text-3)] mb-1'

  const totalExtended = lines.reduce((sum, l) => sum + (l.offer_extended_amount || 0), 0)
  const totalAnnualized = lines.reduce((sum, l) => sum + (l.annualized_offer_amount || 0), 0)

  return (
    <div className="p-4">
      <div className="mb-3 flex items-center justify-between">
        <h5 className="text-sm font-medium text-[var(--text-2)]">Offer Lines</h5>
        <button onClick={() => setShowAddLine(!showAddLine)}
          className="flex items-center gap-1 rounded bg-[var(--surface)] px-2.5 py-1 text-xs font-medium text-indigo-600 dark:text-indigo-400 hover:bg-indigo-50 dark:bg-indigo-900/30">
          <Plus className="h-3 w-3" /> Add Line
        </button>
      </div>

      {showAddLine && (
        <form onSubmit={handleAddLine} className="mb-4 rounded border border-indigo-200 dark:border-indigo-800 bg-[var(--surface)] p-4">
          <div className="grid grid-cols-1 gap-3 md:grid-cols-3">
            <div className="md:col-span-3">
              <label className={labelClass}>Scope Line</label>
              <Select value={newLine.scope_line_id}
                onChange={(e) => setNewLine({ ...newLine, scope_line_id: e.target.value })}>
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
              <Input type="number" step="0.0001" required value={newLine.offer_unit_price}
                onChange={(e) => setNewLine({ ...newLine, offer_unit_price: e.target.value })}
                placeholder="0.00" />
            </div>
            <div>
              <label className={labelClass}>Quantity</label>
              <Input type="number" step="0.01" required value={newLine.offer_quantity}
                onChange={(e) => setNewLine({ ...newLine, offer_quantity: e.target.value })}
                placeholder="0" />
            </div>
            <div>
              <label className={labelClass}>Term (months)</label>
              <Input type="number" step="0.01" value={newLine.offer_term_months}
                onChange={(e) => setNewLine({ ...newLine, offer_term_months: e.target.value })} />
            </div>
            <div>
              <label className={labelClass}>Extended (auto)</label>
              <div className="rounded border border-[var(--border)] bg-[var(--surface-2)] px-2 py-1 text-xs text-[var(--text-2)]">
                {formatCurrency(calcExtended(
                  parseFloat(newLine.offer_unit_price) || 0,
                  parseFloat(newLine.offer_quantity) || 0
                ))}
              </div>
            </div>
            <div>
              <label className={labelClass}>One-Time Amount</label>
              <Input type="number" step="0.01" value={newLine.offer_one_time_amount}
                onChange={(e) => setNewLine({ ...newLine, offer_one_time_amount: e.target.value })}
                placeholder="0" />
            </div>
            <div>
              <label className={labelClass}>Compliance</label>
              <Select value={newLine.compliance_status}
                onChange={(e) => setNewLine({ ...newLine, compliance_status: e.target.value })}>
                <option value="Compliant">Compliant</option>
                <option value="Non-Compliant">Non-Compliant</option>
                <option value="Conditional">Conditional</option>
                <option value="Pending Review">Pending Review</option>
              </Select>
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

      {lines.length === 0 ? (
        <p className="py-6 text-center text-xs text-[var(--text-3)]">
          No offer lines yet. Click "Add Line" to add pricing.
        </p>
      ) : (
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b border-[var(--border)] text-left text-xs uppercase text-[var(--text-3)]">
                <th className="px-2 py-2">#</th>
                <th className="px-2 py-2">Scope Line</th>
                <th className="px-2 py-2 text-right">Unit Price</th>
                <th className="px-2 py-2 text-right">Qty</th>
                <th className="px-2 py-2 text-right">Extended</th>
                <th className="px-2 py-2 text-right">One-Time</th>
                <th className="px-2 py-2 text-right">Term</th>
                <th className="px-2 py-2 text-right">Annualized</th>
                <th className="px-2 py-2 text-center">Compliance</th>
                <th className="px-2 py-2"></th>
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
                    {line.scope_line?.uom && <div className="text-[var(--text-3)]">{line.scope_line.uom}</div>}
                  </td>
                  <td className="px-2 py-2 text-right text-xs text-[var(--text-2)]">
                    {line.offer_unit_price ? formatCurrency(line.offer_unit_price) : '—'}
                  </td>
                  <td className="px-2 py-2 text-right text-xs text-[var(--text-2)]">{line.offer_quantity ?? '—'}</td>
                  <td className="px-2 py-2 text-right text-xs font-medium text-[var(--text)]">
                    {formatCurrency(line.offer_extended_amount)}
                  </td>
                  <td className="px-2 py-2 text-right text-xs text-[var(--text-2)]">
                    {formatCurrency(line.offer_one_time_amount)}
                  </td>
                  <td className="px-2 py-2 text-right text-xs text-[var(--text-2)]">{line.offer_term_months ?? '—'}</td>
                  <td className="px-2 py-2 text-right text-xs font-medium text-indigo-700 dark:text-indigo-300">
                    {formatCurrency(line.annualized_offer_amount)}
                  </td>
                  <td className="px-2 py-2 text-center">
                    <span className={clsx('rounded px-2 py-0.5 text-xs font-medium',
                      COMPLIANCE_STATUS_COLORS[line.compliance_status] || 'bg-[var(--surface-2)] text-[var(--text-2)]'
                    )}>
                      {line.compliance_status}
                    </span>
                  </td>
                  <td className="px-2 py-2 text-right">
                    <button onClick={() => handleDeleteLine(line.id)}
                      className="text-[var(--text-3)] hover:text-red-600 dark:text-red-400">
                      <Trash2 className="h-3.5 w-3.5" />
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
            <tfoot>
              <tr className="border-t-2 border-[var(--border)] bg-[var(--surface-2)] font-medium">
                <td colSpan={4} className="px-2 py-2 text-right text-xs text-[var(--text-2)]">Totals:</td>
                <td className="px-2 py-2 text-right text-xs font-bold text-[var(--text)]">{formatCurrency(totalExtended)}</td>
                <td colSpan={2} className="px-2 py-2"></td>
                <td className="px-2 py-2 text-right text-xs font-bold text-indigo-700 dark:text-indigo-300">{formatCurrency(totalAnnualized)}</td>
                <td colSpan={2} className="px-2 py-2"></td>
              </tr>
            </tfoot>
          </table>
        </div>
      )}
    </div>
  )
}

// ============================================
// Comparison View (side-by-side)
// ============================================
function ComparisonView({ offers, offerLines, fetchOfferLines, eventId }: {
  offers: Offer[]
  offerLines: Record<string, any[]>
  fetchOfferLines: (id: string) => void
  eventId: string
}) {
  const supabase = createClient()
  const [baselines, setBaselines] = useState<any[]>([])

  useEffect(() => {
    // Fetch the official baseline for comparison
    const fetchBaseline = async () => {
      const { data } = await supabase
        .from('baselines')
        .select('*, baseline_lines(*)')
        .eq('event_id', eventId)
        .eq('official_for_hard_savings', true)
        .maybeSingle()
      if (data) setBaselines([data])
    }
    fetchBaseline()
  }, [eventId, supabase])

  // Fetch all offer lines for comparison
  useEffect(() => {
    offers.forEach(offer => {
      if (!offerLines[offer.id]) fetchOfferLines(offer.id)
    })
  }, [offers, offerLines, fetchOfferLines])

  // Collect all unique scope line names
  const allScopeLines = new Map<string, string>()
  offers.forEach(offer => {
    const lines = offerLines[offer.id] || []
    lines.forEach((line: any) => {
      if (line.scope_line?.item_service_name) {
        allScopeLines.set(line.scope_line_id, line.scope_line.item_service_name)
      }
    })
  })

  const scopeLineNames = Array.from(allScopeLines.entries())

  // Get line amount for a specific offer and scope line
  const getLineAmount = (offerId: string, scopeLineId: string) => {
    const lines = offerLines[offerId] || []
    const line = lines.find((l: any) => l.scope_line_id === scopeLineId)
    return line ? line.offer_extended_amount : null
  }

  const getLineUnitPrice = (offerId: string, scopeLineId: string) => {
    const lines = offerLines[offerId] || []
    const line = lines.find((l: any) => l.scope_line_id === scopeLineId)
    return line ? line.offer_unit_price : null
  }

  // Calculate savings vs baseline for each offer
  const baselineTotal = baselines[0]?.baseline_total_amount || 0
  const baselineLines = baselines[0]?.baseline_lines || []

  const getBaselineLineAmount = (scopeLineId: string) => {
    const line = baselineLines.find((l: any) => l.scope_line_id === scopeLineId)
    return line ? line.baseline_extended_amount : null
  }

  return (
    <Card className="mb-6 overflow-hidden">
      <div className="border-b border-[var(--border)] bg-[var(--surface-2)] px-4 py-3">
        <h4 className="flex items-center gap-2 text-sm font-semibold text-[var(--text)]">
          <GitCompare className="h-4 w-4" />
          Side-by-Side Offer Comparison
        </h4>
        <p className="mt-1 text-xs text-[var(--text-3)]">Compare all supplier offers line by line</p>
      </div>

      <div className="overflow-x-auto">
        <table className="w-full">
          <thead>
            <tr className="border-b border-[var(--border)] bg-[var(--surface)]">
              <th className="sticky left-0 bg-[var(--surface)] px-4 py-3 text-left text-xs font-semibold uppercase text-[var(--text-3)]">
                Scope Line
              </th>
              {baselines[0] && (
                <th className="px-4 py-3 text-right text-xs font-semibold uppercase text-[var(--text-3)]">
                  <div className="text-[var(--text-2)]">Baseline</div>
                  <div className="text-xs font-normal text-[var(--text-3)]">{baselines[0].baseline_name}</div>
                </th>
              )}
              {offers.map((offer) => {
                const isLowest = offer.offer_total_amount === Math.min(...offers.map(o => o.offer_total_amount))
                return (
                  <th key={offer.id} className="px-4 py-3 text-right text-xs font-semibold uppercase text-[var(--text-3)]">
                    <div className="flex items-center justify-end gap-1">
                      {offer.supplier?.supplier_name}
                      {isLowest && <Badge tone="success">Lowest</Badge>}
                    </div>
                    <div className="text-xs font-normal text-[var(--text-3)]">{offer.offer_type} • Round {offer.offer_round}</div>
                  </th>
                )
              })}
            </tr>
          </thead>
          <tbody className="divide-y divide-[var(--border)]">
            {/* Line items */}
            {scopeLineNames.length === 0 ? (
              <tr>
                <td colSpan={2 + offers.length} className="px-4 py-8 text-center text-sm text-[var(--text-3)]">
                  No scope lines linked to offers. Expand each offer to add line-level pricing linked to scope lines.
                </td>
              </tr>
            ) : (
              scopeLineNames.map(([scopeLineId, name]) => (
                <tr key={scopeLineId} className="hover:bg-[var(--surface-2)]">
                  <td className="sticky left-0 bg-[var(--surface)] px-4 py-3 text-sm font-medium text-[var(--text)]">
                    {name}
                  </td>
                  {baselines[0] && (
                    <td className="px-4 py-3 text-right text-sm text-[var(--text-2)]">
                      {getBaselineLineAmount(scopeLineId) !== null ? formatCurrency(getBaselineLineAmount(scopeLineId)) : '—'}
                    </td>
                  )}
                  {offers.map((offer) => {
                    const amount = getLineAmount(offer.id, scopeLineId)
                    const unitPrice = getLineUnitPrice(offer.id, scopeLineId)
                    const baselineAmount = getBaselineLineAmount(scopeLineId)
                    const savings = (baselineAmount && amount) ? baselineAmount - amount : null
                    return (
                      <td key={offer.id} className="px-4 py-3 text-right text-sm">
                        {amount !== null ? (
                          <div>
                            <div className="font-medium text-[var(--text)]">{formatCurrency(amount)}</div>
                            <div className="text-xs text-[var(--text-3)]">@ {formatCurrency(unitPrice || 0)}</div>
                            {savings !== null && savings > 0 && (
                              <div className="text-xs font-medium text-green-600 dark:text-green-400">↓ {formatCurrency(savings)}</div>
                            )}
                            {savings !== null && savings < 0 && (
                              <div className="text-xs font-medium text-red-600 dark:text-red-400">↑ {formatCurrency(Math.abs(savings))}</div>
                            )}
                          </div>
                        ) : (
                          <span className="text-[var(--text-3)]">—</span>
                        )}
                      </td>
                    )
                  })}
                </tr>
              ))
            )}

            {/* Total row */}
            <tr className="border-t-2 border-[var(--border)] bg-[var(--surface-2)] font-semibold">
              <td className="sticky left-0 bg-[var(--surface-2)] px-4 py-3 text-sm text-[var(--text)]">Total</td>
              {baselines[0] && (
                <td className="px-4 py-3 text-right text-sm text-[var(--text)]">
                  {formatCurrency(baselineTotal)}
                </td>
              )}
              {offers.map((offer) => {
                const savings = baselineTotal ? grossSavings(baselineTotal, offer.offer_total_amount) : null
                const savingsPct = baselineTotal ? savingsPctOf(savings!, baselineTotal) : null
                return (
                  <td key={offer.id} className="px-4 py-3 text-right text-sm">
                    <div className="text-[var(--text)]">{formatCurrency(offer.offer_total_amount)}</div>
                    {savings !== null && savings > 0 && (
                      <div className="text-xs font-medium text-green-600 dark:text-green-400">
                        ↓ {formatCurrency(savings)} ({savingsPct?.toFixed(1)}%)
                      </div>
                    )}
                    {savings !== null && savings < 0 && (
                      <div className="text-xs font-medium text-red-600 dark:text-red-400">
                        ↑ {formatCurrency(Math.abs(savings))} ({Math.abs(savingsPct!).toFixed(1)}%)
                      </div>
                    )}
                  </td>
                )
              })}
            </tr>
          </tbody>
        </table>
      </div>
    </Card>
  )
}
