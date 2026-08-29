import { formatCurrency, formatDate, formatReduction } from './utils.ts'
import { fixedMoney } from './money.ts'
import { csvCell } from './csv.ts'

export type ReportDisplayFormat = 'text' | 'number' | 'currency' | 'reduction' | 'date' | 'status' | 'percent' | 'score'
export type ReportDisplayValue = string | number | null

function numeric(value: ReportDisplayValue): number {
  const parsed = typeof value === 'number' ? value : Number(value)
  return Number.isFinite(parsed) ? parsed : 0
}

export function reportColumnLabel(
  label: string,
  format: ReportDisplayFormat | undefined,
  currencyCode: string,
): string {
  return format === 'currency' || format === 'reduction'
    ? `${label} (${currencyCode})`
    : label
}

/** Locale-neutral numeric text keeps CSV money exact and summable. */
export function reportCsvMoney(value: ReportDisplayValue): string {
  return fixedMoney(numeric(value))
}

// Exactly the text our numeric exporters emit: fixedMoney and
// reportReductionExport (whose only non-numeric suffix is " (partial)").
const TRUSTED_NUMERIC_TEXT = /^-?\d+(\.\d+)?( \(partial\))?$/

/**
 * Numeric report cells stay numeric in spreadsheets, including negatives.
 * The formula exemption keys on the runtime value, never the column format:
 * any string that is not provably numeric-exporter output is neutralized.
 */
export function reportCsvCell(value: ReportDisplayValue): string {
  return csvCell(value, typeof value === 'string' && !TRUSTED_NUMERIC_TEXT.test(value))
}

export function formatReportValue(
  value: ReportDisplayValue,
  format: ReportDisplayFormat = 'text',
  annotation?: ReportDisplayValue,
  currencyCode = 'USD',
  locale = 'en-US',
): string {
  if (format === 'currency') return formatCurrency(numeric(value), currencyCode, locale)
  if (format === 'reduction') {
    const formatted = formatReduction(value === null ? null : numeric(value), currencyCode, locale)
    return annotation === 'partial' ? `${formatted}*` : formatted
  }
  if (format === 'date') return formatDate(typeof value === 'string' ? value : null, locale)
  if (format === 'number') return numeric(value).toLocaleString(locale)
  if (format === 'score') return value === null ? '—' : `${numeric(value).toLocaleString(locale, { minimumFractionDigits: 1, maximumFractionDigits: 1 })} / 5`
  if (format === 'percent') return value === null ? '—' : `${numeric(value).toLocaleString(locale, { minimumFractionDigits: 1, maximumFractionDigits: 1 })}%`
  if (value === null || value === '') return '—'
  return String(value)
}
