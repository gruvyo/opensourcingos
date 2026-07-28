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

// ---- TERM NORMALISATION ------------------------------------------------
// Every anchor carries an amount and a term in MONTHS. Normalising to a
// monthly rate is what lets a 12-month baseline be compared with a 36-month
// offer. Deliberately no dates: no day-counting, no timezone edge cases.
// Escalators are priced into the amount by the buyer, so a flat rate is exact.

export interface TermRates {
  /** amount / months. 0 when the term is missing or non-positive. */
  perMonth: number
  /** perMonth * 12 — the annual run-rate. */
  perYear: number
  /** The full amount over the whole term (what was entered). */
  perTerm: number
  /** False when the term is missing/invalid, so callers can show "—" not "0". */
  known: boolean
}

/** Derive monthly and annual run-rates from an amount and a term in months. */
export function termRates(amount: unknown, months: unknown): TermRates {
  const amt = num(amount)
  const m = num(months)
  if (m <= 0) return { perMonth: 0, perYear: 0, perTerm: amt, known: false }
  const perMonth = amt / m
  return { perMonth, perYear: perMonth * 12, perTerm: amt, known: true }
}

/** Basis on which a set of anchors is compared. */
export type RateBasis = 'perMonth' | 'perYear' | 'perTerm'

/** Pick one basis off a TermRates. Keeps callers from hand-picking fields. */
export function onBasis(r: TermRates, basis: RateBasis): number {
  return basis === 'perMonth' ? r.perMonth : basis === 'perYear' ? r.perYear : r.perTerm
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

// ---- THE SAVINGS SCHEDULE (the period model) --------------------------
// A deal does not save its money all at once — it saves it period by period,
// and the CFO wants the figure for THIS fiscal year, not for the whole term.
// So the deal is spread over a schedule: a start month/year, a period type,
// and a period count produce one row per period, each carrying the same three
// anchors and running the same chain.
//
// Joe's model (project-savings-tab-ideation-and-calculation.xlsx) has three
// period types, and the point of it is that ALL THREE GIVE THE SAME TOTAL:
//
//   Monthly  36 rows x the per-month rate
//   Annual    3 rows x the per-year rate
//   One-Time  1 row  x the whole-term amount
//
// That falls out of one formula — every row books `perMonth x months_in_row` —
// because per-year is just per-month x 12 and whole-term is per-month x term.
// There is no second definition of savings here; the chain does all the work.

/** How the deal's savings are spread over time. */
export type PeriodType = 'monthly' | 'annual' | 'one_time'

export const PERIOD_TYPES: { value: PeriodType; label: string }[] = [
  { value: 'monthly', label: 'Monthly' },
  { value: 'annual', label: 'Annual' },
  { value: 'one_time', label: 'One-Time' },
]

/**
 * Months covered by ONE period of this type. One-Time collapses the whole deal
 * into a single row, so its period is the deal term itself.
 */
export function periodMonths(type: PeriodType, dealMonths: number): number {
  if (type === 'monthly') return 1
  if (type === 'annual') return 12
  return Math.max(1, Math.round(num(dealMonths)))
}

/**
 * How many periods it takes to cover the deal term exactly. A 30-month deal on
 * an annual schedule needs 3 rows — the third being a 6-month stub, not a full
 * year — which is why the row's own span is what drives its amount.
 */
export function defaultPeriodCount(type: PeriodType, dealMonths: number): number {
  const d = Math.max(1, Math.round(num(dealMonths)))
  if (type === 'one_time') return 1
  return Math.max(1, Math.ceil(d / periodMonths(type, d)))
}

/** The schedule header: where it starts, how it is sliced, how many slices. */
export interface ScheduleSpec {
  /** 1-12. */
  startMonth: number
  startYear: number
  periodType: PeriodType
  periodCount: number
  /** The deal term — the Final offer's term. Bounds what the schedule may book. */
  dealMonths: number
}

/**
 * The three anchors as MONTHLY rates. null means the anchor was never captured,
 * which propagates through the chain as "not applicable" — never as zero.
 */
export interface ScheduleRates {
  baselinePerMonth: number | null
  openingPerMonth: number | null
  finalPerMonth: number
}

export interface SchedulePeriod {
  /** 1-based. */
  periodNumber: number
  /** 1-12. */
  month: number
  year: number
  /** Months of the deal term this row books. Zero past the end of the term. */
  months: number
  baseline: number | null
  opening: number | null
  final: number
  /** May be negative (a real cost increase); null when there is no baseline. */
  reduction: number | null
  avoidance: number
  total: number
}

const MONTH_NAMES = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
]

/** 1-12 -> "August". Out-of-range returns an em dash rather than undefined. */
export function monthName(month: unknown): string {
  const m = Math.round(num(month))
  return m >= 1 && m <= 12 ? MONTH_NAMES[m - 1] : '—'
}

/** Advance a (month, year) pair by n months. Month is 1-12 throughout. */
export function addMonths(month: number, year: number, n: number): { month: number; year: number } {
  const zero = (year * 12) + (Math.round(num(month)) - 1) + Math.round(num(n))
  return { month: (zero % 12) + 1, year: Math.floor(zero / 12) }
}

/**
 * Generate the schedule. Every row books `perMonth x months`, where `months` is
 * how much of the DEAL TERM that row still has left to spend:
 *
 *     months(i) = clamp(dealMonths - i * step, 0, step)
 *
 * The clamp is the honest part. Rows scheduled past the end of the term book
 * ZERO rather than inventing savings the contract cannot produce, and a term
 * that is not a whole number of periods ends in a short final period instead of
 * being rounded up. Both keep the schedule's grand total equal to the
 * whole-term figure on the Calculations tab, for every period type.
 *
 * Rows are a starting point, not a verdict — they are saved and then editable.
 */
export function generateSchedule(spec: ScheduleSpec, rates: ScheduleRates): SchedulePeriod[] {
  const dealMonths = Math.max(0, Math.round(num(spec.dealMonths)))
  const step = periodMonths(spec.periodType, dealMonths)
  const count = Math.max(0, Math.round(num(spec.periodCount)))
  const rows: SchedulePeriod[] = []

  for (let i = 0; i < count; i++) {
    const { month, year } = addMonths(spec.startMonth, spec.startYear, i * step)
    const months = Math.max(0, Math.min(step, dealMonths - i * step))

    const baseline = rates.baselinePerMonth === null ? null : rates.baselinePerMonth * months
    const opening = rates.openingPerMonth === null ? null : rates.openingPerMonth * months
    const final = num(rates.finalPerMonth) * months
    const chain = chainSavings({ baseline, opening, final })

    rows.push({
      periodNumber: i + 1,
      month,
      year,
      months,
      baseline,
      opening,
      final,
      reduction: chain.reduction,
      avoidance: chain.avoidance,
      total: chain.total,
    })
  }
  return rows
}

/** A row as it comes back from the database (numbers may arrive as strings). */
export interface SchedulePeriodRow {
  period_number?: number | null
  period_month?: number | null
  period_year?: number | null
  period_months?: number | null
  baseline_amount?: number | string | null
  opening_amount?: number | string | null
  final_amount?: number | string | null
  cost_reduction_amount?: number | string | null
  cost_avoidance_amount?: number | string | null
  total_savings_amount?: number | string | null
}

export interface ScheduleTotals {
  baseline: number
  opening: number
  final: number
  /** null when NO row has a baseline — not applicable, distinct from zero. */
  reduction: number | null
  avoidance: number
  total: number
  periodCount: number
  /** Months of deal term the schedule actually books. */
  months: number
}

/** Grand totals down the schedule. The column footer, and the reconciliation. */
export function scheduleTotals(rows: SchedulePeriod[]): ScheduleTotals {
  const t: ScheduleTotals = {
    baseline: 0, opening: 0, final: 0,
    reduction: null, avoidance: 0, total: 0,
    periodCount: rows.length, months: 0,
  }
  for (const r of rows) {
    t.baseline += num(r.baseline)
    t.opening += num(r.opening)
    t.final += num(r.final)
    t.avoidance += num(r.avoidance)
    t.total += num(r.total)
    t.months += num(r.months)
    // Stays null only while every row is null, so "no baseline anywhere" reads
    // as not-applicable while a single grounded row makes the sum meaningful.
    if (r.reduction !== null) t.reduction = num(t.reduction) + r.reduction
  }
  return t
}

export interface ScheduleYearBucket {
  year: number
  /** null means NOT APPLICABLE — no period in this year had a baseline anchor.
   *  Distinct from zero, exactly as it is on a single period and on the total. */
  reduction: number | null
  avoidance: number
  total: number
  /** How many of the deal's months fall in this calendar year. */
  months: number
}

/**
 * Group the schedule by CALENDAR YEAR — the fiscal-year report.
 * (FY = calendar year for this business; it ran Oct-Sep historically, so any
 * figure labelled FY24 elsewhere is ambiguous and should not be trusted.)
 *
 * EVERY PERIOD IS BOOKED PER MONTH, from the month it starts. A period that
 * straddles a year boundary is split across both years by the months that
 * actually fall in each — a 12-month period starting in September puts four
 * months in the first year and eight in the second.
 *
 * Attributing a whole period to the year it starts in would round the ending
 * up to a full year, which is precisely what deriving a per-month rate exists
 * to prevent. It also made the fiscal-year report depend on how the schedule
 * happened to be sliced. It no longer does: Monthly, Annual and One-Time all
 * produce the SAME year buckets for the same deal, which is the invariant
 * worth protecting here.
 */
export function scheduleByYear(rows: SchedulePeriod[]): ScheduleYearBucket[] {
  const buckets = new Map<number, ScheduleYearBucket>()
  const ensure = (y: number): ScheduleYearBucket => {
    let b = buckets.get(y)
    if (!b) { b = { year: y, reduction: null, avoidance: 0, total: 0, months: 0 }; buckets.set(y, b) }
    return b
  }

  for (const r of rows) {
    const span = Math.max(0, Math.round(num(r.months)))

    // A period booking no months has nothing to spread. It still carries money
    // if someone hand-edited a past-term row, so book that to its start year
    // rather than dividing by zero or dropping it silently.
    if (span === 0) {
      const b = ensure(Math.round(num(r.year)))
      if (r.reduction !== null) b.reduction = num(b.reduction) + r.reduction
      b.avoidance += num(r.avoidance)
      b.total += num(r.total)
      continue
    }

    // Per-month rates for THIS period, then one month at a time into its own
    // calendar year. Whatever the row carries — generated or hand-edited — is
    // what gets spread; the split is never recomputed here.
    const perMonth = {
      reduction: r.reduction === null ? null : r.reduction / span,
      avoidance: num(r.avoidance) / span,
      total: num(r.total) / span,
    }
    for (let k = 0; k < span; k++) {
      const { year } = addMonths(r.month, r.year, k)
      const b = ensure(year)
      // Stays null while every period contributing to this year is null, so a
      // year with no baseline reads "n/a" rather than a misleading zero.
      if (perMonth.reduction !== null) b.reduction = num(b.reduction) + perMonth.reduction
      b.avoidance += perMonth.avoidance
      b.total += perMonth.total
      b.months += 1
    }
  }
  return Array.from(buckets.values()).sort((a, b) => a.year - b.year)
}

/** Normalize DB rows into SchedulePeriods so every reader shares one shape. */
export function toSchedulePeriods(rows: SchedulePeriodRow[]): SchedulePeriod[] {
  const nullable = (v: unknown) => (v === null || v === undefined || v === '' ? null : num(v))
  return rows.map((r, i) => ({
    periodNumber: Math.round(num(r.period_number)) || i + 1,
    month: Math.round(num(r.period_month)),
    year: Math.round(num(r.period_year)),
    months: num(r.period_months),
    baseline: nullable(r.baseline_amount),
    opening: nullable(r.opening_amount),
    final: num(r.final_amount),
    reduction: nullable(r.cost_reduction_amount),
    avoidance: num(r.cost_avoidance_amount),
    total: num(r.total_savings_amount),
  }))
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

// ---- THE PORTFOLIO FISCAL YEAR (Step 4) -------------------------------
// The Schedule tab answers "when does THIS deal save?". The CFO asks it of the
// whole portfolio, and there the awkward fact is that only some projects have
// been scheduled. The rest carry nothing but a savings_calculation with a start
// and an end date.
//
// The old answer was prorateByYear(), which weights each calendar year by the
// number of DAYS it holds. That disagrees with the schedule, which books whole
// months — on the reference deal (900,000 over 36 months from August 2026) the
// two differ by up to 912 in a single year while both summing to 900,000. Two
// screens, same deal, different fiscal-year numbers. That is exactly the drift
// this module exists to prevent.
//
// So there is ONE path: every calculation becomes schedule periods, real ones
// where they exist and synthesised monthly ones where they do not, and
// scheduleByYear() produces every year figure in the app. What differs between
// the two sources is CONFIDENCE, not method — so confidence is reported
// separately rather than blended silently into the total.

/**
 * Months spanned by a start and end date, inclusive, counted in whole months.
 * 2026-01-01 to 2028-12-31 is 36. Returns 0 if either date is missing or the
 * range is inverted. Deliberately month arithmetic, never day arithmetic.
 */
export function monthSpan(startISO?: string | null, endISO?: string | null): number {
  if (!startISO || !endISO) return 0
  const s = new Date(String(startISO).slice(0, 10) + 'T00:00:00')
  const e = new Date(String(endISO).slice(0, 10) + 'T00:00:00')
  if (isNaN(s.getTime()) || isNaN(e.getTime())) return 0
  const months = (e.getFullYear() * 12 + e.getMonth()) - (s.getFullYear() * 12 + s.getMonth()) + 1
  return months > 0 ? months : 0
}

/**
 * Synthesise monthly schedule periods for a calculation that has no real ones,
 * so it can go through exactly the same year grouping as a scheduled deal.
 * Returns [] when the calc has no usable dates — those are `unscheduled` and
 * are surfaced, never silently dropped.
 */
export function calcToPeriods(c: SavingsCalcRow): SchedulePeriod[] {
  const months = monthSpan(c.savings_start_date, c.savings_end_date)
  if (months <= 0) return []
  const start = new Date(String(c.savings_start_date).slice(0, 10) + 'T00:00:00')

  const total = num(c.gross_savings_amount)
  const avoidance = num(c.cost_avoidance_amount)
  // null stays null all the way through — not applicable is not zero.
  const reduction = c.cost_reduction_amount === null || c.cost_reduction_amount === undefined
    ? null : num(c.cost_reduction_amount)

  const rows: SchedulePeriod[] = []
  for (let i = 0; i < months; i++) {
    const { month, year } = addMonths(start.getMonth() + 1, start.getFullYear(), i)
    rows.push({
      periodNumber: i + 1,
      month,
      year,
      months: 1,
      baseline: null,
      opening: null,
      final: 0,
      reduction: reduction === null ? null : reduction / months,
      avoidance: avoidance / months,
      total: total / months,
    })
  }
  return rows
}

export interface PortfolioYear extends ScheduleYearBucket {
  /** Of this year's total, how much came from real schedule rows. */
  exact: number
  /** How much was derived from a calculation's start and end dates instead. */
  estimated: number
}

export interface PortfolioByYear {
  years: PortfolioYear[]
  /** Portfolio totals, split by how much can be trusted to the month. */
  exactTotal: number
  estimatedTotal: number
  /** Savings on calculations with no usable dates — cannot be placed in a year. */
  unscheduled: number
  scheduledProjects: number
  estimatedProjects: number
  unscheduledProjects: number
  /** True when every year bucket adds back to the calculations' own total. */
  reconciles: boolean
}

/**
 * THE portfolio fiscal-year rollup. Pass every savings calculation plus the
 * schedule periods that exist, keyed by savings_calculation_id.
 *
 * A calculation with real periods uses them (exact to the month, and edited
 * rows are honoured). One without falls back to synthesised monthly periods
 * from its own dates (right method, weaker input). One with neither is counted
 * in `unscheduled` and reported, because a savings figure that silently fails
 * to appear in any year is the worst outcome available.
 */
export function portfolioByYear(
  calcs: SavingsCalcRow[],
  periodsByCalcId: Map<string, SchedulePeriod[]>,
): PortfolioByYear {
  const buckets = new Map<number, PortfolioYear>()
  let exactTotal = 0, estimatedTotal = 0, unscheduled = 0
  let scheduledProjects = 0, estimatedProjects = 0, unscheduledProjects = 0

  const add = (rows: SchedulePeriod[], exact: boolean) => {
    for (const y of scheduleByYear(rows)) {
      let b = buckets.get(y.year)
      if (!b) {
        b = { year: y.year, reduction: null, avoidance: 0, total: 0, months: 0, exact: 0, estimated: 0 }
        buckets.set(y.year, b)
      }
      if (y.reduction !== null) b.reduction = num(b.reduction) + y.reduction
      b.avoidance += y.avoidance
      b.total += y.total
      b.months += y.months
      if (exact) b.exact += y.total; else b.estimated += y.total
    }
  }

  for (const c of calcs) {
    const real = (c.id && periodsByCalcId.get(c.id)) || null
    if (real && real.length) {
      add(real, true)
      exactTotal += scheduleTotals(real).total
      scheduledProjects++
      continue
    }
    const synth = calcToPeriods(c)
    if (synth.length) {
      add(synth, false)
      estimatedTotal += scheduleTotals(synth).total
      estimatedProjects++
      continue
    }
    unscheduled += reportedSavings(c)
    unscheduledProjects++
  }

  const years = Array.from(buckets.values()).sort((a, b) => a.year - b.year)
  const placed = years.reduce((s, y) => s + y.total, 0)
  const reconciles = Math.abs(placed - (exactTotal + estimatedTotal)) < 0.01

  return {
    years, exactTotal, estimatedTotal, unscheduled,
    scheduledProjects, estimatedProjects, unscheduledProjects, reconciles,
  }
}

export interface YoYRow {
  year: number
  total: number
  reduction: number | null
  avoidance: number
  /** The prior year's total, or null when this is the first year on record. */
  prior: number | null
  /** total − prior. null when there is no prior year. */
  delta: number | null
  /** Percentage change. null when there is no prior year OR the prior year was
   *  zero — growth from nothing is not a percentage, and rendering it as one
   *  (or as Infinity) is how a report starts lying. */
  pct: number | null
}

/** Year-on-year movement. Consecutive years only; gaps are not interpolated. */
export function yearOverYear(years: { year: number; total: number; reduction: number | null; avoidance: number }[]): YoYRow[] {
  const sorted = [...years].sort((a, b) => a.year - b.year)
  return sorted.map((y, i) => {
    const previous = i > 0 && sorted[i - 1].year === y.year - 1 ? sorted[i - 1] : null
    const prior = previous ? previous.total : null
    const delta = prior === null ? null : y.total - prior
    const pct = prior === null || prior === 0 ? null : (delta! / Math.abs(prior)) * 100
    return { year: y.year, total: y.total, reduction: y.reduction, avoidance: y.avoidance, prior, delta, pct }
  })
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
