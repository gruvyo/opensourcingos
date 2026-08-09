export type SupplierReadinessInput = {
  relationshipOwner: string | null
  nextReviewDate: string | null
  risk: string | null
}

export type SupplierReadiness = {
  alerts: string[]
  gaps: string[]
  label: string
  priority: number
  state: 'attention' | 'incomplete' | 'ready'
}

export function dateKeyInTimeZone(date: Date, timeZone: string): string {
  let parts: Intl.DateTimeFormatPart[]
  try {
    parts = new Intl.DateTimeFormat('en-US', {
      timeZone,
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
    }).formatToParts(date)
  } catch {
    parts = new Intl.DateTimeFormat('en-US', {
      timeZone: 'UTC',
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
    }).formatToParts(date)
  }
  const values = new Map(parts.map(part => [part.type, part.value]))
  return `${values.get('year')}-${values.get('month')}-${values.get('day')}`
}

export function assessSupplierReadiness(
  supplier: SupplierReadinessInput,
  asOfDate: string,
): SupplierReadiness {
  const alerts: string[] = []
  const gaps: string[] = []

  if (supplier.risk === 'High') alerts.push('High risk')
  if (supplier.nextReviewDate && supplier.nextReviewDate < asOfDate) alerts.push('Review overdue')
  if (!supplier.relationshipOwner) gaps.push('Missing owner')
  if (!supplier.nextReviewDate) gaps.push('Missing review date')
  if (!supplier.risk) gaps.push('Unrated risk')

  if (alerts.length) {
    return {
      alerts,
      gaps,
      label: alerts.join('; '),
      priority: supplier.risk === 'High' ? 0 : 1,
      state: 'attention',
    }
  }

  if (gaps.length) {
    return {
      alerts,
      gaps,
      label: gaps.join('; '),
      priority: 2 + gaps.length * -0.1,
      state: 'incomplete',
    }
  }

  return { alerts, gaps, label: 'Ready', priority: 3, state: 'ready' }
}
