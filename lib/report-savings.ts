import { fixedMoney, roundMoney } from './money.ts'
import { num, reportedSavings, type SavingsCalcRow } from './savings/index.ts'

export type ReductionCoverage = 'complete' | 'partial' | 'none'

export type ReportSavingsTotals = {
  reduction: number | null
  reductionKnown: number
  reductionMissing: number
  avoidance: number
  total: number
  estimated: number
  executed: number
}

export function emptyReportSavingsTotals(): ReportSavingsTotals {
  return {
    reduction: null,
    reductionKnown: 0,
    reductionMissing: 0,
    avoidance: 0,
    total: 0,
    estimated: 0,
    executed: 0,
  }
}

export function addReportSavingsCalculation(
  totals: ReportSavingsTotals,
  calculation: SavingsCalcRow,
): ReportSavingsTotals {
  const reductionMissing = calculation.cost_reduction_amount === null
    || calculation.cost_reduction_amount === undefined
  const reported = reportedSavings(calculation)

  return {
    reduction: reductionMissing
      ? totals.reduction
      : roundMoney(num(totals.reduction) + num(calculation.cost_reduction_amount)),
    reductionKnown: totals.reductionKnown + (reductionMissing ? 0 : 1),
    reductionMissing: totals.reductionMissing + (reductionMissing ? 1 : 0),
    avoidance: roundMoney(totals.avoidance + num(calculation.cost_avoidance_amount)),
    total: roundMoney(totals.total + reported),
    estimated: roundMoney(totals.estimated + (calculation.calculation_status === 'executed' ? 0 : reported)),
    executed: roundMoney(totals.executed + (calculation.calculation_status === 'executed' ? reported : 0)),
  }
}

export function mergeReportSavingsTotals(
  left: ReportSavingsTotals,
  right: ReportSavingsTotals,
): ReportSavingsTotals {
  const known = left.reductionKnown + right.reductionKnown
  return {
    reduction: known > 0 ? roundMoney(num(left.reduction) + num(right.reduction)) : null,
    reductionKnown: known,
    reductionMissing: left.reductionMissing + right.reductionMissing,
    avoidance: roundMoney(left.avoidance + right.avoidance),
    total: roundMoney(left.total + right.total),
    estimated: roundMoney(left.estimated + right.estimated),
    executed: roundMoney(left.executed + right.executed),
  }
}

export function reductionCoverage(totals: ReportSavingsTotals): ReductionCoverage {
  if (totals.reductionMissing > 0 && totals.reductionKnown === 0) return 'none'
  if (totals.reductionMissing > 0) return 'partial'
  return 'complete'
}

/** No calculations is a measured zero; calculations with no baseline are n/a. */
export function reportReductionValue(totals: ReportSavingsTotals): number | null {
  return reductionCoverage(totals) === 'none' ? null : totals.reduction ?? 0
}

export function reportReductionExport(
  value: number | null,
  coverage: ReductionCoverage,
): string {
  if (value === null || coverage === 'none') return 'n/a'
  const exact = fixedMoney(value)
  return coverage === 'partial' ? `${exact} (partial)` : exact
}
