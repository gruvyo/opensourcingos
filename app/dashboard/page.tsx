import Link from 'next/link'
import { BriefcaseBusiness, ChevronRight, Users } from 'lucide-react'
import { createClient } from '@/lib/supabase/server'
import { fetchPortfolioRows } from '@/lib/supabase/portfolio-query'
import { DashboardStats } from '@/components/dashboard-stats'
import {
  DashboardOverviewChart,
  type DashboardTrendPoint,
} from '@/components/dashboard-overview-chart'
import { SavingsByCategoryChart, SavingsByTypeChart } from '@/components/dashboard-charts'
import { FiscalYearPanel } from '@/components/fiscal-year-panel'
import {
  DashboardActivityBreakdowns,
  type ActivityBreakdown,
} from '@/components/dashboard-activity-breakdowns'
import {
  getFirst,
  num,
  portfolioByYear,
  portfolioRollup,
  realizationRollup,
  reportedSavings,
  scheduleLifecycleRollup,
  toExecutedSchedulePeriods,
  toSchedulePeriods,
  type EventLiteRow,
  type RealizationPeriodRow,
  type SavingsCalcRow,
  type SchedulePeriod,
  type SchedulePeriodRow,
} from '@/lib/savings'
import { formatDashboardCurrency, statusColor } from '@/lib/utils'
import { Card } from '@/components/ui/card'
import { AttentionQueue } from '@/components/attention-queue'
import { buildAttentionQueue } from '@/lib/attention-queue'
import { dateKeyInTimeZone } from '@/lib/supplier-readiness'
import { supplierGovernanceSummaries, type SupplierPerformanceReviewSummaryRow } from '@/lib/supplier-governance-report'
import { clsx } from 'clsx'
import { sourcingSavingsPopulation } from '@/lib/savings-population'
import { isTerminalStatus, type TerminalStatusOption } from '@/lib/terminal-status'

const STATUS_PROGRESS: Record<string, number> = {
  Pipeline: 10,
  'Not Started': 10,
  'Scoping & Strategy': 25,
  'In Market': 45,
  'In Progress': 50,
  Pending: 50,
  Negotiation: 60,
  'Award & Contracting': 75,
  Implementation: 90,
  'On Hold': 50,
  Complete: 100,
}

type EventRow = EventLiteRow & {
  project_type?: string | null
  event_type?: string | null
  buyer_name?: string | null
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

type SupplierAttentionRow = {
  id: string
  supplier_name?: string | null
  supplier_status?: string | null
  risk_rating?: string | null
  next_review_date?: string | null
}

type SupplierRiskAttentionRow = {
  supplier_id: string
  severity: string
}

function relationName(relation: unknown, key: string, fallback: string): string {
  const row = getFirst<Record<string, unknown>>(relation)
  const value = row?.[key]
  return typeof value === 'string' && value.trim() ? value : fallback
}

function eventSummaries(
  events: EventRow[],
  calculations: CalculationRow[],
  terminalStatuses: TerminalStatusOption[],
): EventSummary[] {
  const moneyByEvent = new Map<string, { baseline: number; savings: number }>()

  for (const calculation of calculations) {
    if (!calculation.event_id) continue
    const current = moneyByEvent.get(calculation.event_id) ?? { baseline: 0, savings: 0 }
    current.baseline += num(calculation.baseline_total_amount)
    current.savings += reportedSavings(calculation)
    moneyByEvent.set(calculation.event_id, current)
  }

  return events
    .filter(event => !isTerminalStatus(event.event_status, event.project_type, terminalStatuses))
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

function countBy(
  events: EventRow[],
  getLabel: (event: EventRow) => string,
): Array<{ label: string; value: number }> {
  const counts = new Map<string, number>()
  for (const event of events) {
    const label = getLabel(event)
    counts.set(label, (counts.get(label) || 0) + 1)
  }
  return Array.from(counts.entries())
    .map(([label, value]) => ({ label, value }))
    .sort((a, b) => b.value - a.value || a.label.localeCompare(b.label))
    .slice(0, 6)
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
    { data: supplierRows, error: suppliersError },
    { data: supplierRiskRows, error: supplierRisksError },
    { data: supplierReviewRows, error: supplierReviewsError },
    { data: terminalStatusRows, error: terminalStatusesError },
    { data: settings, error: settingsError },
  ] = await Promise.all([
    fetchPortfolioRows('Projects', (from, to) => (
      supabase.from('sourcing_events').select(`
        id, event_name, event_type, event_status, project_type, buyer_name, contract_start_date,
        event_start_date, project_due_date, event_close_date,
        category:categories!sourcing_events_category_id_fkey(category_name),
        business_unit:business_units(business_unit_name),
        awarded_supplier:suppliers!sourcing_events_awarded_supplier_id_fkey(id, supplier_name)
      `, { count: 'exact' })
        .order('id', { ascending: true })
        .range(from, to)
    )),
    fetchPortfolioRows('Savings calculations', (from, to) => (
      supabase.from('savings_calculations').select(`
        id, savings_type, gross_savings_amount, baseline_total_amount,
        savings_percentage, cost_reduction_amount, cost_avoidance_amount,
        savings_start_date, savings_end_date, event_id, calculation_status
      `, { count: 'exact' })
        .order('id', { ascending: true })
        .range(from, to)
    )),
    fetchPortfolioRows('Savings periods', (from, to) => (
      supabase.from('savings_periods').select(`
        id, savings_calculation_id, period_number, period_month, period_year, period_months,
        baseline_amount, opening_amount, final_amount,
        cost_reduction_amount, cost_avoidance_amount, total_savings_amount,
        executed_baseline_amount, executed_opening_amount, executed_final_amount,
        executed_cost_reduction_amount, executed_cost_avoidance_amount, executed_total_savings_amount
      `, { count: 'exact' })
        .order('savings_calculation_id', { ascending: true })
        .order('period_number', { ascending: true })
        .order('id', { ascending: true })
        .range(from, to)
    )),
    fetchPortfolioRows('Realization periods', (from, to) => (
      supabase.from('realization_periods').select(`
        id, projected_savings, projected_reduction_amount, projected_avoidance_amount,
        realized_savings, realized_reduction_amount, realized_avoidance_amount,
        leakage_amount, realization_status,
        event_id, period_start_date
      `, { count: 'exact' })
        .order('id', { ascending: true })
        .range(from, to)
    )),
    fetchPortfolioRows('Suppliers', (from, to) => (
      supabase.from('suppliers').select(`
        id, supplier_name, supplier_status, risk_rating, next_review_date
      `, { count: 'exact' })
        .order('id', { ascending: true })
        .range(from, to)
    )),
    fetchPortfolioRows('Supplier risks', (from, to) => (
      supabase.from('supplier_risks').select('id, supplier_id, severity', { count: 'exact' })
        .neq('risk_status', 'Resolved')
        .order('id', { ascending: true })
        .range(from, to)
    )),
    fetchPortfolioRows('Supplier performance reviews', (from, to) => (
      supabase.from('supplier_performance_reviews').select(`
        id, supplier_id, review_date, created_at, overall_score, next_review_date
      `, { count: 'exact' })
        .order('supplier_id', { ascending: true })
        .order('review_date', { ascending: false })
        .order('created_at', { ascending: false })
        .order('id', { ascending: false })
        .range(from, to)
    )),
    supabase.from('project_choice_options')
      .select('label, project_type, is_terminal')
      .eq('choice_type', 'event_status'),
    supabase.from('organization_settings').select('savings_realization_enabled, timezone').maybeSingle(),
  ])

  const loadError = eventsError?.message
    || calcsError?.message
    || periodsError?.message
    || realizationError?.message
    || suppliersError?.message
    || supplierRisksError?.message
    || supplierReviewsError?.message
    || terminalStatusesError?.message
    || settingsError?.message
    || null

  const eventList = (events || []) as EventRow[]
  const terminalStatuses = (terminalStatusRows || []) as TerminalStatusOption[]
  const population = sourcingSavingsPopulation(
    eventList,
    (savingsCalcs || []) as CalculationRow[],
    (periodRows || []) as Array<SchedulePeriodRow & { savings_calculation_id?: string | null }>,
    (realizationPeriods || []) as DashboardRealizationPeriod[],
  )
  const sourcingEvents = population.events
  const calcList = population.calculations
  const sourcingPeriodRows = population.periodRows
  const realizationList = population.realizationRows
  const supplierAttentionList = (supplierRows || []) as SupplierAttentionRow[]
  const supplierGovernance = supplierGovernanceSummaries(
    (supplierReviewRows || []) as SupplierPerformanceReviewSummaryRow[],
    [],
  )
  const riskIssueCounts = new Map<string, { critical: number; high: number }>()
  for (const risk of (supplierRiskRows || []) as SupplierRiskAttentionRow[]) {
    if (risk.severity !== 'Critical' && risk.severity !== 'High') continue
    const count = riskIssueCounts.get(risk.supplier_id) || { critical: 0, high: 0 }
    if (risk.severity === 'Critical') count.critical += 1
    else count.high += 1
    riskIssueCounts.set(risk.supplier_id, count)
  }
  const asOfDate = dateKeyInTimeZone(new Date(), settings?.timezone || 'America/Chicago')
  const attentionQueue = buildAttentionQueue(
    eventList.map(event => ({
      id: event.id,
      name: event.event_name || null,
      status: event.event_status || null,
      projectType: event.project_type || null,
      dueDate: event.project_due_date || null,
    })),
    supplierAttentionList.map(supplier => {
      const issueCounts = riskIssueCounts.get(supplier.id)
      return {
        id: supplier.id,
        name: supplier.supplier_name || null,
        status: supplier.supplier_status || null,
        risk: supplier.risk_rating || null,
        nextReviewDate: supplier.next_review_date || null,
        performanceNextReviewDate: supplierGovernance.get(supplier.id)?.performanceNextReviewDate || null,
        criticalRiskIssues: issueCounts?.critical || 0,
        highRiskIssues: issueCounts?.high || 0,
      }
    }),
    asOfDate,
    terminalStatuses,
  )

  const rollup = portfolioRollup(calcList, sourcingEvents, {
    topCategories: 8,
    timeZone: settings?.timezone || 'America/Chicago',
  })
  const lifecycle = scheduleLifecycleRollup(
    calcList,
    sourcingPeriodRows,
    new Date(),
    selectedYear ?? undefined,
  )

  const periodsByCalcId = new Map<string, SchedulePeriod[]>()
  const calculationById = new Map(calcList.map(calculation => [calculation.id, calculation]))
  for (const row of sourcingPeriodRows) {
    const calculationId = (row as { savings_calculation_id?: string }).savings_calculation_id
    if (!calculationId) continue
    const list = periodsByCalcId.get(calculationId) || []
    const calculation = calculationById.get(calculationId)
    const normalized = calculation?.calculation_status === 'executed'
      ? toExecutedSchedulePeriods([row as SchedulePeriodRow])[0]
      : toSchedulePeriods([row as SchedulePeriodRow])[0]
    if (!normalized) continue
    list.push(normalized)
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

  const trendData: DashboardTrendPoint[] = byYear.years.map(({ year }) => {
    const yearLifecycle = scheduleLifecycleRollup(
      calcList,
      sourcingPeriodRows,
      new Date(),
      year,
    )
    return {
      year,
      estimated: yearLifecycle.estimatedPipeline,
      executed: yearLifecycle.executed,
    }
  })

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
  const suppliers = supplierSummaries(sourcingEvents, calcList, rollup.totalSavings)
  const activeEvents = eventSummaries(sourcingEvents, calcList, terminalStatuses)
  const scopeLabel = selectedYear === null ? 'All years' : `FY${selectedYear}`
  const activeSourcingEvents = sourcingEvents.filter(event => (
    !isTerminalStatus(event.event_status, event.project_type, terminalStatuses)
  ))
  const activityCards: ActivityBreakdown[] = [
    {
      title: 'Projects by Business Unit',
      description: 'All sourcing projects',
      items: countBy(sourcingEvents, event => relationName(event.business_unit, 'business_unit_name', 'Unassigned')),
    },
    {
      title: 'Pipeline by Status',
      description: 'Active sourcing projects',
      items: countBy(activeSourcingEvents, event => event.event_status || 'Pipeline'),
    },
    {
      title: 'Projects by Type',
      description: 'Sourcing method or event type',
      items: countBy(sourcingEvents, event => event.event_type || 'Unspecified'),
    },
    {
      title: 'Projects by Owner',
      description: 'Assigned buyer or project owner',
      items: countBy(sourcingEvents, event => event.buyer_name || 'Unassigned'),
    },
  ]

  return (
    <div className="mx-auto w-full max-w-[1600px] p-4 sm:p-6 lg:p-8">
      <header className="mb-6 flex flex-col gap-4 sm:flex-row sm:items-end sm:justify-between">
        <div>
          <p className="text-xs font-semibold uppercase tracking-[0.18em] text-[var(--brand-ink)]">
            Procurement value
          </p>
          <h1 className="mt-1 text-2xl font-bold tracking-tight text-[var(--text)] sm:text-3xl">Overview</h1>
          <p className="mt-1 text-sm text-[var(--text-2)]">
            Estimated, executed, and accrued savings, suppliers, and active sourcing work.
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
        spendAddressed: lifecycle.spendAddressed,
        estimatedPipeline: lifecycle.estimatedPipeline,
        executedSavings: lifecycle.executed,
        accruedExecuted: lifecycle.accruedExecuted,
        realizationRate: realization.realizationRate,
        realizedSavings: realization.totalRealized,
        savingsRealizationEnabled: settings?.savings_realization_enabled ?? false,
        scopeLabel,
      }} />

      <AttentionQueue queue={attentionQueue} />

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
              <p className="mt-1 text-xs text-[var(--text-3)]">Estimated pipeline compared with executed savings</p>
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

      <DashboardActivityBreakdowns cards={activityCards} />

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
              <td className="px-4 py-3 text-right font-semibold tabular-nums text-[var(--text)]">{formatDashboardCurrency(supplier.savings)}</td>
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
              <td className="px-4 py-3 text-right tabular-nums text-[var(--text-2)]">{event.baseline > 0 ? formatDashboardCurrency(event.baseline) : '—'}</td>
              <td className="px-4 py-3 text-right">
                <p className="font-semibold tabular-nums text-[var(--text)]">{formatDashboardCurrency(event.savings)}</p>
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
