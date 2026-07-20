import { clsx, type ClassValue } from 'clsx'
import { twMerge } from 'tailwind-merge'

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs))
}

export function formatCurrency(amount: number | null | undefined): string {
  if (amount === null || amount === undefined) return '$0'
  return new Intl.NumberFormat('en-US', {
    style: 'currency',
    currency: 'USD',
    minimumFractionDigits: 0,
    maximumFractionDigits: 0,
  }).format(amount)
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
  const colors: Record<string, string> = {
    'Pipeline': 'bg-blue-100 text-blue-700',
    'Scoped': 'bg-blue-100 text-blue-700',
    'Baseline Pending': 'bg-amber-100 text-amber-700',
    'Baseline Approved': 'bg-green-100 text-green-700',
    'In Market': 'bg-purple-100 text-purple-700',
    'Negotiation': 'bg-purple-100 text-purple-700',
    'Award Recommended': 'bg-indigo-100 text-indigo-700',
    'Award Approved': 'bg-indigo-100 text-indigo-700',
    'Contracted': 'bg-emerald-100 text-emerald-700',
    'Implemented': 'bg-emerald-100 text-emerald-700',
    'Realized': 'bg-green-100 text-green-700',
    'Finance Validated': 'bg-green-100 text-green-700',
    'Closed': 'bg-gray-100 text-gray-700',
    'Cancelled': 'bg-red-100 text-red-700',
    'Rejected': 'bg-red-100 text-red-700',
  }
  return colors[status] || 'bg-gray-100 text-gray-700'
}
