export type SupplierAttentionInput = {
  status?: string | null
  risk: string | null
  nextReviewDate: string | null
  performanceNextReviewDate?: string | null
  criticalRiskIssues?: number
  highRiskIssues?: number
}

export type SupplierAttentionAssessment = {
  reasons: string[]
  date: string | null
  priority: number
}

function issueReason(count: number, severity: 'critical' | 'high'): string {
  return `${count} unresolved ${severity} risk ${count === 1 ? 'issue' : 'issues'}`
}

/** One canonical definition used by supplier lists, reports, and the dashboard. */
export function assessSupplierAttention(
  supplier: SupplierAttentionInput,
  asOfDate: string,
): SupplierAttentionAssessment {
  if (supplier.status === 'Inactive') return { reasons: [], date: null, priority: 3 }

  const reasons: string[] = []
  let priority = 1.5

  if (supplier.status === 'Blocked') {
    reasons.push('Blocked')
    priority = Math.min(priority, 0.25)
  }
  if (supplier.status === 'Under Review') {
    reasons.push('Under review')
    priority = Math.min(priority, 1.25)
  }
  if (supplier.risk === 'High') {
    reasons.push('High risk')
    priority = Math.min(priority, 1)
  }
  if (supplier.criticalRiskIssues) {
    reasons.push(issueReason(supplier.criticalRiskIssues, 'critical'))
    priority = Math.min(priority, 0.5)
  }
  if (supplier.highRiskIssues) {
    reasons.push(issueReason(supplier.highRiskIssues, 'high'))
    priority = Math.min(priority, 1)
  }

  const relationshipReviewOverdue = Boolean(supplier.nextReviewDate && supplier.nextReviewDate < asOfDate)
  const performanceReviewOverdue = Boolean(supplier.performanceNextReviewDate && supplier.performanceNextReviewDate < asOfDate)
  if (relationshipReviewOverdue) reasons.push('Relationship review overdue')
  if (performanceReviewOverdue) reasons.push('Performance review overdue')

  const date = [
    relationshipReviewOverdue ? supplier.nextReviewDate : null,
    performanceReviewOverdue ? supplier.performanceNextReviewDate : null,
  ].filter((value): value is string => Boolean(value)).sort()[0] || null

  return { reasons, date, priority }
}

export function supplierNeedsAttention(supplier: SupplierAttentionInput, asOfDate: string): boolean {
  return assessSupplierAttention(supplier, asOfDate).reasons.length > 0
}
