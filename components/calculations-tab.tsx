'use client'

import { useState, useEffect, useCallback } from 'react'
import { createClient } from '@/lib/supabase/client'
import type { Tables, TablesInsert } from '@/lib/database.types'
import { Calculator, ArrowRight, AlertCircle, Check } from 'lucide-react'
import { formatCurrency } from '@/lib/utils'
import {
  chainWithBaselineQuality, baselineQuality, termRates,
  reportableSavingsPct, type RateBasis,
} from '@/lib/savings'
import { clsx } from 'clsx'
import { Card } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input, Select } from '@/components/ui/input'

const CALC_STATUSES = [
  { value: 'identified', label: 'Identified' },
  { value: 'negotiated', label: 'Negotiated' },
  { value: 'contracted', label: 'Contracted' },
  { value: 'realized', label: 'Realized' },
]

type Anchor = {
  label: string
  amount: number | null
  months: number | null
  detail: string
  missing: boolean
}

type CalculationBaseline = Pick<Tables<'baselines'>,
  | 'id'
  | 'baseline_name'
  | 'baseline_type'
  | 'baseline_source'
  | 'baseline_total_amount'
  | 'baseline_term_months'
  | 'is_selected'
  | 'hard_reduction_override'
  | 'hard_reduction_override_reason'
>

type SupplierName = { supplier_name: string }

type CalculationOffer = Pick<Tables<'supplier_offers'>,
  | 'id'
  | 'offer_total_amount'
  | 'offer_term_months'
  | 'offer_role'
  | 'offer_type'
  | 'offer_round'
> & { supplier: SupplierName | SupplierName[] | null }

/**
 * The savings calculation is DERIVED from three selected anchors, never typed:
 *   Opening -> Baseline -> Final
 * You pick which baseline and which offers play those roles on their own tabs;
 * this tab shows the resulting arithmetic and saves it as the project's one
 * savings record (which is what every dashboard and report reads).
 */
export function CalculationsTab({ eventId }: { eventId: string }) {
  const supabase = createClient()
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [savedAt, setSavedAt] = useState<string | null>(null)

  const [baseline, setBaseline] = useState<CalculationBaseline | null>(null)
  const [opening, setOpening] = useState<CalculationOffer | null>(null)
  const [final, setFinal] = useState<CalculationOffer | null>(null)
  const [existing, setExisting] = useState<Tables<'savings_calculations'> | null>(null)

  const [basis, setBasis] = useState<RateBasis>('perYear')
  const [status, setStatus] = useState('identified')
  const [startDate, setStartDate] = useState('')

  const load = useCallback(async () => {
    const [{ data: bases }, { data: offers }, { data: calcs }, { data: ev }] = await Promise.all([
      supabase.from('baselines')
        .select('id, baseline_name, baseline_type, baseline_source, baseline_total_amount, baseline_term_months, is_selected, hard_reduction_override, hard_reduction_override_reason')
        .eq('event_id', eventId),
      supabase.from('supplier_offers')
        .select('id, offer_total_amount, offer_term_months, offer_role, offer_type, offer_round, supplier:suppliers(supplier_name)')
        .eq('event_id', eventId),
      supabase.from('savings_calculations').select('*').eq('event_id', eventId)
        .order('created_at', { ascending: true }),
      supabase.from('sourcing_events').select('contract_start_date, contract_end_date').eq('id', eventId).maybeSingle(),
    ])

    setBaseline((bases || []).find(b => b.is_selected) ?? null)
    setOpening((offers || []).find(o => o.offer_role === 'opening') ?? null)
    setFinal((offers || []).find(o => o.offer_role === 'final') ?? null)

    const calc = (calcs || [])[0] ?? null
    setExisting(calc)
    if (calc) {
      setStatus(calc.calculation_status || 'identified')
      setStartDate(calc.savings_start_date || '')
      setSavedAt(calc.updated_at || calc.created_at || null)
    } else {
      setStartDate(ev?.contract_start_date || '')
    }
    setLoading(false)
  }, [eventId, supabase])

  useEffect(() => { load() }, [load])

  const supplierName = (o: CalculationOffer | null) =>
    (Array.isArray(o?.supplier) ? o.supplier[0] : o?.supplier)?.supplier_name || 'Supplier'

  const bRates = termRates(baseline?.baseline_total_amount, baseline?.baseline_term_months)
  const oRates = termRates(opening?.offer_total_amount, opening?.offer_term_months)
  const fRates = termRates(final?.offer_total_amount, final?.offer_term_months)

  // The deal's term is the Final offer's term - that is what was signed. On a
  // "whole term" basis every anchor is extended to it, otherwise a 12-month
  // baseline would be subtracted from a 36-month final, which is the exact
  // apples-to-oranges error the monthly rate exists to prevent.
  const dealMonths = Number(final?.offer_term_months) || Number(baseline?.baseline_term_months) || 12

  // An anchor whose TERM was never captured is NOT CAPTURED, not zero.
  // termRates() returns perMonth 0 with known:false in that case; treating that
  // as a real zero used to publish a baseline of $0 and a Cost Reduction of
  // minus the entire deal, while leaving Total correct so no invariant fired.
  // `known` exists precisely so callers show "—" instead of "0".
  const pick = (r: ReturnType<typeof termRates>, present: boolean) =>
    !present || !r.known ? null
      : basis === 'perMonth' ? r.perMonth
      : basis === 'perYear' ? r.perYear
      : r.perMonth * dealMonths

  // Whether this baseline may drive a HARD Cost Reduction at all. A market
  // index or a vendor's own quote is a reference figure, not spend you
  // incurred, so it books as avoidance -- the Total is identical either way.
  const quality = baselineQuality(baseline?.baseline_type, {
    enabled: baseline?.hard_reduction_override,
    reason: baseline?.hard_reduction_override_reason,
  })

  const chain = chainWithBaselineQuality({
    opening: pick(oRates, !!opening),
    baseline: pick(bRates, !!baseline),
    final: pick(fRates, !!final) ?? 0,
  }, quality.isHard)

  const anchors: Anchor[] = [
    {
      label: 'Opening proposal', amount: opening?.offer_total_amount ?? null,
      months: opening?.offer_term_months ?? null,
      detail: opening ? `${supplierName(opening)} · ${opening.offer_type} · round ${opening.offer_round}` : 'Mark an offer as “Opening proposal” on the Supplier Offers tab',
      missing: !opening,
    },
    {
      label: 'Baseline (current spend)', amount: baseline?.baseline_total_amount ?? null,
      months: baseline?.baseline_term_months ?? null,
      detail: baseline ? [baseline.baseline_type, baseline.baseline_source].filter(Boolean).join(' · ') : 'Choose “Use as baseline” on the Baselines tab',
      missing: !baseline,
    },
    {
      label: 'Final offer', amount: final?.offer_total_amount ?? null,
      months: final?.offer_term_months ?? null,
      detail: final ? `${supplierName(final)} · ${final.offer_type} · round ${final.offer_round}` : 'Mark an offer as “Final offer” on the Supplier Offers tab',
      missing: !final,
    },
  ]

  // The end date is not a separate fact: the deal term already says how long
  // the savings run. Derive it so it can never contradict the term.
  const derivedEnd = (() => {
    if (!startDate) return null
    const d = new Date(startDate + 'T00:00:00')
    if (isNaN(d.getTime())) return null
    d.setMonth(d.getMonth() + dealMonths)
    d.setDate(d.getDate() - 1)          // inclusive of the final day
    return d.toISOString().slice(0, 10)
  })()

  const basisLabel = basis === 'perMonth' ? 'per month' : basis === 'perYear' ? 'per year' : `over the ${dealMonths}-month term`

  const save = async () => {
    if (!final) { setError('Select a Final offer before saving.'); return }
    // Without the Final offer's term there is no deal term, so nothing here is
    // derivable. Refuse rather than publish a figure built on a guessed 12.
    if (!fRates.known) {
      setError('The Final offer has no term in months, so the deal term is unknown. Set it on the Supplier Offers tab.')
      return
    }
    setSaving(true); setError(null)

    const { data: { user } } = await supabase.auth.getUser()
    if (!user) { setError('Not logged in'); setSaving(false); return }
    const { data: profile } = await supabase
      .from('profiles').select('organization_id').eq('id', user.id).single()

    // WHAT GETS PUBLISHED IS ALWAYS THE WHOLE DEAL TERM, whatever basis is on
    // screen. The basis switch is a lens for reading the numbers, not a claim
    // about what the deal is worth: publishing the displayed basis meant the
    // dashboard reported a different figure depending on where a dropdown had
    // been left, and the savings schedule (whole-term by construction) could
    // never agree with it.
    const overTerm = (r: ReturnType<typeof termRates>, present: boolean) =>
      present && r.known ? r.perMonth * dealMonths : null
    const termChain = chainWithBaselineQuality({
      opening: overTerm(oRates, !!opening),
      baseline: overTerm(bRates, !!baseline),
      final: overTerm(fRates, !!final) ?? 0,
    }, quality.isHard)

    // Denominator is BASELINE spend, never the opening ask. Null when there
    // is no baseline -- see reportableSavingsPct.
    const baselineOverTerm = overTerm(bRates, !!baseline)
    const payload: TablesInsert<'savings_calculations'> = {
      event_id: eventId,
      baseline_id: baseline?.id ?? null,
      calculation_name: `${dealMonths}-month deal savings`,
      // Derived, never chosen. A negotiation produces BOTH legs; the label just
      // records which one carried the deal. The dashboard splits on the two
      // amount columns, not on this.
      savings_type: (termChain.reduction ?? 0) >= termChain.avoidance ? 'Cost Reduction' : 'Cost Avoidance',
      calculation_status: status,
      baseline_total_amount: overTerm(bRates, !!baseline),
      opening_proposal_amount: overTerm(oRates, !!opening),
      award_total_amount: overTerm(fRates, !!final) ?? 0,
      gross_savings_amount: termChain.total,
      cost_reduction_amount: termChain.reduction,
      cost_avoidance_amount: termChain.avoidance,
      savings_percentage: reportableSavingsPct(termChain.total, quality.isHard ? baselineOverTerm : null),
      net_savings_amount: termChain.total,
      savings_start_date: startDate || null,
      savings_end_date: derivedEnd,
      recognition_notes: `Derived from the selected anchors over the ${dealMonths}-month deal term.`,
      updated_by: user.id,
    }

    const res = existing
      ? await supabase.from('savings_calculations').update(payload).eq('id', existing.id)
      : await supabase.from('savings_calculations')
          .insert({ ...payload, organization_id: profile?.organization_id, created_by: user.id })

    setSaving(false)
    if (res.error) { setError(res.error.message); return }
    setSavedAt(new Date().toISOString())
    load()
  }

  if (loading) {
    return <div className="p-8 text-center text-sm text-[var(--text-3)]">Loading calculation...</div>
  }

  const ready = !!final && (!!baseline || !!opening)

  return (
    <div>
      <div className="mb-4">
        <h3 className="text-lg font-semibold text-[var(--text)]">Savings Calculation</h3>
        <p className="text-sm text-[var(--text-2)]">
          Derived from the anchors you selected. Nothing here is typed by hand.
        </p>
      </div>

      {/* The methodology, stated correctly. */}
      <div className="mb-4 rounded-lg border border-blue-200 bg-blue-50 p-4 dark:border-blue-800 dark:bg-blue-900/20">
        <div className="flex items-start gap-3">
          <Calculator className="mt-0.5 h-5 w-5 shrink-0 text-blue-600 dark:text-blue-400" />
          <div className="text-xs text-blue-700 dark:text-blue-300">
            <p className="text-sm font-semibold text-blue-900 dark:text-blue-100">The chain</p>
            <p className="mt-1"><strong>Cost Reduction</strong> = Baseline − Final. Hard, hits the P&amp;L. Can be negative, shown in parentheses.</p>
            <p><strong>Cost Avoidance</strong> = Opening − Baseline. Soft, the increase you held off.</p>
            <p><strong>Total procurement performance</strong> = Opening − Final = Reduction + Avoidance, counted once.</p>
            <p className="mt-1 opacity-80">All figures are pre-tax. Procurement does not negotiate tax, and the savings percentage is the same either way.</p>
          </div>
        </div>
      </div>

      {/* The three anchors */}
      <Card className="mb-4 p-4">
        <div className="mb-3 flex flex-wrap items-center justify-between gap-2">
          <h4 className="text-sm font-semibold text-[var(--text)]">Selected anchors</h4>
          <div className="flex items-center gap-2">
            {/* A lens, not a decision — the saved figure is always whole-term. */}
            <span className="text-xs text-[var(--text-3)]">View as</span>
            <Select aria-label="Display rate basis" value={basis} onChange={(e) => setBasis(e.target.value as RateBasis)}
              className="w-auto px-2 py-1 text-xs">
              <option value="perYear">Per year</option>
              <option value="perMonth">Per month</option>
              <option value="perTerm">{`Whole term (${dealMonths} mo)`}</option>
            </Select>
          </div>
        </div>

        <div className="grid grid-cols-1 gap-3 md:grid-cols-3">
          {anchors.map((a, i) => {
            const r = termRates(a.amount, a.months)
            const shown = a.missing ? null : basis === 'perMonth' ? r.perMonth : basis === 'perYear' ? r.perYear : r.perMonth * dealMonths
            return (
              <div key={a.label} className={clsx(
                'rounded-lg border p-3',
                a.missing ? 'border-dashed border-[var(--border-strong)] bg-[var(--surface-2)]' : 'border-[var(--border)] bg-[var(--surface)]'
              )}>
                <div className="flex items-center gap-1 text-xs text-[var(--text-3)]">
                  {a.label}
                  {i < 2 && <ArrowRight className="ml-auto h-3 w-3" />}
                </div>
                {a.missing ? (
                  <>
                    <p className="mt-1 text-sm font-medium text-[var(--text-3)]">not selected</p>
                    <p className="mt-1 text-[11px] text-[var(--text-3)]">{a.detail}</p>
                  </>
                ) : (
                  <>
                    <p className="mt-1 text-lg font-bold text-[var(--text)]">
                      {r.known ? formatCurrency(shown ?? 0) : '—'}
                    </p>
                    <p className={clsx('text-[11px]',
                      r.known ? 'text-[var(--text-3)]' : 'text-amber-600 dark:text-amber-400')}>
                      {r.known
                        ? `${formatCurrency(a.amount ?? 0)} over ${a.months} mo`
                        : `${formatCurrency(a.amount ?? 0)}, term not captured — cannot be compared`}
                    </p>
                    <p className="mt-1 truncate text-[11px] text-[var(--text-3)]" title={a.detail}>{a.detail}</p>
                  </>
                )}
              </div>
            )
          })}
        </div>
      </Card>

      {!ready ? (
        <Card className="p-8 text-center">
          <AlertCircle className="mx-auto mb-3 h-8 w-8 text-[var(--text-3)]" />
          <p className="text-sm font-medium text-[var(--text)]">Select your anchors to see the savings</p>
          <p className="mt-1 text-sm text-[var(--text-3)]">
            A Final offer is required. Add a Baseline for Cost Reduction, and an Opening proposal
            for Cost Avoidance.
          </p>
        </Card>
      ) : (
        <>
          <Card className="mb-4 p-4">
            <div className="grid grid-cols-1 gap-4 text-center md:grid-cols-3">
              <div>
                <p className="text-xs text-[var(--text-3)]">Cost Reduction</p>
                <p className={clsx('text-xl font-bold',
                  chain.reduction === null ? 'text-[var(--text-3)]'
                    : chain.reduction < 0 ? 'text-red-600 dark:text-red-400' : 'text-[var(--text)]')}>
                  {chain.reduction === null ? 'n/a'
                    : chain.reduction < 0 ? `(${formatCurrency(Math.abs(chain.reduction))})`
                    : formatCurrency(chain.reduction)}
                </p>
                <p className="text-[11px] text-[var(--text-3)]">Baseline − Final · {basisLabel}</p>
              </div>
              <div>
                <p className="text-xs text-[var(--text-3)]">Cost Avoidance</p>
                <p className="text-xl font-bold text-[var(--text)]">{formatCurrency(chain.avoidance)}</p>
                <p className="text-[11px] text-[var(--text-3)]">Opening − Baseline · {basisLabel}</p>
              </div>
              <div className="rounded-lg bg-[var(--surface-2)] p-2">
                <p className="text-xs text-[var(--text-3)]">Total procurement performance</p>
                <p className="text-2xl font-bold text-green-600 dark:text-green-400">{formatCurrency(chain.total)}</p>
                <p className="text-[11px] text-[var(--text-3)]">Opening − Final · {basisLabel}</p>
              </div>
            </div>

            {chain.reduction === null && !baseline && (
              <p className="mt-3 text-xs text-[var(--text-3)]">
                No baseline selected, so the whole span books as avoidance and Cost Reduction is
                not applicable.
              </p>
            )}
            {/* A soft baseline is the other reason reduction reads n/a, and it is
                far less obvious than having no baseline at all. Say which type
                caused it, so nobody has to guess why the hard line is empty. */}
            {chain.reduction === null && !!baseline && (
              <p className="mt-3 text-xs text-amber-600 dark:text-amber-400">
                {quality.explanation} The whole span books as <strong>Cost Avoidance</strong> and the
                Total is unchanged — only the hard line is empty. If this baseline really does
                reflect what you were paying, record an override on the Baselines tab.
              </p>
            )}
            {quality.byOverride && (
              <p className="mt-3 text-xs text-amber-600 dark:text-amber-400">
                <strong>Booked as hard by override.</strong> {baseline?.baseline_type} does not
                normally qualify. The reason on file is:{' '}
                <span className="italic">&ldquo;{baseline?.hard_reduction_override_reason}&rdquo;</span>
              </p>
            )}
            {!opening && (
              <p className="mt-3 text-xs text-[var(--text-3)]">
                No opening proposal selected, so the total collapses to Cost Reduction.
              </p>
            )}
            {chain.reduction !== null && chain.reduction < 0 && (
              <p className="mt-3 text-xs text-amber-600 dark:text-amber-400">
                This is a genuine cost increase against the baseline, shown in parentheses. It is
                not relabelled as savings.
              </p>
            )}
          </Card>

          <Card className="p-4">
            <h4 className="mb-1 text-sm font-semibold text-[var(--text)]">Reporting</h4>
            <p className="mb-3 text-xs text-[var(--text-3)]">
              How this figure is reported. The savings type is derived from the chain, and the end
              date from the {dealMonths}-month term, so neither can contradict the numbers above.
            </p>
            <div className="grid grid-cols-1 gap-4 md:grid-cols-3">
              <div>
                <label className="block text-xs font-medium text-[var(--text-2)]">Stage</label>
                <Select aria-label="Stage" value={status} onChange={(e) => setStatus(e.target.value)} className="mt-1">
                  {CALC_STATUSES.map(s => <option key={s.value} value={s.value}>{s.label}</option>)}
                </Select>
                <p className="mt-1 text-[11px] text-[var(--text-3)]">
                  Identified/Negotiated report as forecast; Contracted/Realized as booked.
                </p>
              </div>
              <div>
                <label className="block text-xs font-medium text-[var(--text-2)]">Savings start</label>
                <Input aria-label="Savings start" type="date" value={startDate} onChange={(e) => setStartDate(e.target.value)} className="mt-1" />
                <p className="mt-1 text-[11px] text-[var(--text-3)]">When the new pricing takes effect.</p>
              </div>
              <div>
                <label className="block text-xs font-medium text-[var(--text-2)]">Savings end</label>
                <div className="mt-1 rounded-md border border-[var(--border)] bg-[var(--surface-2)] px-3 py-2 text-sm text-[var(--text-2)]">
                  {derivedEnd ?? 'set a start date'}
                </div>
                <p className="mt-1 text-[11px] text-[var(--text-3)]">
                  Start + {dealMonths} months, from the Final offer term.
                </p>
              </div>
            </div>

            {error && (
              <div role="alert" className="mt-3 rounded bg-red-50 p-3 text-sm text-red-700 dark:bg-red-900/30 dark:text-red-300">{error}</div>
            )}

            <div className="mt-4 flex items-center justify-end gap-3">
              {savedAt && !saving && (
                <span className="flex items-center gap-1 text-xs text-[var(--text-3)]">
                  <Check className="h-3.5 w-3.5" /> Saved
                </span>
              )}
              <Button onClick={save} disabled={saving}>
                {saving ? 'Saving...' : existing ? 'Update savings record' : 'Save savings record'}
              </Button>
            </div>
            <p className="mt-2 text-right text-[11px] text-[var(--text-3)]">
              Saving publishes the <strong>whole {dealMonths}-month term</strong> to the dashboard,
              savings and reports — not the basis shown above. Use the Schedule tab to spread it
              over periods and report it by year.
            </p>
          </Card>
        </>
      )}
    </div>
  )
}
