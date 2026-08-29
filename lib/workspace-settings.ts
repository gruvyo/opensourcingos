import { formatCurrency, formatDashboardCurrency, formatDashboardReduction, formatDate, formatReduction } from './utils.ts'

export const DEFAULT_WORKSPACE_CURRENCY = 'USD'
export const DEFAULT_WORKSPACE_LOCALE = 'en-US'
export const DEFAULT_WORKSPACE_TIMEZONE = 'America/Chicago'

export function workspaceFormatters(
  currencyCode = DEFAULT_WORKSPACE_CURRENCY,
  locale = DEFAULT_WORKSPACE_LOCALE,
) {
  return {
    currencyCode,
    locale,
    formatCurrency: (amount: number | null | undefined) => formatCurrency(amount, currencyCode, locale),
    formatDashboardCurrency: (amount: number | null | undefined) => formatDashboardCurrency(amount, currencyCode, locale),
    formatDashboardReduction: (amount: number | null | undefined) => formatDashboardReduction(amount, currencyCode, locale),
    formatReduction: (amount: number | null | undefined) => formatReduction(amount, currencyCode, locale),
    formatDate: (date: string | null | undefined) => formatDate(date, locale),
  }
}
