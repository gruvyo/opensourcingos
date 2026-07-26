import { clsx, type ClassValue } from 'clsx'
import { twMerge } from 'tailwind-merge'

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
    minimumFractionDigits: 0,
    maximumFractionDigits: 0,
  }).format(value)
}

export function formatDate(date: string | null | undefined): string {
  if (!date) return '—'
  return new Date(date).toLocaleDateString('en-US', {
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
    'Scoped': blue,
    'Baseline Pending': amber,
    'Baseline Approved': green,
    'In Market': purple,
    'Negotiation': purple,
    'Award Recommended': indigo,
    'Award Approved': indigo,
    'Contracted': emerald,
    'Implemented': emerald,
    'Realized': green,
    'Finance Validated': green,
    'Closed': gray,
    'Cancelled': red,
    'Rejected': red,
    'Not Started': gray,
    'In Progress': blue,
    'Hold': amber,
    'Complete': green,
  }
  return colors[status] || gray
}
