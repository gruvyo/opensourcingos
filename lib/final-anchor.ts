import { hasCentPrecision, roundMoney } from './money.ts'

export type FinalAnchorValidation =
  | { status: 'error'; value: null; message: string }
  | { status: 'confirm-zero'; value: 0; message: string }
  | { status: 'valid'; value: number; message: null }

/**
 * Final is a required commercial anchor, never an optional amount that may be
 * silently coerced to zero. A genuine zero is valid, but only after the user
 * explicitly confirms it because it books the full baseline as reduction.
 */
export function validateFinalAnchor(
  rawValue: unknown,
  options: { zeroConfirmed?: boolean } = {},
): FinalAnchorValidation {
  if (
    rawValue === null
    || rawValue === undefined
    || (typeof rawValue === 'string' && rawValue.trim() === '')
  ) {
    return { status: 'error', value: null, message: 'Enter the Final amount before saving.' }
  }

  const amount = typeof rawValue === 'number' ? rawValue : Number(rawValue)
  if (!Number.isFinite(amount)) {
    return { status: 'error', value: null, message: 'Enter a valid Final amount.' }
  }
  if (amount < 0) {
    return { status: 'error', value: null, message: 'The Final amount cannot be negative.' }
  }
  let exactAmount: number
  try {
    if (!hasCentPrecision(amount)) {
      return { status: 'error', value: null, message: 'Use no more than two decimal places for the Final amount.' }
    }
    exactAmount = roundMoney(amount)
  } catch {
    return { status: 'error', value: null, message: 'The Final amount is outside the supported money range.' }
  }
  if (exactAmount === 0 && !options.zeroConfirmed) {
    return {
      status: 'confirm-zero',
      value: 0,
      message: 'A $0.00 Final books the full baseline as savings. Confirm that the signed Final is truly zero.',
    }
  }

  return { status: 'valid', value: exactAmount, message: null }
}
