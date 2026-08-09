import type { SupplierPortfolioValue } from './supplier-portfolio.ts'

export type SupplierSegmentDimension = 'Preferred status' | 'Diversity' | 'Relationship risk' | 'Supplier status'

export type SupplierSegmentInput = {
  id: string
  supplierStatus: string | null
  riskRating: string | null
  preferred: boolean
  diverse: boolean
}

export type SupplierSegment = {
  label: string
  suppliers: number
  awardedSuppliers: number
  awards: number
  spendAddressed: number
  spendShare: number | null
  estimatedSavings: number
  executedSavings: number
  totalSavings: number
  savingsShare: number | null
  realizedSavings: number
}

function segmentLabel(supplier: SupplierSegmentInput, dimension: SupplierSegmentDimension): string {
  if (dimension === 'Preferred status') return supplier.preferred ? 'Preferred' : 'Standard'
  if (dimension === 'Diversity') return supplier.diverse ? 'Diverse' : 'Not diverse'
  if (dimension === 'Relationship risk') return supplier.riskRating || 'Unrated'
  return supplier.supplierStatus || 'Active'
}

export function supplierPortfolioSegments(
  suppliers: SupplierSegmentInput[],
  values: Map<string, SupplierPortfolioValue>,
  dimension: SupplierSegmentDimension,
): SupplierSegment[] {
  const segments = new Map<string, SupplierSegment>()

  for (const supplier of suppliers) {
    const label = segmentLabel(supplier, dimension)
    const segment = segments.get(label) || {
      label,
      suppliers: 0,
      awardedSuppliers: 0,
      awards: 0,
      spendAddressed: 0,
      spendShare: null,
      estimatedSavings: 0,
      executedSavings: 0,
      totalSavings: 0,
      savingsShare: null,
      realizedSavings: 0,
    }
    const value = values.get(supplier.id)
    segment.suppliers += 1
    if (value?.awards) segment.awardedSuppliers += 1
    segment.awards += value?.awards || 0
    segment.spendAddressed += value?.spendAddressed || 0
    segment.estimatedSavings += value?.estimatedSavings || 0
    segment.executedSavings += value?.executedSavings || 0
    segment.totalSavings += value?.totalSavings || 0
    segment.realizedSavings += value?.realizedSavings || 0
    segments.set(label, segment)
  }

  const rows = Array.from(segments.values())
  const totalSpend = rows.reduce((sum, segment) => sum + segment.spendAddressed, 0)
  const totalSavings = rows.reduce((sum, segment) => sum + segment.totalSavings, 0)
  for (const segment of rows) {
    segment.spendShare = totalSpend > 0 ? (segment.spendAddressed / totalSpend) * 100 : null
    segment.savingsShare = totalSavings !== 0 ? (segment.totalSavings / totalSavings) * 100 : null
  }

  return rows.sort((a, b) => b.spendAddressed - a.spendAddressed || a.label.localeCompare(b.label))
}
