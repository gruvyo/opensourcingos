export const MONEY_DECIMAL_PLACES = 2
export const MONEY_SCALE = 100

/**
 * Convert a finite amount to integer cents using decimal half-away-from-zero
 * semantics (the same tie rule PostgreSQL uses for numeric round()). Working
 * in cents keeps allocation and reconciliation independent of binary floating
 * point addition.
 */
export function moneyToCents(amount: number): number {
  if (!Number.isFinite(amount)) throw new RangeError('Money must be a finite number')

  const sign = amount < 0 ? -1 : 1
  const scaled = Math.abs(amount) * MONEY_SCALE
  // Values such as 1.005 can land just below their decimal half-cent in binary.
  // The tolerance only cancels representation noise; it is many orders of
  // magnitude smaller than a real fraction of a cent.
  const tolerance = Number.EPSILON * Math.max(1, scaled) * 4
  const cents = Math.floor(scaled + 0.5 + tolerance)
  if (!Number.isSafeInteger(cents)) throw new RangeError('Money exceeds safe cent precision')
  return sign * cents
}

export function centsToMoney(cents: number): number {
  if (!Number.isSafeInteger(cents)) throw new RangeError('Cents must be a safe integer')
  return cents / MONEY_SCALE
}

export function roundMoney(amount: number): number {
  return centsToMoney(moneyToCents(amount))
}

export function hasCentPrecision(amount: number): boolean {
  if (!Number.isFinite(amount)) return false
  return Math.abs(amount - roundMoney(amount)) < 1e-9
}

export interface AllocateMoneyOptions {
  /** Exact column total to preserve. Defaults to the sum of the raw values. */
  target?: number
  /** Preferred residual row. Falls back to the last non-null row. */
  sinkIndex?: number
}

/**
 * Round each non-null amount to cents and place the aggregate residual in one
 * deterministic row. This is the accounting-grade schedule rule: detail rows
 * remain two-decimal values and their integer-cent sum exactly matches the
 * approved column total.
 */
export function allocateMoney(
  values: Array<number | null>,
  options: AllocateMoneyOptions = {},
): Array<number | null> {
  const present = values.flatMap((value, index) => value === null ? [] : [index])
  if (present.length === 0) return values.map(() => null)

  const preferred = options.sinkIndex
  const sinkIndex = preferred !== undefined && values[preferred] !== null
    ? preferred
    : present[present.length - 1]

  const target = options.target ?? present.reduce((sum, index) => sum + (values[index] ?? 0), 0)
  const targetCents = moneyToCents(target)
  const allocatedCents = values.map(value => value === null ? null : moneyToCents(value))
  const regularCents = allocatedCents.reduce<number>(
    (sum, cents, index) => index === sinkIndex || cents === null ? sum : sum + cents,
    0,
  )
  allocatedCents[sinkIndex] = targetCents - regularCents

  return allocatedCents.map(cents => cents === null ? null : centsToMoney(cents))
}

/** Stable machine-readable money for CSVs and other exact-detail exports. */
export function fixedMoney(amount: number): string {
  return roundMoney(amount).toFixed(MONEY_DECIMAL_PLACES)
}
