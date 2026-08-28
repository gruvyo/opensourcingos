export type SavingsPopulationEvent = {
  id: string
  project_type?: string | null
}

export type SavingsPopulationCalculation = {
  id?: string
  event_id?: string | null
}

export type SavingsPopulationPeriod = {
  savings_calculation_id?: string | null
}

export type SavingsPopulationRealization = {
  event_id?: string | null
}

/**
 * Savings are a commercial measure and therefore belong only to Sourcing
 * Projects. Historical null Project Types predate the explicit choice and are
 * treated as Sourcing, matching the rest of the application.
 */
export function isSourcingProject(event: SavingsPopulationEvent): boolean {
  return (event.project_type || 'Sourcing') === 'Sourcing'
}

/**
 * One population boundary for Dashboard, Savings, Reports, supplier money
 * summaries, CSV exports, and realization. Filtering the children from the
 * selected parent IDs makes malformed legacy/API rows fail closed instead of
 * leaking into a headline.
 */
export function sourcingSavingsPopulation<
  Event extends SavingsPopulationEvent,
  Calculation extends SavingsPopulationCalculation,
  Period extends SavingsPopulationPeriod,
  Realization extends SavingsPopulationRealization,
>(
  events: Event[],
  calculations: Calculation[],
  periodRows: Period[] = [],
  realizationRows: Realization[] = [],
) {
  const sourcingEvents = events.filter(isSourcingProject)
  const eventIds = new Set(sourcingEvents.map(event => event.id))
  const sourcingCalculations = calculations.filter(
    calculation => Boolean(calculation.event_id && eventIds.has(calculation.event_id)),
  )
  const calculationIds = new Set(
    sourcingCalculations
      .map(calculation => calculation.id)
      .filter((id): id is string => Boolean(id)),
  )

  return {
    events: sourcingEvents,
    eventIds,
    calculations: sourcingCalculations,
    calculationIds,
    periodRows: periodRows.filter(
      period => Boolean(period.savings_calculation_id && calculationIds.has(period.savings_calculation_id)),
    ),
    realizationRows: realizationRows.filter(
      period => Boolean(period.event_id && eventIds.has(period.event_id)),
    ),
  }
}
