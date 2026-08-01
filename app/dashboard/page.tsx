import Link from 'next/link'
import { BriefcaseBusiness, ChevronRight, Users } from 'lucide-react'
import { createClient } from '@/lib/supabase/server'
import { DashboardStats } from '@/components/dashboard-stats'
import {
  DashboardOverviewChart,
  type DashboardTrendPoint,
} from '@/components/dashboard-overview-chart'
import { SavingsByCategoryChart, SavingsByTypeChart } from '@/components/dashboard-charts'
import { FiscalYearPanel } from '@/components/fiscal-year-panel'
import {
  getFirst,
  num,
  portfolioByYear,
  portfolioRollup,
  realizationRollup,
  reportedSavings,
  toSchedulePeriods,
  type EventLiteRow,
  type RealizationPeriodRow,
  type SavingsCalcRow,
  type SchedulePeriod,
  type SchedulePeriodRow,
} from '@/lib/savings'
import { formatCurrency, statusColor } from '@/lib/utils'
import { Card } from '@/components/ui/card'
import { clsx } from 'clsx'

const INACTIVE_STATUSES = new Set(['Closed', 'Cancelled', 'Rejected', 'Complete'])

const STATUS_PROGRESS: Record<string, number> = {
  Pipeline: 10,
  'Not Started': 10,
  Scoped: 20,
  'Baseline Pending': 30,
  'Baseline Approved': 40,
  'In Market': 55,
  'In Progress': 55,
  Negotiation: 70,
  'Award Recommended': 80,
  'Award Approved': 88,
  Contracted: 94,
  Implemented: 97,
  Realized: 100,
  'Finance Validated': 100,
  Hold: 50,
}

type EventRow = EventLiteRow & {
  project_type?: string | null
  event_start_date?: string | null
  project_due_date?: string | null
  event_close_date?: string | null
  awarded_supplier?: unknown
}

type CalculationRow = SavingsCalcRow & {
  baseline_total_amount?: number | null
  savings_percentage?: number | null
}

type DashboardRealizationPeriod = RealizationPeriodRow & {
  period_start_date?: string | null
}

type EventSummary = {
  id: string
  name: string
  category: string
  status: string
  baseline: number
  savings: number
  savingsPercent: number | null
  progress: number
}

type SupplierSummary = {
  id: string
  name: string
  savings: number
  projects: number
  share: number
}

function relationName(relation: unknown, key: string, fallback: string): string {
  const row = getFirst<Record<string, unknown>>(relation)
  const value = row?.[key]
  return typeof value === 'string' && value.trim() ? value : fallback
}

function eventSummaries(events: EventRow[], calculations: CalculationRow[]): EventSummary[] {
  const moneyByEvent = new Map<string, { baseline: number; savings: number }>()

  for (const calculation of calculations) {
    if (!calculation.event_id) continue
    const current = moneyByEvent.get(calculation.event_id) ?? { baseline: 0, savings: 0 }
    current.baseline += num(calculation.baseline_total_amount)
    current.savings += reportedSavings(calculation)
    moneyByEvent.set(calculation.event_id, current)
  }

  return events
    .filter(event => !INACTIVE_STATUSES.has(event.event_status ?? ''))
    .map(event => {
      const money = moneyByEvent.get(event.id) ?? { baseline: 0, savings: 0 }
      return {
        id: event.id,
        name: event.event_name || 'Untitled project',
        category: relationName(event.category, 'category_name', 'Uncategorized'),
        status: event.event_status || 'Pipeline',
        baseline: money.baseline,
        savings: money.savings,
        savingsPercent: money.baseline > 0 ? (money.savings / money.baseline) * 100 : null,
        progress: STATUS_PROGRESS[event.event_status || 'Pipeline'] ?? 25,
      }
    })
    .sort((a, b) => b.progress - a.progress || b.savings - a.savings)
}

function supplierSummaries(
  events: EventRow[],
  calculations: CalculationRow[],
  portfolioTotal: number,
): SupplierSummary[] {
  const eventById = new Map(events.map(event => [event.id, event]))
  const suppliers = new Map<string, { id: string; name: string; savings: number; projects: Set<string> }>()

  for (const calculation of calculations) {
    if (!calculation.event_id) continue
    const event = eventById.get(calculation.event_id)
    const supplier = getFirst<{ id?: string; supplier_name?: string }>(event?.awarded_supplier)
    if (!supplier?.id || !supplier.supplier_name) continue

    const current = suppliers.get(supplier.id) ?? {
      id: supplier.id,
      name: supplier.supplier_name,
      savings: 0,
      projects: new Set<string>(),
    }
    current.savings += reportedSavings(calculation)
    current.projects.add(calculation.event_id)
    suppliers.set(supplier.id, current)
  }

  return Array.from(suppliers.values())
    .map(supplier => ({
      id: supplier.id,
      name: supplier.name,
      savings: supplier.savings,
      projects: supplier.projects.size,
      share: portfolioTotal > 0 ? (supplier.savings / portfolioTotal) * 100 : 0,
    }))
    .sort((a, b) => b.savings - a.savings)
}

function realizationYear(period: DashboardRealizationPeriod): number | null {
  const value = period.period_start_date
  if (!value || !/^\d{4}-\d{2}-\d{2}/.test(value)) return null
  return Number(value.slice(0, 4))
}

export default async function DashboardPage({
  searchParams,
}: {
  searchParams: Promise<{ [key: string]: string | string[] | undefined }>
}) {
  const supabase = await createClient()
  const fyParam = (await searchParams).fy
  const fyRaw = Array.isArray(fyParam) ? fyParam[0] : fyParam
  const selectedYear = fyRaw && /^\d{4}$/.test(fyRaw) ? Number(fyRaw) : null

  const [
    { data: events, error: eventsError },
    { data: savingsCalcs, error: calcsError },
    { data: periodRows, error: periodsError },
    { data: realizationPeriods, error: realizationError },
  ] = await Promise.all([
    supabase.from('sourcing_events').select(`
      id, event_name, event_status, project_type, contract_start_date,
      event_start_date, project_due_date, event_close_date,
      category:categories!sourcing_events_category_id_fkey(category_name),
      business_unit:business_units(business_unit_name),
      awarded_supplier:suppliers!sourcing_events_awarded_supplier_id_fkey(id, supplier_name)
    `),
    supabase.from('savings_calculations').select(`
      id, savings_type, gross_savings_amount, baseline_total_amount,
      savings_percentage, cost_reduction_amount, cost_avoidance_amount,
      savings_start_date, savings_end_date, event_id, calculation_status
    `),
    supabase.from('savings_periods').select(`
      savings_calculation_id, period_number, period_month, period_year, period_months,
      baseline_amount, opening_amount, final_amount,
      cost_reduction_amount, cost_avoidance_amount, total_savings_amount
    `).order('period_number', { ascending: true }),
    supabase.from('realization_periods').select(`
      projected_savings, realized_savings, leakage_amount, realization_status,
      event_id, period_start_date
    `),
  ])

  const loadError = eventsError?.message
    || calcsError?.message
    || periodsError?.message
    || realizationError?.message
    || null

  const eventList = (events || []) as EventRow[]
  const calcList = (savingsCalcs || []) as CalculationRow[]
  const realizationList = (realizationPeriods || []) as DashboardRealizationPeriod[]

  const rollup = portfolioRollup(calcList, eventList, { topCategories: 8 })

  const periodsByCalcId = new Map<string, SchedulePeriod[]>()
  for (const row of periodRows || []) {
    const calculationId = (row as { savings_calculation_id?: string }).savings_calculation_id
    if (!calculationId) continue
    const list = periodsByCalcId.get(calculationId) || []
    list.push(toSchedulePeriods([row as SchedulePeriodRow])[0])
    periodsByCalcId.set(calculationId, list)
  }
  const byYear = portfolioByYear(calcList, periodsByCalcId)
  const selectedSavings = selectedYear === null
    ? null
    : byYear.years.find(year => year.year === selectedYear) ?? null

  const scopedRealizationPeriods = selectedYear === null
    ? realizationList
    : realizationList.filter(period => realizationYear(period) === selectedYear)
  const realization = realizationRollup(scopedRealizationPeriods)

  const realizedByYear = new Map<number, number>()
  for (const period of realizationList) {
    const year = realizationYear(period)
    if (year === null) continue
    realizedByYear.set(year, (realizedByYear.get(year) || 0) + num(period.realized_savings))
  }
  const trendYears = new Set([
    ...byYear.years.map(year => year.year),
    ...realizedByYear.keys(),
  ])
  const trendData: DashboardTrendPoint[] = Array.from(trendYears)
    .sort((a, b) => a - b)
    .map(year => ({
      year,
      total: byYear.years.find(bucket => bucket.year === year)?.total ?? 0,
      realized: realizedByYear.get(year) ?? 0,
    }))

  const typeSplit = [
    {
      name: 'Cost Reduction',
      value: selectedYear === null ? rollup.totalCostReduction : (selectedSavings?.reduction ?? 0),
    },
    {
      name: 'Cost Avoidance',
      value: selectedYear === null ? rollup.totalCostAvoidance : (selectedSavings?.avoidance ?? 0),
    },
  ]
  const suppliers = supplierSummaries(eventList, calcList, rollup.totalSavings)
  const activeEvents = eventSummaries(eventList, calcList)
  const scopeLabel = selectedYear === null ? 'All years' : `FY${selectedYear}`

  return (
    <div className="mx-auto w-full max-w-[1600px] p-4 sm:p-6 lg:p-8">
      <header className="mb-6 flex flex-col gap-4 sm:flex-row sm:items-end sm:justify-between">
        <div>
          <p className="text-xs font-semibold uppercase tracking-[0.18em] text-[var(--brand-ink)]">
            Procurement value
          </p>
          <h1 className="mt-1 text-2xl font-bold tracking-tight text-[var(--text)] sm:text-3xl">Overview</h1>
          <p className="mt-1 text-sm text-[var(--text-2)]">
            Savings performance, realization, suppliers, and active sourcing work.
          </p>
        </div>
        <YearFilter years={byYear.years.map(year => year.year)} selectedYear={selectedYear} />
      </header>

      {loadError && (
        <div className="mb-6 rounded-xl bg-red-50 p-4 text-sm text-red-700 dark:bg-red-900/30 dark:text-red-300" role="alert">
          <strong>These figures are incomplete.</strong> A query failed: {loadError}. Do not report
          from this page until it loads cleanly.
        </div>
      )}

      <DashboardStats stats={{
        totalSavings: selectedYear === null ? rollup.totalSavings : (selectedSavings?.total ?? 0),
        totalCostReduction: selectedYear === null ? rollup.totalCostReduction : (selectedSavings?.reduction ?? null),
        totalCostAvoidance: selectedYear === null ? rollup.totalCostAvoidance : (selectedSavings?.avoidance ?? 0),
        booked: rollup.booked,
        forecast: rollup.forecast,
        realizationRate: realization.realizationRate,
        realizedSavings: realization.totalRealized,
        scopeLabel,
      }} />

      <div className="mt-6 grid grid-cols-1 gap-6 xl:grid-cols-[minmax(0,0.9fr)_minmax(0,1.1fr)]">
        <Card className="overflow-hidden">
          <PanelHeader
            title="Top suppliers by savings"
            description="Savings attributed to awarded suppliers"
            href="/suppliers"
            linkLabel="View suppliers"
          />
          <TopSuppliersTable suppliers={suppliers.slice(0, 5)} />
        </Card>

        <Card className="p-5 sm:p-6">
          <div className="mb-2 flex flex-wrap items-start justify-between gap-3">
            <div>
              <h2 className="text-sm font-semibold text-[var(--text)]">Savings over fiscal year</h2>
              <p className="mt-1 text-xs text-[var(--text-3)]">Reported total compared with recorded realization</p>
            </div>
            <span className="rounded-full bg-[var(--brand-soft)] px-2.5 py-1 text-xs font-medium text-[var(--brand-ink)]">
              {scopeLabel}
            </span>
          </div>
          <DashboardOverviewChart data={trendData} selectedYear={selectedYear} />
        </Card>
      </div>

      <Card className="mt-6 overflow-hidden">
        <PanelHeader
          title="Active sourcing events"
          description={`${activeEvents.length} project${activeEvents.length === 1 ? '' : 's'} currently in progress`}
          href="/events"
          linkLabel="View all events"
        />
        <ActiveEventsTable events={activeEvents.slice(0, 6)} />
      </Card>

      <section className="mt-10" aria-labelledby="reporting-detail-title">
        <div className="mb-4">
          <h2 id="reporting-detail-title" className="text-lg font-semibold text-[var(--text)]">Reporting detail</h2>
          <p className="mt-1 text-sm text-[var(--text-2)]">
            Audit-ready fiscal-year allocation and methodology breakdowns behind the overview.
          </p>
        </div>

        <FiscalYearPanel data={byYear} selectedYear={selectedYear} basePath="/dashboard" />

        <div className="mt-6 grid grid-cols-1 gap-6 xl:grid-cols-2">
          <SavingsByCategoryChart data={rollup.byCategory} />
          <SavingsByTypeChart data={typeSplit} />
        </div>
      </section>
    </div>
  )
}

function YearFilter({ years, selectedYear }: { years: number[]; selectedYear: number | null }) {
  return (
    <nav aria-label="Dashboard fiscal year" className="flex flex-wrap items-center gap-1 rounded-xl border border-[var(--border)] bg-[var(--surface)] p-1 shadow-sm">
      <YearLink href="/dashboard" label="All years" active={selectedYear === null} />
      {years.map(year => (
        <YearLink
          key={year}
          href={`/dashboard?fy=${year}`}
          label={`FY${String(year).slice(-2)}`}
          active={selectedYear === year}
        />
      ))}
    </nav>
  )
}

function YearLink({ href, label, active }: { href: string; label: string; active: boolean }) {
  return (
    <Link
      href={href}
      aria-current={active ? 'page' : undefined}
      className={clsx(
        'rounded-lg px-3 py-1.5 text-xs font-medium transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--brand)]',
        active
          ? 'bg-[var(--brand)] text-[var(--on-brand)] shadow-sm'
          : 'text-[var(--text-2)] hover:bg-[var(--surface-2)] hover:text-[var(--text)]',
      )}
    >
      {label}
    </Link>
  )
}

function PanelHeader({
  title,
  description,
  href,
  linkLabel,
}: {
  title: string
  description: string
  href: string
  linkLabel: string
}) {
  return (
    <div className="flex flex-wrap items-center justify-between gap-3 border-b border-[var(--border)] px-5 py-4 sm:px-6">
      <div>
        <h2 className="text-sm font-semibold text-[var(--text)]">{title}</h2>
        <p className="mt-1 text-xs text-[var(--text-3)]">{description}</p>
      </div>
      <Link href={href} className="inline-flex items-center gap-1 text-xs font-semibold text-[var(--brand-ink)] hover:underline">
        {linkLabel}
        <ChevronRight className="h-3.5 w-3.5" aria-hidden="true" />
      </Link>
    </div>
  )
}

function TopSuppliersTable({ suppliers }: { suppliers: SupplierSummary[] }) {
  if (suppliers.length === 0) {
    return (
      <div className="grid min-h-64 place-items-center px-6 text-center">
        <div>
          <Users className="mx-auto h-8 w-8 text-[var(--text-3)]" aria-hidden="true" />
          <p className="mt-3 text-sm font-medium text-[var(--text)]">No awarded suppliers yet</p>
          <p className="mt-1 text-xs text-[var(--text-3)]">Award a project to attribute its savings to a supplier.</p>
        </div>
      </div>
    )
  }

  return (
    <div className="overflow-x-auto">
      <table className="w-full min-w-[560px] text-sm">
        <caption className="sr-only">Top awarded suppliers ranked by reported savings</caption>
        <thead>
          <tr className="bg-[var(--surface-2)] text-left text-[11px] font-semibold uppercase tracking-wider text-[var(--text-3)]">
            <th scope="col" className="px-5 py-3 sm:px-6">Supplier</th>
            <th scope="col" className="px-4 py-3 text-right">Savings</th>
            <th scope="col" className="px-4 py-3 text-right">Share</th>
            <th scope="col" className="px-5 py-3 text-right sm:px-6">Projects</th>
          </tr>
        </thead>
        <tbody className="divide-y divide-[var(--border)]">
          {suppliers.map(supplier => (
            <tr key={supplier.id} className="transition-colors hover:bg-[var(--surface-2)]">
              <th scope="row" className="px-5 py-3 text-left font-medium text-[var(--text)] sm:px-6">{supplier.name}</th>
              <td className="px-4 py-3 text-right font-semibold tabular-nums text-[var(--text)]">{formatCurrency(supplier.savings)}</td>
              <td className="px-4 py-3 text-right tabular-nums text-[var(--text-2)]">{supplier.share.toFixed(1)}%</td>
              <td className="px-5 py-3 text-right tabular-nums text-[var(--text-2)] sm:px-6">{supplier.projects}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  )
}

function ActiveEventsTable({ events }: { events: EventSummary[] }) {
  if (events.length === 0) {
    return (
      <div className="grid min-h-56 place-items-center px-6 text-center">
        <div>
          <BriefcaseBusiness className="mx-auto h-8 w-8 text-[var(--text-3)]" aria-hidden="true" />
          <p className="mt-3 text-sm font-medium text-[var(--text)]">No active sourcing events</p>
          <Link href="/events/new" className="mt-2 inline-block text-xs font-semibold text-[var(--brand-ink)] hover:underline">
            Create the first project
          </Link>
        </div>
      </div>
    )
  }

  return (
    <div className="overflow-x-auto">
      <table className="w-full min-w-[860px] text-sm">
        <caption className="sr-only">Active sourcing events with savings and stage progress</caption>
        <thead>
          <tr className="bg-[var(--surface-2)] text-left text-[11px] font-semibold uppercase tracking-wider text-[var(--text-3)]">
            <th scope="col" className="px-5 py-3 sm:px-6">Event</th>
            <th scope="col" className="px-4 py-3">Category</th>
            <th scope="col" className="px-4 py-3 text-right">Baseline</th>
            <th scope="col" className="px-4 py-3 text-right">Savings</th>
            <th scope="col" className="px-4 py-3">Status</th>
            <th scope="col" className="px-5 py-3 sm:px-6">Progress</th>
          </tr>
        </thead>
        <tbody className="divide-y divide-[var(--border)]">
          {events.map(event => (
            <tr key={event.id} className="transition-colors hover:bg-[var(--surface-2)]">
              <th scope="row" className="px-5 py-3 text-left sm:px-6">
                <Link href={`/events/${event.id}`} className="font-medium text-[var(--text)] hover:text-[var(--brand-ink)] hover:underline">
                  {event.name}
                </Link>
              </th>
              <td className="px-4 py-3 text-[var(--text-2)]">{event.category}</td>
              <td className="px-4 py-3 text-right tabular-nums text-[var(--text-2)]">{event.baseline > 0 ? formatCurrency(event.baseline) : '—'}</td>
              <td className="px-4 py-3 text-right">
                <p className="font-semibold tabular-nums text-[var(--text)]">{formatCurrency(event.savings)}</p>
                <p className="text-[11px] tabular-nums text-[var(--text-3)]">
                  {event.savingsPercent === null ? 'No baseline %' : `${event.savingsPercent.toFixed(1)}% of baseline`}
                </p>
              </td>
              <td className="px-4 py-3">
                <span className={`inline-flex rounded-full px-2.5 py-1 text-xs font-medium ${statusColor(event.status)}`}>
                  {event.status}
                </span>
              </td>
              <td className="px-5 py-3 sm:px-6">
                <div className="flex min-w-28 items-center gap-2">
                  <div className="h-1.5 flex-1 overflow-hidden rounded-full bg-[var(--surface-2)]">
                    <div className="h-full rounded-full bg-[var(--brand)]" style={{ width: `${event.progress}%` }} />
                  </div>
                  <span className="w-8 text-right text-xs tabular-nums text-[var(--text-3)]">{event.progress}%</span>
                </div>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  )
}
