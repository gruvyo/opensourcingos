import { num, reportedSavings, type SavingsCalcRow } from './savings/index.ts'
import { canonicalCalculationsByEvent, type CalculationDataQuality } from './calculation-integrity.ts'

export type SupplierPortfolioEvent = {
  id: string
  awardedSupplierId: string | null
}

export type SupplierPortfolioCalculation = SavingsCalcRow & {
  event_id: string | null
  baseline_total_amount?: number | null
  created_at?: string | null
}

export type SupplierPortfolioRealization = {
  event_id: string | null
  projected_savings?: number | null
  realized_savings?: number | null
}

export type SupplierPortfolioValue = {
  supplierId: string
  awards: number
  spendAddressed: number
  spendShare: number | null
  estimatedSavings: number
  executedSavings: number
  totalSavings: number
  savingsShare: number | null
  realizedSavings: number
  realizationRate: number | null
}

export type SupplierPortfolioResult = {
  values: Map<string, SupplierPortfolioValue>
  dataQuality: CalculationDataQuality
}

export type SupplierAttributionTotals = {
  negotiatedSavings: number
  realizedSavings: number
}

export function supplierPortfolioValues(
  events: SupplierPortfolioEvent[],
  calculations: SupplierPortfolioCalculation[],
  realizationPeriods: SupplierPortfolioRealization[],
): SupplierPortfolioResult {
  const supplierByEvent = new Map(events.map(event => [event.id, event.awardedSupplierId]))
  const values = new Map<string, SupplierPortfolioValue>()
  const canonical = canonicalCalculationsByEvent(calculations)

  const getValue = (supplierId: string) => {
    const current = values.get(supplierId) ?? {
      supplierId,
      awards: 0,
      spendAddressed: 0,
      spendShare: null,
      estimatedSavings: 0,
      executedSavings: 0,
      totalSavings: 0,
      savingsShare: null,
      realizedSavings: 0,
      realizationRate: null,
    }
    values.set(supplierId, current)
    return current
  }

  for (const event of events) {
    if (!event.awardedSupplierId) continue
    getValue(event.awardedSupplierId).awards += 1
  }

  for (const calculation of canonical.calculations) {
    if (!calculation.event_id) continue
    const supplierId = supplierByEvent.get(calculation.event_id)
    if (!supplierId) continue
    const current = getValue(supplierId)
    const savings = reportedSavings(calculation)
    current.spendAddressed += num(calculation.baseline_total_amount)
    current.totalSavings += savings
    if (calculation.calculation_status === 'executed') current.executedSavings += savings
    else current.estimatedSavings += savings
  }

  const projectedBySupplier = new Map<string, number>()
  for (const period of realizationPeriods) {
    if (!period.event_id) continue
    const supplierId = supplierByEvent.get(period.event_id)
    if (!supplierId) continue
    const current = getValue(supplierId)
    current.realizedSavings += num(period.realized_savings)
    projectedBySupplier.set(
      supplierId,
      (projectedBySupplier.get(supplierId) || 0) + num(period.projected_savings),
    )
  }

  const totalSpend = Array.from(values.values()).reduce((sum, value) => sum + value.spendAddressed, 0)
  const totalSavings = Array.from(values.values()).reduce((sum, value) => sum + value.totalSavings, 0)
  for (const value of values.values()) {
    const projected = projectedBySupplier.get(value.supplierId) || 0
    value.spendShare = totalSpend > 0 ? (value.spendAddressed / totalSpend) * 100 : null
    value.savingsShare = totalSavings !== 0 ? (value.totalSavings / totalSavings) * 100 : null
    value.realizationRate = projected > 0 ? (value.realizedSavings / projected) * 100 : null
  }

  return { values, dataQuality: canonical.dataQuality }
}

/**
 * Supplier-profile money uses the same award relationship and canonical
 * calculation selection as the portfolio. Incumbent relationships remain
 * useful history, but never receive the winning supplier's commercial value.
 */
export function supplierAttributionTotals(
  supplierId: string,
  events: SupplierPortfolioEvent[],
  calculations: SupplierPortfolioCalculation[],
  realizationPeriods: SupplierPortfolioRealization[],
): SupplierAttributionTotals {
  const attributed = supplierPortfolioValues(events, calculations, realizationPeriods)
    .values.get(supplierId)

  return {
    negotiatedSavings: attributed?.totalSavings ?? 0,
    realizedSavings: attributed?.realizedSavings ?? 0,
  }
}
