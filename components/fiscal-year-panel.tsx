import Link from 'next/link'
import { clsx } from 'clsx'
import { formatCurrency, formatReduction } from '@/lib/utils'
import { yearOverYear, type PortfolioByYear } from '@/lib/savings'
import { Card } from '@/components/ui/card'
import { TrendingUp, TrendingDown, Minus, Info } from 'lucide-react'

/**
 * The fiscal-year report — the figure the CFO actually asks for, which is never
 * "what is this deal worth" but "what did we save this year".
 *
 * The fiscal year IS the calendar year for this business. It ran Oct-Sep
 * historically, so any figure labelled FY24 in an older document is ambiguous
 * and should not be trusted against this table.
 *
 * Every number here comes from portfolioByYear(), which books whole months from
 * each period's start month. A year is EXACT when it comes from real schedule
 * rows and ESTIMATED when it was derived from a calculation's start and end
 * dates instead. That distinction is shown rather than blended, because a
 * portfolio number that mixes the two without saying so invites a question no
 * one can answer later.
 */
export function FiscalYearPanel({
  data,
  selectedYear,
  basePath,
}: {
  data: PortfolioByYear
  /** null means "all years". */
  selectedYear: number | null
  /** Route the filter links point at, e.g. "/dashboard". */
  basePath: string
}) {
  const rows = yearOverYear(data.years)
  const selected = selectedYear === null ? null : data.years.find(y => y.year === selectedYear) ?? null
  const shown = selectedYear === null ? rows : rows.filter(r => r.year === selectedYear)

  const link = (year: number | null) => (year === null ? basePath : `${basePath}?fy=${year}`)

  return (
    <Card className="p-6">
      <div className="mb-4 flex flex-wrap items-center justify-between gap-3">
        <div>
          <h3 className="text-sm font-semibold uppercase tracking-wider text-[var(--text-3)]">
            Savings by fiscal year
          </h3>
          <p className="mt-1 text-xs text-[var(--text-3)]">
            The fiscal year is the calendar year. Each period books whole months from the month it
            starts, so a deal spanning a year boundary is split across both.
          </p>
        </div>

        {/* Server-rendered filter: plain links, so a fiscal year is a URL you
            can bookmark or paste into an email, and no client JS is needed. */}
        <nav aria-label="Filter by fiscal year" className="flex flex-wrap gap-1">
          <FilterPill href={link(null)} active={selectedYear === null} label="All years" />
          {data.years.map(y => (
            <FilterPill key={y.year} href={link(y.year)} active={selectedYear === y.year} label={String(y.year)} />
          ))}
        </nav>
      </div>

      {data.years.length === 0 ? (
        <p className="py-8 text-center text-sm text-[var(--text-3)]">
          No savings have been placed in a year yet. Generate a schedule on a project, or set the
          savings start and end dates on its Calculations tab.
        </p>
      ) : (
        <>
          {selected && (
            <div className="mb-4 grid grid-cols-1 gap-4 rounded-lg bg-[var(--surface-2)] p-4 sm:grid-cols-3">
              <Figure label={`FY${selected.year} Cost Reduction`} value={formatReduction(selected.reduction)} />
              <Figure label={`FY${selected.year} Cost Avoidance`} value={formatCurrency(selected.avoidance)} />
              <Figure label={`FY${selected.year} Total`} value={formatCurrency(selected.total)} accent />
            </div>
          )}

          <div className="overflow-x-auto">
            <table className="w-full min-w-[680px] text-sm">
              <caption className="sr-only">
                Procurement savings by fiscal year, with year-on-year movement and how much of each
                year is exact rather than estimated.
              </caption>
              <thead>
                <tr className="border-b border-[var(--border)] text-left text-xs text-[var(--text-3)]">
                  <th scope="col" className="py-2 pr-3 font-medium">Fiscal year</th>
                  <th scope="col" className="py-2 pr-3 text-right font-medium">Months</th>
                  <th scope="col" className="py-2 pr-3 text-right font-medium">Cost Reduction</th>
                  <th scope="col" className="py-2 pr-3 text-right font-medium">Cost Avoidance</th>
                  <th scope="col" className="py-2 pr-3 text-right font-medium">Total</th>
                  <th scope="col" className="py-2 pr-3 text-right font-medium">vs prior year</th>
                  <th scope="col" className="py-2 text-right font-medium">Confidence</th>
                </tr>
              </thead>
              <tbody>
                {shown.map(r => {
                  const bucket = data.years.find(y => y.year === r.year)!
                  const allExact = bucket.estimated === 0
                  return (
                    <tr key={r.year} className={clsx(
                      'border-b border-[var(--border)] last:border-0',
                      selectedYear === r.year && 'bg-[var(--surface-2)]',
                    )}>
                      <th scope="row" className="py-2 pr-3 text-left font-medium text-[var(--text)]">
                        {r.year}
                      </th>
                      <td className="py-2 pr-3 text-right tabular-nums text-[var(--text-3)]">{bucket.months}</td>
                      <td className="py-2 pr-3 text-right tabular-nums text-[var(--text-2)]">{formatReduction(r.reduction)}</td>
                      <td className="py-2 pr-3 text-right tabular-nums text-[var(--text-2)]">{formatCurrency(r.avoidance)}</td>
                      <td className="py-2 pr-3 text-right font-semibold tabular-nums text-[var(--text)]">{formatCurrency(r.total)}</td>
                      <td className="py-2 pr-3 text-right"><Movement delta={r.delta} pct={r.pct} /></td>
                      <td className="py-2 text-right">
                        {allExact ? (
                          <span className="text-xs text-[var(--text-3)]">exact</span>
                        ) : (
                          <span className="text-xs text-amber-600 dark:text-amber-400"
                            title={`${formatCurrency(bucket.exact)} from schedules, ${formatCurrency(bucket.estimated)} estimated from dates`}>
                            {formatCurrency(bucket.estimated)} estimated
                          </span>
                        )}
                      </td>
                    </tr>
                  )
                })}
              </tbody>
            </table>
          </div>

          <Provenance data={data} />
        </>
      )}
    </Card>
  )
}

function FilterPill({ href, active, label }: { href: string; active: boolean; label: string }) {
  return (
    <Link
      href={href}
      aria-current={active ? 'true' : undefined}
      className={clsx(
        'rounded-full px-3 py-1 text-xs font-medium transition-colors',
        'focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--brand)]',
        active
          ? 'bg-[var(--brand)] text-[var(--on-brand)]'
          : 'border border-[var(--border-strong)] text-[var(--text-2)] hover:bg-[var(--surface-2)]',
      )}
    >
      {label}
    </Link>
  )
}

function Figure({ label, value, accent }: { label: string; value: string; accent?: boolean }) {
  return (
    <div>
      <p className="text-xs text-[var(--text-3)]">{label}</p>
      <p className={clsx('mt-0.5 text-xl font-bold tabular-nums',
        accent ? 'text-green-600 dark:text-green-400' : 'text-[var(--text)]')}>{value}</p>
    </div>
  )
}

/**
 * Year-on-year movement. The arrow is never the only signal — the sign and the
 * word travel with it, so this reads correctly without colour vision.
 */
function Movement({ delta, pct }: { delta: number | null; pct: number | null }) {
  if (delta === null) {
    return <span className="text-xs text-[var(--text-3)]">no prior year</span>
  }
  const up = delta > 0
  const flat = delta === 0
  const Icon = flat ? Minus : up ? TrendingUp : TrendingDown
  return (
    <span className={clsx('inline-flex items-center justify-end gap-1 text-xs tabular-nums',
      flat ? 'text-[var(--text-3)]' : up ? 'text-green-600 dark:text-green-400' : 'text-red-600 dark:text-red-400')}>
      <Icon className="h-3 w-3" aria-hidden="true" />
      {up ? '+' : ''}{formatCurrency(delta)}
      {pct !== null && <span className="opacity-70">({up ? '+' : ''}{pct.toFixed(1)}%)</span>}
    </span>
  )
}

/** Say plainly where the numbers came from, including what could not be placed. */
function Provenance({ data }: { data: PortfolioByYear }) {
  const parts: string[] = []
  if (data.scheduledProjects) {
    parts.push(`${data.scheduledProjects} project${data.scheduledProjects === 1 ? '' : 's'} from a generated schedule (${formatCurrency(data.exactTotal)}, exact to the month)`)
  }
  if (data.estimatedProjects) {
    parts.push(`${data.estimatedProjects} spread evenly across its savings dates (${formatCurrency(data.estimatedTotal)})`)
  }
  return (
    <div className="mt-3 flex items-start gap-2 text-xs text-[var(--text-3)]">
      <Info className="mt-0.5 h-3.5 w-3.5 shrink-0" aria-hidden="true" />
      <div>
        {parts.length > 0 && <p>{parts.join('; ')}.</p>}
        {data.unscheduledProjects > 0 && (
          <p className="mt-1 text-amber-600 dark:text-amber-400">
            {formatCurrency(data.unscheduled)} across {data.unscheduledProjects} project
            {data.unscheduledProjects === 1 ? '' : 's'} could not be placed in any year — no savings
            start and end dates. That money is missing from this table, not from the portfolio.
          </p>
        )}
        {!data.reconciles && (
          <p className="mt-1 text-red-600 dark:text-red-400">
            These year buckets do not add back to the portfolio total. Do not report from this table
            until that is resolved.
          </p>
        )}
      </div>
    </div>
  )
}
