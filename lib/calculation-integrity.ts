export type CalculationIdentity = {
  id?: string | null
  event_id: string | null
  created_at?: string | null
}

export type CalculationDataQuality = {
  duplicateCalculationEvents: number
}

export type CanonicalCalculations<T> = {
  calculations: T[]
  dataQuality: CalculationDataQuality
}

function createdAtMillis(value: string | null | undefined): number {
  if (!value) return Number.POSITIVE_INFINITY
  const parsed = Date.parse(value)
  return Number.isFinite(parsed) ? parsed : Number.POSITIVE_INFINITY
}

function precedes<T extends CalculationIdentity>(candidate: T, current: T): boolean {
  const candidateTime = createdAtMillis(candidate.created_at)
  const currentTime = createdAtMillis(current.created_at)
  if (candidateTime !== currentTime) return candidateTime < currentTime

  // created_at should normally make the choice. The id tie-breaker keeps
  // malformed fixtures and imported data deterministic when timestamps match.
  return String(candidate.id ?? '').localeCompare(String(current.id ?? '')) < 0
}

/**
 * A project has one mutable savings calculation. The database enforces that
 * invariant, but readers still defend against malformed imports or stale
 * snapshots: use the earliest record once and report how many projects were
 * affected instead of silently double counting them.
 */
export function canonicalCalculationsByEvent<T extends CalculationIdentity>(
  calculations: T[],
): CanonicalCalculations<T> {
  const canonicalByEvent = new Map<string, T>()
  const unlinked: T[] = []
  const duplicateEvents = new Set<string>()

  for (const calculation of calculations) {
    if (!calculation.event_id) {
      unlinked.push(calculation)
      continue
    }

    const current = canonicalByEvent.get(calculation.event_id)
    if (!current) {
      canonicalByEvent.set(calculation.event_id, calculation)
      continue
    }

    duplicateEvents.add(calculation.event_id)
    if (precedes(calculation, current)) {
      canonicalByEvent.set(calculation.event_id, calculation)
    }
  }

  return {
    calculations: [...canonicalByEvent.values(), ...unlinked],
    dataQuality: { duplicateCalculationEvents: duplicateEvents.size },
  }
}

export type CalculationReadResult = {
  label: string
  data?: unknown
  error?: { message: string } | null
}

export function calculationLoadError(results: CalculationReadResult[]): string | null {
  const failures = results.filter(result => result.error || result.data === null)
  if (failures.length === 0) return null

  const details = failures
    .map(result => `${result.label}: ${result.error?.message || 'query returned null data without an error'}`)
    .join('; ')

  return `The calculation could not be loaded safely (${details}). Saving is disabled so a second savings record cannot be created.`
}
