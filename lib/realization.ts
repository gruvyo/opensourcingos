export type RealizationStatus =
  | 'Pending'
  | 'In Progress'
  | 'Realized'
  | 'Partially Realized'
  | 'Not Realized'
  | 'Leaked'

export type RealizationLegs = {
  projectedReduction: number | null
  projectedAvoidance: number | null
  realizedReduction: number | null
  realizedAvoidance: number | null
}

export type DerivedRealization = {
  projectedTotal: number | null
  realizedTotal: number | null
  reductionLeakage: number | null
  status: RealizationStatus
}

function totalOrNull(left: number | null, right: number | null): number | null {
  return left === null && right === null ? null : (left ?? 0) + (right ?? 0)
}

/**
 * Realization follows the same two legs as savings: reduction and avoidance.
 * Leakage is a like-for-like reduction shortfall only. Avoidance that has not
 * yet been realized affects progress, but can never masquerade as leakage.
 */
export function deriveRealization(legs: RealizationLegs): DerivedRealization {
  const projectedTotal = totalOrNull(legs.projectedReduction, legs.projectedAvoidance)
  const realizedTotal = totalOrNull(legs.realizedReduction, legs.realizedAvoidance)
  const reductionLeakage = legs.projectedReduction === null || legs.realizedReduction === null
    ? null
    : Math.max(legs.projectedReduction - legs.realizedReduction, 0)

  if (legs.realizedReduction === null && legs.realizedAvoidance === null) {
    return { projectedTotal, realizedTotal, reductionLeakage, status: 'Pending' }
  }

  const reductionExpected = legs.projectedReduction !== null && legs.projectedReduction !== 0
  const avoidanceExpected = legs.projectedAvoidance !== null && legs.projectedAvoidance !== 0
  if ((reductionExpected && legs.realizedReduction === null)
    || (avoidanceExpected && legs.realizedAvoidance === null)) {
    return { projectedTotal, realizedTotal, reductionLeakage, status: 'In Progress' }
  }

  if ((realizedTotal ?? 0) <= 0) {
    return {
      projectedTotal,
      realizedTotal,
      reductionLeakage,
      status: (reductionLeakage ?? 0) > 0 ? 'Leaked' : 'Not Realized',
    }
  }

  const reductionAchieved = !reductionExpected
    || (legs.realizedReduction !== null && legs.realizedReduction >= (legs.projectedReduction ?? 0))
  const avoidanceAchieved = !avoidanceExpected
    || (legs.realizedAvoidance !== null && legs.realizedAvoidance >= (legs.projectedAvoidance ?? 0))

  return {
    projectedTotal,
    realizedTotal,
    reductionLeakage,
    status: reductionAchieved && avoidanceAchieved ? 'Realized' : 'Partially Realized',
  }
}

export function reductionFromActualSpend(
  baselineAmount: number | null,
  actualAmount: number | null,
  projectedReduction: number | null,
): number | null {
  if (baselineAmount === null || actualAmount === null || projectedReduction === null) return null
  return baselineAmount - actualAmount
}
