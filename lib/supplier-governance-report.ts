export type SupplierPerformanceReviewSummaryRow = {
  id: string
  supplier_id: string
  review_date: string
  created_at: string
  overall_score: number
  next_review_date: string | null
}

export type SupplierRiskSummaryRow = {
  supplier_id: string
  severity: string
  risk_status: string
}

export type SupplierGovernanceSummary = {
  latestReviewDate: string | null
  latestOverallScore: number | null
  performanceNextReviewDate: string | null
  unresolvedRisks: number
  criticalRisks: number
  highRisks: number
  mediumRisks: number
  lowRisks: number
}

function emptySummary(): SupplierGovernanceSummary {
  return {
    latestReviewDate: null,
    latestOverallScore: null,
    performanceNextReviewDate: null,
    unresolvedRisks: 0,
    criticalRisks: 0,
    highRisks: 0,
    mediumRisks: 0,
    lowRisks: 0,
  }
}

export function supplierGovernanceSummaries(
  reviews: SupplierPerformanceReviewSummaryRow[],
  risks: SupplierRiskSummaryRow[],
): Map<string, SupplierGovernanceSummary> {
  const summaries = new Map<string, SupplierGovernanceSummary>()
  const latestReviewBySupplier = new Map<string, SupplierPerformanceReviewSummaryRow>()

  for (const review of reviews) {
    const current = latestReviewBySupplier.get(review.supplier_id)
    if (!current
      || review.review_date > current.review_date
      || (review.review_date === current.review_date && review.created_at > current.created_at)
      || (review.review_date === current.review_date && review.created_at === current.created_at && review.id > current.id)) {
      latestReviewBySupplier.set(review.supplier_id, review)
    }
  }

  for (const [supplierId, review] of latestReviewBySupplier) {
    const summary = summaries.get(supplierId) || emptySummary()
    summary.latestReviewDate = review.review_date
    summary.latestOverallScore = review.overall_score
    summary.performanceNextReviewDate = review.next_review_date
    summaries.set(supplierId, summary)
  }

  for (const risk of risks) {
    if (risk.risk_status === 'Resolved') continue
    const summary = summaries.get(risk.supplier_id) || emptySummary()
    summary.unresolvedRisks += 1
    if (risk.severity === 'Critical') summary.criticalRisks += 1
    else if (risk.severity === 'High') summary.highRisks += 1
    else if (risk.severity === 'Medium') summary.mediumRisks += 1
    else if (risk.severity === 'Low') summary.lowRisks += 1
    summaries.set(risk.supplier_id, summary)
  }

  return summaries
}
