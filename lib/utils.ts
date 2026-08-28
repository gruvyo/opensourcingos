import { clsx, type ClassValue } from 'clsx'
import { twMerge } from 'tailwind-merge'
import { MONEY_DECIMAL_PLACES } from '@/lib/money'

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs))
}

export function formatCurrency(
  amount: number | null | undefined,
  currencyCode: string = 'USD',
): string {
  // Guard null/undefined AND NaN/Infinity (previously "NaN" could render).
  const value = typeof amount === 'number' && Number.isFinite(amount) ? amount : 0
  return new Intl.NumberFormat('en-US', {
    style: 'currency',
    currency: currencyCode || 'USD',
    minimumFractionDigits: MONEY_DECIMAL_PLACES,
    maximumFractionDigits: MONEY_DECIMAL_PLACES,
  }).format(value)
}

/** Compact whole-dollar presentation reserved for dashboard summaries. */
export function formatDashboardCurrency(
  amount: number | null | undefined,
  currencyCode: string = 'USD',
): string {
  const value = typeof amount === 'number' && Number.isFinite(amount) ? amount : 0
  return new Intl.NumberFormat('en-US', {
    style: 'currency',
    currency: currencyCode || 'USD',
    minimumFractionDigits: 0,
    maximumFractionDigits: 0,
  }).format(value)
}

export function formatDashboardReduction(
  amount: number | null | undefined,
  currencyCode: string = 'USD',
): string {
  if (amount === null || amount === undefined || !Number.isFinite(amount)) return 'n/a'
  return amount < 0
    ? `(${formatDashboardCurrency(Math.abs(amount), currencyCode)})`
    : formatDashboardCurrency(amount, currencyCode)
}

/**
 * THE way to display a Cost Reduction. Two rules from the methodology that
 * plain formatCurrency silently breaks:
 *
 *   null  -> "n/a"          NOT APPLICABLE (no baseline anchor). Rendering it
 *                           as "$0" claims the deal saved nothing hard, when
 *                           the truth is the question does not apply.
 *   < 0   -> "($100,000)"   A real cost increase, in accounting parentheses.
 *                           "-$100,000" reads as a typo; it is never
 *                           sign-flipped and never relabelled as savings.
 *
 * Use this anywhere cost_reduction_amount is shown to a human.
 */
export function formatReduction(
  amount: number | null | undefined,
  currencyCode: string = 'USD',
): string {
  if (amount === null || amount === undefined) return 'n/a'
  if (!Number.isFinite(amount)) return 'n/a'
  return amount < 0
    ? `(${formatCurrency(Math.abs(amount), currencyCode)})`
    : formatCurrency(amount, currencyCode)
}

export function formatDate(date: string | null | undefined): string {
  if (!date) return '—'
  // A bare 'YYYY-MM-DD' is parsed as UTC midnight, which renders as the DAY
  // BEFORE anywhere west of Greenwich — a contract starting 2026-01-01 showed
  // as Dec 31, 2025. These columns are dates, not instants, so pin them to
  // local midnight. Timestamps (which carry a time or a zone) are left alone.
  const localDate = /^\d{4}-\d{2}-\d{2}$/.test(date) ? `${date}T00:00:00` : date
  const d = new Date(localDate)
  if (isNaN(d.getTime())) return '—'
  return d.toLocaleDateString('en-US', {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
  })
}

export function statusColor(status: string): string {
  // Each value carries its own dark-mode classes so status pills are correct
  // in both themes without depending on any global override.
  const blue = 'bg-blue-100 text-blue-700 dark:bg-blue-500/15 dark:text-blue-300'
  const amber = 'bg-amber-100 text-amber-700 dark:bg-amber-500/15 dark:text-amber-300'
  const green = 'bg-green-100 text-green-700 dark:bg-green-500/15 dark:text-green-300'
  const purple = 'bg-purple-100 text-purple-700 dark:bg-purple-500/15 dark:text-purple-300'
  const indigo = 'bg-indigo-100 text-indigo-700 dark:bg-indigo-500/15 dark:text-indigo-300'
  const emerald = 'bg-emerald-100 text-emerald-700 dark:bg-emerald-500/15 dark:text-emerald-300'
  const gray = 'bg-gray-100 text-gray-700 dark:bg-gray-500/20 dark:text-gray-300'
  const red = 'bg-red-100 text-red-700 dark:bg-red-500/15 dark:text-red-300'

  const colors: Record<string, string> = {
    'Pipeline': blue,
    'Scoping & Strategy': blue,
    'In Market': purple,
    'Negotiation': purple,
    'Award & Contracting': indigo,
    'Implementation': emerald,
    'Cancelled': red,
    'Rejected': red,
    'Not Started': gray,
    'In Progress': blue,
    'Pending': amber,
    'On Hold': amber,
    'Complete': green,
  }
  return colors[status] || gray
}
