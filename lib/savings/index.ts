// =====================================================================
// lib/savings — THE SINGLE SOURCE OF TRUTH for procurement savings math.
// =====================================================================
// Every dashboard, report, and savings screen MUST compute its numbers
// through the functions here — never with an inline `.reduce()`. Before
// this module existed, "Total Savings" was re-implemented four different
// ways across the app and the figures drifted apart. If you need a new
// savings number, add it here so every screen agrees.
//
// Methodology reference: ASSESSMENT.md, Appendix A.
// =====================================================================

// ---- Loose row shapes (match the DB columns; tolerate nulls) ----------

/**
 * Workflow stages that mean a deal is still IN THE PIPELINE — its savings are a
 * forecast, not a booked result. Everything else counts as booked.
 * Keep in step with the calculation_status CHECK constraint.
 */
export const FORECAST_STATUSES = ['identified', 'negotiated'] as const
export const BOOKED_STATUSES = ['contracted', 'realized'] as const

/** Is this calculation still a forecast (pipeline), rather than a booked result? */
export function isForecast(c: SavingsCalcRow): boolean {
  const s = (c.calculation_status || '').toLowerCase()
  return (FORECAST_STATUSES as readonly string[]).includes(s)
}

export interface SavingsCalcRow {
  id?: string
  event_id?: string | null
  savings_type?: string | null
  calculation_status?: string | null
  gross_savings_amount?: number | null
  cost_reduction_amount?: number | null
  cost_avoidance_amount?: number | null
  net_savings_amount?: number | null
  savings_start_date?: string | null
  savings_end_date?: string | null
  // Optional: when the parent event's currency is joined onto the calc.
  currency_code?: string | null
  fx_rate_to_usd?: number | null
  // Optional: the joined event (some queries embed it instead of event_id).
  event?: unknown
}

export interface EventLiteRow {
  id: string
  event_name?: string | null
  event_status?: string | null
  contract_start_date?: string | null
  currency_code?: string | null
  fx_rate_to_usd?: number | null
  category?: unknown
  business_unit?: unknown
}

export type RealizationClass = 'Realized' | 'Accrued'

// ---- Tiny safe helpers -----------------------------------------------

/** Coerce anything to a finite number; null/undefined/NaN/Infinity -> 0. */
export function num(x: unknown): number {
  const n = typeof x === 'number' ? x : Number(x)
  return Number.isFinite(n) ? n : 0
}

/** Supabase embeds to-one relations as an array OR an object; normalize. */
export function getFirst<T = any>(obj: unknown): T | null {
  if (!obj) return null
  if (Array.isArray(obj)) return (obj[0] as T) ?? null
  return obj as T
}

function nameFrom(rel: unknown, key: string, fallback: string): string {
  const r = getFirst<Record<string, unknown>>(rel)
  const v = r?.[key]
  return typeof v === 'string' && v ? v : fallback
}

// ---- Core per-line / per-calc formulas --------------------------------

/** Extended amount for a line: unit price × quantity. */
export function lineExtended(unitPrice: unknown, quantity: unknown): number {
  return num(unitPrice) * num(quantity)
}

/** Annualize an extended amount given a contract term in months. */
export function annualized(extended: unknown, termMonths: unknown): number {
  const t = num(termMonths)
  if (t <= 0) return 0 // guard zero AND negative terms
  return (num(extended) * 12) / t
}

/** Gross savings = baseline spend − awarded spend. */
export function grossSavings(baselineTotal: unknown, awardTotal: unknown): number {
  return num(baselineTotal) - num(awardTotal)
}

/**
 * Savings % — denominator is BASELINE spend (never total or awarded spend).
 * Returns 0 when baseline ≤ 0 (undefined rather than a divide-by-zero).
 */
export function savingsPct(gross: unknown, baselineTotal: unknown): number {
  const base = num(baselineTotal)
  if (base <= 0) return 0
  return (num(gross) / base) * 100
}

/** Convert an amount to the reporting currency (USD) using the row's FX rate. */
export function toReportingUsd(amount: unknown, fxRateToUsd: unknown): number {
  const rate = num(fxRateToUsd)
  return num(amount) * (rate > 0 ? rate : 1)
}

/**
 * THE canonical "reported total savings" for a single calculation.
 * One definition, used by every table and card. This holds the CHAIN TOTAL
 * (Opening − Final) — see chainSavings() below, which is what writes it.
 */
export function reportedSavings(c: SavingsCalcRow): number {
  return num(c.gross_savings_amount)
}

// ---- THE CHAIN (the locked savings methodology) -----------------------

/** Anchors accept strings too (form inputs); `present()` and `num()` coerce safely.
 *  An empty string is treated as NOT CAPTURED, never as zero. */
export interface ChainAnchors {
  /** The vendor's opening proposal. null/undefined/'' = not captured. */
  opening?: number | string | null
  /** Current spend / baseline. null/undefined/'' = no baseline anchor. */
  baseline?: number | string | null
  /** The final signed offer. */
  final?: number | string | null
}

export interface ChainResult {
  /** Baseline − Final. Hard, hits the P&L. MAY BE NEGATIVE (a real cost increase).
   *  null means NOT APPLICABLE (no baseline anchor) — a distinct state from zero. */
  reduction: number | null
  /** Opening − Baseline. Soft. */
  avoidance: number
  /** Opening − Final. The headline. Always === reduction + avoidance. */
  total: number
}

/**
 * THE CHAIN — three anchors, Opening → Baseline → Final.
 *
 *   Cost Reduction = Baseline − Final    (hard; may legitimately be negative)
 *   Cost Avoidance = Opening  − Baseline (soft)
 *   Total          = Opening  − Final    = Reduction + Avoidance, exactly.
 *
 * Total is the headline because it is the only figure that cannot be moved by
 * choosing a flattering baseline. Missing anchors COLLAPSE segments rather than
 * erroring:
 *   • no baseline → the whole span is avoidance; reduction is NOT APPLICABLE
 *     (null), which is distinct from both zero and unknown.
 *   • no opening  → Total equals Reduction.
 *
 * A negative reduction is never sign-flipped and never relabelled as savings.
 */
export function chainSavings({ opening, baseline, final }: ChainAnchors): ChainResult {
  const present = (v: unknown) =>
    v !== null && v !== undefined && v !== '' && Number.isFinite(Number(v))

  const hasOpening = present(opening)
  const hasBaseline = present(baseline)
  const O = num(opening)
  const B = num(baseline)
  const F = num(final)

  if (hasOpening && hasBaseline) {
    const reduction = B - F
    const avoidance = O - B
    return { reduction, avoidance, total: reduction + avoidance }
  }
  if (hasOpening) {
    // No baseline anchor: the entire span books as avoidance.
    const avoidance = O - F
    return { reduction: null, avoidance, total: avoidance }
  }
  if (hasBaseline) {
    // No opening captured: Total collapses to Reduction.
    const reduction = B - F
    return { reduction, avoidance: 0, total: reduction }
  }
  return { reduction: null, avoidance: 0, total: 0 }
}

// ---- Realized vs Accrued (ONE rule for the whole app) -----------------

/**
 * Classify a calculation as Realized (savings period has started) or Accrued
 * (not yet started). Canonical rule, replacing the 3 divergent versions:
 *   1. use savings_start_date if present;
 *   2. else fall back to the parent event's contract_start_date;
 *   3. Realized iff that date <= now; otherwise Accrued (incl. no date at all).
 */
export function classifyRealization(
  c: SavingsCalcRow,
  contractStartByEventId: Map<string, string | null>,
  now: Date = new Date(),
): RealizationClass {
  let effective = c.savings_start_date || null
  if (!effective && c.event_id) effective = contractStartByEventId.get(c.event_id) || null
  if (effective && new Date(effective) <= now) return 'Realized'
  return 'Accrued'
}

// ---- Portfolio rollup (dashboard / savings / reports all use this) -----

export interface YearBucket {
  year: string
  costReduction: number
  costAvoidance: number
  total: number
}

export interface PortfolioRollup {
  totalSavings: number
  totalCostReduction: number
  totalCostAvoidance: number
  realized: number
  accrued: number
  /** Savings on deals still in the pipeline (identified/negotiated) — a FORECAST. */
  forecast: number
  /** Savings on deals that reached contracted/realized — BOOKED. */
  booked: number
  /** How many calculations sit in each bucket. */
  forecastCount: number
  bookedCount: number
  /** Gross savings grouped by savings_type — always sums to totalSavings. */
  byType: { name: string; value: number }[]
  /** Gross savings grouped by the event's category (matched by event_id). */
  byCategory: { name: string; value: number }[]
  /** Gross savings + project count grouped by the event's business unit. */
  byBusinessUnit: { name: string; value: number; count: number }[]
  /** Savings prorated across calendar years (dynamic range, no rounding drift). */
  byYear: YearBucket[]
  /** Gross savings of calcs with no dates — surfaced, not silently dropped. */
  unscheduled: number
  /** True when byType sums back to totalSavings (a self-consistency check). */
  reconciles: boolean
}

export interface RollupOptions {
  now?: Date
  /** Cap byCategory to the top N (0 = no cap). Default 0. */
  topCategories?: number
}

/**
 * The one rollup. Pass the savings calculations and the events they belong to;
 * every headline number, breakdown, and chart series comes back consistent.
 */
export function portfolioRollup(
  calcs: SavingsCalcRow[],
  events: EventLiteRow[],
  opts: RollupOptions = {},
): PortfolioRollup {
  const now = opts.now ?? new Date()
  const eventById = new Map<string, EventLiteRow>()
  const contractStartByEventId = new Map<string, string | null>()
  for (const e of events) {
    eventById.set(e.id, e)
    contractStartByEventId.set(e.id, e.contract_start_date ?? null)
  }

  let totalSavings = 0
  let totalCostReduction = 0
  let totalCostAvoidance = 0
  let realized = 0
  let accrued = 0
  let forecast = 0
  let booked = 0
  let forecastCount = 0
  let bookedCount = 0
  const typeMap = new Map<string, number>()
  const catMap = new Map<string, number>()
  const buMap = new Map<string, { value: number; count: number }>()

  for (const c of calcs) {
    const gross = reportedSavings(c)
    totalSavings += gross
    totalCostReduction += num(c.cost_reduction_amount)
    totalCostAvoidance += num(c.cost_avoidance_amount)

    if (classifyRealization(c, contractStartByEventId, now) === 'Realized') realized += gross
    else accrued += gross

    // Pipeline vs booked, driven by workflow stage (not by date).
    if (isForecast(c)) { forecast += gross; forecastCount++ }
    else { booked += gross; bookedCount++ }

    const type = c.savings_type || 'Unspecified'
    typeMap.set(type, (typeMap.get(type) || 0) + gross)

    const event = c.event_id ? eventById.get(c.event_id) : null
    const catName = nameFrom(event?.category, 'category_name', 'Uncategorized')
    catMap.set(catName, (catMap.get(catName) || 0) + gross)
  }

  // Business-unit rollup: iterate events (each event counts once) and attribute
  // its savings by event_id (NOT by event_name, which mis-attributed before).
  const savingsByEventId = new Map<string, number>()
  for (const c of calcs) {
    if (!c.event_id) continue
    savingsByEventId.set(c.event_id, (savingsByEventId.get(c.event_id) || 0) + reportedSavings(c))
  }
  for (const e of events) {
    const bu = nameFrom(e.business_unit, 'business_unit_name', 'Unassigned')
    const existing = buMap.get(bu) || { value: 0, count: 0 }
    buMap.set(bu, {
      value: existing.value + (savingsByEventId.get(e.id) || 0),
      count: existing.count + 1,
    })
  }

  let byCategory = Array.from(catMap.entries())
    .map(([name, value]) => ({ name, value }))
    .sort((a, b) => b.value - a.value)
  if (opts.topCategories && opts.topCategories > 0) {
    byCategory = byCategory.slice(0, opts.topCategories)
  }

  const byType = Array.from(typeMap.entries())
    .map(([name, value]) => ({ name, value }))
    .sort((a, b) => b.value - a.value)

  const byBusinessUnit = Array.from(buMap.entries())
    .map(([name, { value, count }]) => ({ name, value, count }))
    .sort((a, b) => b.value - a.value)

  const { byYear, unscheduled } = prorateByYear(calcs)

  // Self-consistency: the type breakdown must add back to the headline total.
  const typeSum = byType.reduce((s, t) => s + t.value, 0)
  const reconciles = Math.abs(typeSum - totalSavings) < 0.01

  return {
    totalSavings,
    totalCostReduction,
    totalCostAvoidance,
    realized,
    accrued,
    forecast,
    booked,
    forecastCount,
    bookedCount,
    byType,
    byCategory,
    byBusinessUnit,
    byYear,
    unscheduled,
    reconciles,
  }
}

const DAY_MS = 1000 * 60 * 60 * 24

/**
 * Prorate each calc's savings across the calendar years its savings period
 * spans, weighted by the number of days that fall in each year. Fixes the old
 * version's three flaws: (1) hardcoded 2026–2030 window → dynamic range;
 * (2) rounding each year independently → keep full precision, round only at
 * display; (3) silently dropping undated calcs → returned as `unscheduled`.
 */
export function prorateByYear(calcs: SavingsCalcRow[]): { byYear: YearBucket[]; unscheduled: number } {
  const buckets = new Map<number, YearBucket>()
  let unscheduled = 0

  const ensure = (y: number): YearBucket => {
    let b = buckets.get(y)
    if (!b) {
      b = { year: String(y), costReduction: 0, costAvoidance: 0, total: 0 }
      buckets.set(y, b)
    }
    return b
  }

  for (const c of calcs) {
    const total = num(c.gross_savings_amount)
    if (!c.savings_start_date || !c.savings_end_date) {
      unscheduled += total
      continue
    }
    const start = new Date(c.savings_start_date)
    const end = new Date(c.savings_end_date)
    if (isNaN(start.getTime()) || isNaN(end.getTime()) || end < start) {
      unscheduled += total
      continue
    }
    const cr = num(c.cost_reduction_amount)
    const ca = num(c.cost_avoidance_amount)
    const totalDays = Math.max(1, Math.round((end.getTime() - start.getTime()) / DAY_MS) + 1)

    for (let y = start.getFullYear(); y <= end.getFullYear(); y++) {
      const yearStart = new Date(y, 0, 1)
      const yearEnd = new Date(y, 11, 31)
      const overlapStart = start > yearStart ? start : yearStart
      const overlapEnd = end < yearEnd ? end : yearEnd
      if (overlapStart > overlapEnd) continue
      const overlapDays = Math.max(0, Math.round((overlapEnd.getTime() - overlapStart.getTime()) / DAY_MS) + 1)
      const fraction = overlapDays / totalDays
      const b = ensure(y)
      b.costReduction += cr * fraction
      b.costAvoidance += ca * fraction
      b.total += total * fraction
    }
  }

  const byYear = Array.from(buckets.values()).sort((a, b) => Number(a.year) - Number(b.year))
  return { byYear, unscheduled }
}

// ---- Realization (negotiated → realized lifecycle) --------------------

export interface RealizationPeriodRow {
  projected_savings?: number | null
  realized_savings?: number | null
  leakage_amount?: number | null
  actual_amount?: number | null
  realization_status?: string | null
  event_id?: string | null
}

export interface RealizationRollup {
  totalProjected: number
  totalRealized: number
  totalLeakage: number
  /** realized ÷ projected, as a percentage (0 when nothing projected). */
  realizationRate: number
  periodCount: number
}

/**
 * Roll up realization periods into the negotiated-vs-realized story.
 * Same math as the per-event Realization tab, so the portfolio view agrees.
 */
export function realizationRollup(periods: RealizationPeriodRow[]): RealizationRollup {
  let totalProjected = 0
  let totalRealized = 0
  let totalLeakage = 0
  for (const p of periods) {
    totalProjected += num(p.projected_savings)
    totalRealized += num(p.realized_savings)
    totalLeakage += num(p.leakage_amount)
  }
  const realizationRate = totalProjected > 0 ? (totalRealized / totalProjected) * 100 : 0
  return { totalProjected, totalRealized, totalLeakage, realizationRate, periodCount: periods.length }
}
