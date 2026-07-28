// =====================================================================
// scripts/verify-savings.mts — the money math, checked against the source.
// =====================================================================
//   npm run verify
//
// Every figure asserted here comes from one of two places:
//
//   1. The locked methodology's reference deal (HANDOFF.md section 2), which
//      exists to prove that per-month, per-year and whole-term all agree.
//   2. Joe's own spreadsheet, cell for cell:
//      research/raw/project-savings-tab-ideation-and-calculation.xlsx
//      — sheets `savings-monthly`, `savings-annually`, `savings-one-time`
//      and the `chart-pivots` year buckets.
//
// If this file and the spreadsheet ever disagree, the spreadsheet is right.
// Run it before shipping anything that touches lib/savings.
// =====================================================================

import {
  chainSavings,
  termRates,
  generateSchedule,
  scheduleTotals,
  scheduleByYear,
  defaultPeriodCount,
  type PeriodType,
  type ScheduleRates,
} from '../lib/savings/index.ts'

let failures = 0
let checks = 0

/** Money compares to the cent. Anything closer than that is float noise. */
const CENT = 0.005

function near(label: string, actual: number | null, expected: number | null, tol = CENT) {
  checks++
  const ok =
    actual === null || expected === null
      ? actual === expected
      : Math.abs(actual - expected) <= tol
  if (!ok) {
    failures++
    console.error(`  FAIL  ${label}\n        expected ${expected}\n        actual   ${actual}`)
  }
}

function eq(label: string, actual: unknown, expected: unknown) {
  checks++
  if (actual !== expected) {
    failures++
    console.error(`  FAIL  ${label}\n        expected ${String(expected)}\n        actual   ${String(actual)}`)
  }
}

function section(title: string) {
  console.log(`\n${title}`)
}

// ---------------------------------------------------------------------
// 1. THE CHAIN INVARIANT — all three bases must give the same answer.
//    Reference deal: baseline 1,000,000/12mo, opening 1,200,000/12mo,
//    final 2,700,000/36mo -> 300,000 / 600,000 / 900,000.
// ---------------------------------------------------------------------
section('1. Chain invariant (reference deal, HANDOFF section 2)')
{
  const b = termRates(1_000_000, 12)
  const o = termRates(1_200_000, 12)
  const f = termRates(2_700_000, 36)
  const dealMonths = 36

  const bases: [string, number, number, number][] = [
    ['per month x 36', b.perMonth * 36, o.perMonth * 36, f.perMonth * 36],
    ['per year x 3', b.perYear * 3, o.perYear * 3, f.perYear * 3],
    ['whole term', b.perMonth * dealMonths, o.perMonth * dealMonths, f.perMonth * dealMonths],
  ]
  for (const [name, baseline, opening, final] of bases) {
    const c = chainSavings({ baseline, opening, final })
    near(`${name}: reduction`, c.reduction, 300_000)
    near(`${name}: avoidance`, c.avoidance, 600_000)
    near(`${name}: total`, c.total, 900_000)
    near(`${name}: total === reduction + avoidance`, c.total, (c.reduction ?? 0) + c.avoidance, 1e-6)
  }
}

// ---------------------------------------------------------------------
// 2. JOE'S SPREADSHEET — the deal the schedule sheets are built on.
//    baseline 1,000,000/12  opening 1,200,000/12  final 2,750,000/36
// ---------------------------------------------------------------------
const DEAL_MONTHS = 36
const RATES: ScheduleRates = {
  baselinePerMonth: termRates(1_000_000, 12).perMonth,   // 83,333.33
  openingPerMonth: termRates(1_200_000, 12).perMonth,    // 100,000
  finalPerMonth: termRates(2_750_000, 36).perMonth,      // 76,388.89
}
const START_MONTH = 8   // August
const START_YEAR = 2026

/** Every period type books the same money — that is the whole point. */
const GRAND = { baseline: 3_000_000, opening: 3_600_000, final: 2_750_000, reduction: 250_000, avoidance: 600_000, total: 850_000 }

function schedule(periodType: PeriodType, periodCount: number) {
  return generateSchedule(
    { startMonth: START_MONTH, startYear: START_YEAR, periodType, periodCount, dealMonths: DEAL_MONTHS },
    RATES,
  )
}

function assertGrandTotals(label: string, rows: ReturnType<typeof schedule>) {
  const t = scheduleTotals(rows)
  near(`${label}: baseline total`, t.baseline, GRAND.baseline)
  near(`${label}: opening total`, t.opening, GRAND.opening)
  near(`${label}: final total`, t.final, GRAND.final)
  near(`${label}: cost reduction total`, t.reduction, GRAND.reduction)
  near(`${label}: cost avoidance total`, t.avoidance, GRAND.avoidance)
  near(`${label}: total savings`, t.total, GRAND.total)
  near(`${label}: months booked`, t.months, DEAL_MONTHS)
}

section('2. Sheet `savings-monthly` (36 monthly periods from August 2026)')
{
  const rows = schedule('monthly', 36)
  eq('row count', rows.length, 36)

  // Sheet row 15 — the first period, and every period is identical.
  const r1 = rows[0]
  eq('period 1 month', r1.month, 8)
  eq('period 1 year', r1.year, 2026)
  near('period 1 baseline (E15)', r1.baseline, 83_333.333333333328)
  near('period 1 opening  (F15)', r1.opening, 100_000)
  near('period 1 final    (G15)', r1.final, 76_388.888888888891)
  near('period 1 reduction (H15)', r1.reduction, 6_944.444444444438)
  near('period 1 avoidance (I15)', r1.avoidance, 16_666.666666666672)
  near('period 1 total     (J15)', r1.total, 23_611.111111111109)

  // The calendar rolls over correctly: period 6 is January 2027 (sheet row 20).
  eq('period 6 month', rows[5].month, 1)
  eq('period 6 year', rows[5].year, 2027)
  // Last period is July 2029 (sheet row 50).
  eq('period 36 month', rows[35].month, 7)
  eq('period 36 year', rows[35].year, 2029)

  assertGrandTotals('monthly', rows)

  // chart-pivots A2:C5 — the year buckets, which is what FY reporting reads.
  const byYear = scheduleByYear(rows)
  eq('year bucket count', byYear.length, 4)
  near('2026 avoidance', byYear[0].avoidance, 83_333.333333333358)
  near('2026 reduction', byYear[0].reduction, 34_722.22222222219)
  near('2027 avoidance', byYear[1].avoidance, 200_000.00000000012)
  near('2027 reduction', byYear[1].reduction, 83_333.333333333256)
  near('2028 avoidance', byYear[2].avoidance, 200_000.00000000012)
  near('2028 reduction', byYear[2].reduction, 83_333.333333333256)
  near('2029 avoidance', byYear[3].avoidance, 116_666.6666666667)
  near('2029 reduction', byYear[3].reduction, 48_611.111111111066)
  eq('2026 holds 5 months (Aug-Dec)', byYear[0].months, 5)
  eq('2029 holds 7 months (Jan-Jul)', byYear[3].months, 7)
}

/**
 * Every period is booked PER MONTH from the month it starts, so a period that
 * straddles a year boundary splits across both years. The fiscal-year report
 * therefore does NOT depend on how the schedule was sliced.
 *
 * Ruling, 2026-07-27: this deliberately diverges from the `chart-pivots`
 * blocks at A23:C25 and A38:C39, which attributed a whole annual period to
 * the year it started in. The monthly pivot at A2:C5 is the correct shape,
 * and Annual and One-Time now reproduce it exactly.
 */
function assertSameYearBuckets(label: string, a: ReturnType<typeof scheduleByYear>, b: ReturnType<typeof scheduleByYear>) {
  eq(`${label}: same number of years`, a.length, b.length)
  for (let i = 0; i < Math.min(a.length, b.length); i++) {
    eq(`${label}: year ${a[i].year}`, a[i].year, b[i].year)
    eq(`${label}: ${a[i].year} months`, a[i].months, b[i].months)
    near(`${label}: ${a[i].year} reduction`, a[i].reduction, b[i].reduction)
    near(`${label}: ${a[i].year} avoidance`, a[i].avoidance, b[i].avoidance)
    near(`${label}: ${a[i].year} total`, a[i].total, b[i].total)
  }
}

section('2b. The fiscal year is the same whichever way the deal is sliced')
{
  const monthlyYears = scheduleByYear(schedule('monthly', 36))
  assertSameYearBuckets('annual vs monthly', scheduleByYear(schedule('annual', 3)), monthlyYears)
  assertSameYearBuckets('one-time vs monthly', scheduleByYear(schedule('one_time', 1)), monthlyYears)

  // Concretely: an August start puts 5 months in the first year, never 12.
  const annualYears = scheduleByYear(schedule('annual', 3))
  eq('annual: 2026 holds 5 months, not a whole year', annualYears[0].months, 5)
  eq('annual: spans four calendar years like the monthly schedule', annualYears.length, 4)
  near('annual: 2026 avoidance', annualYears[0].avoidance, 83_333.333333333358)
  near('annual: 2026 reduction', annualYears[0].reduction, 34_722.22222222219)
}

section('3. Sheet `savings-annually` (3 annual periods from August 2026)')
{
  const rows = schedule('annual', 3)
  eq('row count', rows.length, 3)

  const r1 = rows[0]
  near('period 1 baseline (E15)', r1.baseline, 1_000_000)
  near('period 1 opening  (F15)', r1.opening, 1_200_000)
  near('period 1 final    (G15)', r1.final, 916_666.66666666674)
  near('period 1 reduction (H15)', r1.reduction, 83_333.333333333256)
  near('period 1 avoidance (I15)', r1.avoidance, 200_000)
  near('period 1 total     (J15)', r1.total, 283_333.33333333326)

  // The sheet repeats the start month and steps the year: Aug 26, Aug 27, Aug 28.
  eq('period 2 is August 2027', `${rows[1].month}/${rows[1].year}`, '8/2027')
  eq('period 3 is August 2028', `${rows[2].month}/${rows[2].year}`, '8/2028')

  assertGrandTotals('annual', rows)
  // Year buckets are asserted in section 2b: they must match the monthly
  // schedule exactly, NOT the coarse chart-pivots block at A23:C25.
}

section('4. Sheet `savings-one-time` (a single period)')
{
  const rows = schedule('one_time', 1)
  eq('row count', rows.length, 1)
  near('baseline (E15)', rows[0].baseline, 3_000_000)
  near('opening  (F15)', rows[0].opening, 3_600_000)
  near('final    (G15)', rows[0].final, 2_750_000)
  near('reduction (H15)', rows[0].reduction, 249_999.99999999977)
  near('avoidance (I15)', rows[0].avoidance, 600_000)
  near('total     (J15)', rows[0].total, 849_999.99999999977)
  assertGrandTotals('one-time', rows)

  // A single 36-month row still spreads across the four calendar years it
  // covers — it does NOT all land in the start year (chart-pivots A38:C39).
  const byYear = scheduleByYear(rows)
  eq('one row still spans four years', byYear.length, 4)
  eq('2026 holds 5 months', byYear[0].months, 5)
  near('2026 reduction', byYear[0].reduction, 34_722.22222222219)
  near('2026 avoidance', byYear[0].avoidance, 83_333.333333333358)
  near('year buckets add back', byYear.reduce((s, b) => s + b.total, 0), GRAND.total)
}

// ---------------------------------------------------------------------
// 5. THE SCHEDULE MUST NOT INVENT OR LOSE MONEY.
// ---------------------------------------------------------------------
section('5. A term that is not a whole number of years')
{
  // 30 months on an annual schedule: 12 + 12 + a 6-month stub, NOT 3 full years.
  const dealMonths = 30
  const rates: ScheduleRates = { ...RATES, finalPerMonth: termRates(2_291_666.67, 30).perMonth }
  const count = defaultPeriodCount('annual', dealMonths)
  eq('default annual period count for 30 months', count, 3)

  const annual = generateSchedule(
    { startMonth: 1, startYear: 2026, periodType: 'annual', periodCount: count, dealMonths }, rates)
  eq('third period is a 6-month stub', annual[2].months, 6)

  const monthly = generateSchedule(
    { startMonth: 1, startYear: 2026, periodType: 'monthly', periodCount: dealMonths, dealMonths }, rates)
  const oneTime = generateSchedule(
    { startMonth: 1, startYear: 2026, periodType: 'one_time', periodCount: 1, dealMonths }, rates)

  const a = scheduleTotals(annual), m = scheduleTotals(monthly), o = scheduleTotals(oneTime)
  near('annual total === monthly total', a.total, m.total)
  near('one-time total === monthly total', o.total, m.total)
  near('annual reduction === monthly reduction', a.reduction, m.reduction)
  near('months booked === deal term', a.months, dealMonths)

  // And it equals the plain whole-term chain, which is what the Calculations
  // tab shows. The schedule is a view of that number, never a second opinion.
  const wholeTerm = chainSavings({
    baseline: (rates.baselinePerMonth ?? 0) * dealMonths,
    opening: (rates.openingPerMonth ?? 0) * dealMonths,
    final: rates.finalPerMonth * dealMonths,
  })
  near('schedule total === whole-term chain total', m.total, wholeTerm.total)
}

section('6. Periods scheduled past the end of the term book nothing')
{
  const rows = generateSchedule(
    { startMonth: 1, startYear: 2026, periodType: 'monthly', periodCount: 40, dealMonths: 36 }, RATES)
  eq('row count honours the request', rows.length, 40)
  eq('period 37 books zero months', rows[36].months, 0)
  near('period 37 books zero savings', rows[36].total, 0)
  near('grand total is still the whole-term figure', scheduleTotals(rows).total, GRAND.total)
}

section('7. Missing anchors collapse, they do not error')
{
  // No baseline: the whole span is avoidance and reduction is NOT APPLICABLE.
  const noBaseline = generateSchedule(
    { startMonth: 1, startYear: 2026, periodType: 'monthly', periodCount: 36, dealMonths: 36 },
    { ...RATES, baselinePerMonth: null })
  eq('every row reports reduction n/a', noBaseline.every(r => r.reduction === null), true)
  const nb = scheduleTotals(noBaseline)
  eq('total reduction is n/a, not zero', nb.reduction, null)
  near('total avoidance absorbs the whole span', nb.avoidance, GRAND.total)
  near('total is unchanged', nb.total, GRAND.total)

  // No opening: the total collapses to the reduction.
  const noOpening = generateSchedule(
    { startMonth: 1, startYear: 2026, periodType: 'monthly', periodCount: 36, dealMonths: 36 },
    { ...RATES, openingPerMonth: null })
  const no = scheduleTotals(noOpening)
  near('avoidance is zero', no.avoidance, 0)
  near('total collapses to reduction', no.total, GRAND.reduction)
}

section('8. A cost increase stays an increase')
{
  // Final above baseline: reduction is negative and is never sign-flipped.
  const rows = generateSchedule(
    { startMonth: 1, startYear: 2026, periodType: 'annual', periodCount: 1, dealMonths: 12 },
    { baselinePerMonth: 10_000, openingPerMonth: 11_000, finalPerMonth: 12_000 })
  near('reduction is negative', rows[0].reduction, -24_000)
  near('avoidance is positive', rows[0].avoidance, 12_000)
  near('total = reduction + avoidance', rows[0].total, -12_000)
}

// ---------------------------------------------------------------------
// PROFESSIONAL SERVICES — the short and the fractional term.
// Consulting does not run in whole years. These two shapes are the ones a
// period model gets wrong: a term SHORTER than one period, and a term that
// is one and a half of them.
// ---------------------------------------------------------------------
section('9. A 4-month implementation project (term shorter than one period)')
{
  // Net new consulting: nothing was being spent before, so there is NO
  // baseline. Vendor opened at 130,000; signed at 100,000 for 4 months.
  const dealMonths = 4
  const rates: ScheduleRates = {
    baselinePerMonth: null,
    openingPerMonth: termRates(130_000, 4).perMonth,   // 32,500
    finalPerMonth: termRates(100_000, 4).perMonth,     // 25,000
  }
  const spec = (periodType: PeriodType, periodCount: number) =>
    generateSchedule({ startMonth: 3, startYear: 2026, periodType, periodCount, dealMonths }, rates)

  eq('monthly default count', defaultPeriodCount('monthly', dealMonths), 4)
  eq('annual default count is ONE, not zero', defaultPeriodCount('annual', dealMonths), 1)
  eq('one-time default count', defaultPeriodCount('one_time', dealMonths), 1)

  const monthly = spec('monthly', 4)
  near('monthly: each period books 7,500', monthly[0].total, 7_500)
  eq('monthly: reduction is n/a with no baseline', monthly[0].reduction, null)

  // The single annual period must book FOUR months, not twelve. Booking a
  // full year here would invent 90,000 of savings that do not exist.
  const annual = spec('annual', 1)
  eq('annual: the one period books 4 months, not 12', annual[0].months, 4)
  near('annual: books the deal, not a year', annual[0].total, 30_000)

  const oneTime = spec('one_time', 1)
  near('one-time: books the deal', oneTime[0].total, 30_000)

  for (const [label, rows] of [['monthly', monthly], ['annual', annual], ['one-time', oneTime]] as const) {
    const t = scheduleTotals(rows)
    near(`${label}: total`, t.total, 30_000)
    near(`${label}: avoidance absorbs the whole span`, t.avoidance, 30_000)
    eq(`${label}: reduction is n/a, not zero`, t.reduction, null)
    near(`${label}: months booked`, t.months, 4)
  }

  // A 4-month project starting in March lands entirely in one year.
  const byYear = scheduleByYear(monthly)
  eq('one year bucket', byYear.length, 1)
  near('2026 total', byYear[0].total, 30_000)
  eq('last period is June 2026', `${monthly[3].month}/${monthly[3].year}`, '6/2026')
}

section('10. An 18-month consulting contract (one and a half periods)')
{
  // Renewal with a real baseline: 600,000 over the prior 12 months.
  // Vendor opened at 1,000,000 for 18 months; signed at 810,000.
  const dealMonths = 18
  const rates: ScheduleRates = {
    baselinePerMonth: termRates(600_000, 12).perMonth,     // 50,000
    openingPerMonth: termRates(1_000_000, 18).perMonth,    // 55,555.56
    finalPerMonth: termRates(810_000, 18).perMonth,        // 45,000
  }
  const spec = (periodType: PeriodType, periodCount: number) =>
    generateSchedule({ startMonth: 9, startYear: 2026, periodType, periodCount, dealMonths }, rates)

  // Whole term: baseline 900,000, opening 1,000,000, final 810,000.
  const whole = chainSavings({ baseline: 50_000 * 18, opening: 1_000_000, final: 810_000 })
  near('whole term: reduction', whole.reduction, 90_000)
  near('whole term: avoidance', whole.avoidance, 100_000)
  near('whole term: total', whole.total, 190_000)

  eq('annual default count for 18 months', defaultPeriodCount('annual', dealMonths), 2)

  const monthly = spec('monthly', 18)
  const annual = spec('annual', 2)
  const oneTime = spec('one_time', 1)

  // The second annual period is a SIX-month stub. Rounding it up to a full
  // year would book 63,333 of savings the contract never produces.
  eq('annual period 1 is a full year', annual[0].months, 12)
  eq('annual period 2 is a 6-month stub', annual[1].months, 6)
  near('annual period 1 total', annual[0].total, 126_666.667, 0.01)
  near('annual period 2 total', annual[1].total, 63_333.333, 0.01)

  for (const [label, rows] of [['monthly', monthly], ['annual', annual], ['one-time', oneTime]] as const) {
    const t = scheduleTotals(rows)
    near(`${label}: reduction`, t.reduction, 90_000)
    near(`${label}: avoidance`, t.avoidance, 100_000)
    near(`${label}: total`, t.total, 190_000)
    near(`${label}: months booked`, t.months, 18)
    near(`${label}: agrees with the whole-term chain`, t.total, whole.total)
  }

  // The fiscal-year split, which is the whole point. Starting September 2026
  // the contract straddles THREE calendar years: 4 + 12 + 2 months.
  const byYear = scheduleByYear(monthly)
  eq('spans three calendar years', byYear.length, 3)
  eq('2026 holds 4 months', byYear[0].months, 4)
  eq('2027 holds 12 months', byYear[1].months, 12)
  eq('2028 holds 2 months', byYear[2].months, 2)
  near('FY2026 total', byYear[0].total, 42_222.222, 0.01)
  near('FY2027 total', byYear[1].total, 126_666.667, 0.01)
  near('FY2028 total', byYear[2].total, 21_111.111, 0.01)
  near('year buckets add back to the deal', byYear.reduce((s, b) => s + b.total, 0), 190_000)

  // The annual schedule's 12-month period starts in September, so FOUR of its
  // months fall in 2026 and eight in 2027. Booking the whole period to 2026
  // would round the ending up to a full year -- the exact error the per-month
  // rate exists to prevent. Every slicing gives the same fiscal-year answer.
  assertSameYearBuckets('18mo annual vs monthly', scheduleByYear(annual), byYear)
  assertSameYearBuckets('18mo one-time vs monthly', scheduleByYear(oneTime), byYear)
}

// ---------------------------------------------------------------------
console.log(`\n${failures === 0 ? 'PASS' : 'FAIL'} — ${checks - failures}/${checks} checks passed`)
process.exit(failures === 0 ? 0 : 1)
