'use client'

import { useMemo, useState } from 'react'
import { Download, FileBarChart2, Filter, RotateCcw } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Card } from '@/components/ui/card'
import { Select } from '@/components/ui/input'
import { formatCurrency, formatDate, statusColor } from '@/lib/utils'
import { getFirst, num, reportedSavings, type SavingsCalcRow } from '@/lib/savings'

type NamedRelation = { category_name?: string; business_unit_name?: string; supplier_name?: string }

type EventRow = {
  id: string
  event_name: string
  event_type: string
  event_status: string
  project_type: string | null
  buyer_name: string | null
  event_start_date: string | null
  project_due_date: string | null
  event_close_date: string | null
  contract_start_date: string | null
  contract_end_date: string | null
  category: unknown
  business_unit: unknown
  incumbent_supplier: unknown
  awarded_supplier: unknown
}

type SavingsRow = SavingsCalcRow & {
  id: string
  event_id: string | null
}

type ReportId =
  | 'pipeline'
  | 'savings-project'
  | 'savings-business-unit'
  | 'savings-buyer'
  | 'projects-business-unit'
  | 'projects-buyer'
  | 'pipeline-business-unit'
  | 'pipeline-buyer'

type ReportValue = string | number | null
type ReportRow = Record<string, ReportValue>
type ColumnFormat = 'text' | 'number' | 'currency' | 'date' | 'status'

type ReportColumn = {
  key: string
  label: string
  format?: ColumnFormat
}

type ReportDefinition = {
  title: string
  description: string
  filename: string
  columns: ReportColumn[]
  rows: ReportRow[]
}

type SavingsTotals = {
  reduction: number
  avoidance: number
  total: number
}

const INACTIVE_STATUSES = new Set(['Closed', 'Cancelled', 'Rejected', 'Complete'])

const REPORT_OPTIONS: Array<{ id: ReportId; label: string; group: string }> = [
  { id: 'pipeline', label: 'Sourcing Project Pipeline', group: 'Pipeline' },
  { id: 'pipeline-business-unit', label: 'Pipeline by Business Unit', group: 'Pipeline' },
  { id: 'pipeline-buyer', label: 'Pipeline by Buyer', group: 'Pipeline' },
  { id: 'savings-project', label: 'Savings by Project', group: 'Savings' },
  { id: 'savings-business-unit', label: 'Savings by Business Unit', group: 'Savings' },
  { id: 'savings-buyer', label: 'Savings by Buyer', group: 'Savings' },
  { id: 'projects-business-unit', label: 'Projects by Business Unit', group: 'Projects' },
  { id: 'projects-buyer', label: 'Projects by Buyer', group: 'Projects' },
]

function relationName(relation: unknown, key: keyof NamedRelation, fallback: string): string {
  const value = getFirst<NamedRelation>(relation)?.[key]
  return typeof value === 'string' && value.trim() ? value : fallback
}

function csvCell(value: ReportValue): string {
  return `"${String(value ?? '').replace(/"/g, '""')}"`
}

function downloadCSV(filename: string, columns: ReportColumn[], rows: ReportRow[]) {
  const csvRows = [
    columns.map(column => csvCell(column.label)).join(','),
    ...rows.map(row => columns.map(column => csvCell(row[column.key])).join(',')),
  ]
  const blob = new Blob([csvRows.join('\n')], { type: 'text/csv;charset=utf-8' })
  const url = URL.createObjectURL(blob)
  const link = document.createElement('a')
  link.href = url
  link.download = filename
  link.click()
  link.remove()
  URL.revokeObjectURL(url)
}

function sortRows(rows: ReportRow[], key: string): ReportRow[] {
  return rows.sort((a, b) => num(b[key]) - num(a[key]) || String(a[key]).localeCompare(String(b[key])))
}

function formatValue(value: ReportValue, format: ColumnFormat = 'text'): string {
  if (format === 'currency') return formatCurrency(num(value))
  if (format === 'date') return formatDate(typeof value === 'string' ? value : null)
  if (format === 'number') return num(value).toLocaleString('en-US')
  if (value === null || value === '') return '—'
  return String(value)
}

function aggregateBy(
  events: EventRow[],
  totalsByEvent: Map<string, SavingsTotals>,
  getLabel: (event: EventRow) => string,
) {
  const groups = new Map<string, {
    projects: number
    active: number
    reduction: number
    avoidance: number
    savings: number
  }>()

  for (const event of events) {
    const label = getLabel(event)
    const current = groups.get(label) ?? { projects: 0, active: 0, reduction: 0, avoidance: 0, savings: 0 }
    const savings = totalsByEvent.get(event.id) ?? { reduction: 0, avoidance: 0, total: 0 }
    current.projects += 1
    current.active += INACTIVE_STATUSES.has(event.event_status) ? 0 : 1
    current.reduction += savings.reduction
    current.avoidance += savings.avoidance
    current.savings += savings.total
    groups.set(label, current)
  }

  return groups
}

export function ReportsView({ events, savingsCalcs }: { events: EventRow[]; savingsCalcs: SavingsRow[] }) {
  const [reportId, setReportId] = useState<ReportId>('pipeline')
  const [typeFilter, setTypeFilter] = useState('')
  const [statusFilter, setStatusFilter] = useState('')
  const [businessUnitFilter, setBusinessUnitFilter] = useState('')
  const [buyerFilter, setBuyerFilter] = useState('')

  const sourcingEvents = useMemo(
    () => events.filter(event => (event.project_type || 'Sourcing') === 'Sourcing'),
    [events],
  )

  const eventTypes = useMemo(
    () => Array.from(new Set(sourcingEvents.map(event => event.event_type).filter(Boolean))).sort(),
    [sourcingEvents],
  )
  const statuses = useMemo(
    () => Array.from(new Set(sourcingEvents.map(event => event.event_status).filter(Boolean))).sort(),
    [sourcingEvents],
  )
  const businessUnits = useMemo(
    () => Array.from(new Set(sourcingEvents.map(event => relationName(event.business_unit, 'business_unit_name', 'Unassigned')))).sort(),
    [sourcingEvents],
  )
  const buyers = useMemo(
    () => Array.from(new Set(sourcingEvents.map(event => event.buyer_name || 'Unassigned'))).sort(),
    [sourcingEvents],
  )

  const filteredEvents = useMemo(() => sourcingEvents.filter(event => {
    if (typeFilter && event.event_type !== typeFilter) return false
    if (statusFilter && event.event_status !== statusFilter) return false
    if (businessUnitFilter && relationName(event.business_unit, 'business_unit_name', 'Unassigned') !== businessUnitFilter) return false
    if (buyerFilter && (event.buyer_name || 'Unassigned') !== buyerFilter) return false
    return true
  }), [sourcingEvents, typeFilter, statusFilter, businessUnitFilter, buyerFilter])

  const report = useMemo<ReportDefinition>(() => {
    const filteredIds = new Set(filteredEvents.map(event => event.id))
    const totalsByEvent = new Map<string, SavingsTotals>()
    for (const calculation of savingsCalcs) {
      if (!calculation.event_id || !filteredIds.has(calculation.event_id)) continue
      const current = totalsByEvent.get(calculation.event_id) ?? { reduction: 0, avoidance: 0, total: 0 }
      current.reduction += num(calculation.cost_reduction_amount)
      current.avoidance += num(calculation.cost_avoidance_amount)
      current.total += reportedSavings(calculation)
      totalsByEvent.set(calculation.event_id, current)
    }

    const projectRows = filteredEvents.map(event => {
      const savings = totalsByEvent.get(event.id) ?? { reduction: 0, avoidance: 0, total: 0 }
      return {
        project: event.event_name,
        type: event.event_type,
        owner: event.buyer_name || 'Unassigned',
        businessUnit: relationName(event.business_unit, 'business_unit_name', 'Unassigned'),
        supplier: relationName(
          getFirst(event.awarded_supplier) || event.incumbent_supplier,
          'supplier_name',
          'Unassigned',
        ),
        dueDate: event.project_due_date,
        status: event.event_status,
        reduction: savings.reduction,
        avoidance: savings.avoidance,
        savings: savings.total,
      }
    })

    const byBusinessUnit = aggregateBy(
      filteredEvents,
      totalsByEvent,
      event => relationName(event.business_unit, 'business_unit_name', 'Unassigned'),
    )
    const byBuyer = aggregateBy(filteredEvents, totalsByEvent, event => event.buyer_name || 'Unassigned')
    const activeEvents = filteredEvents.filter(event => !INACTIVE_STATUSES.has(event.event_status))
    const activeByBusinessUnit = aggregateBy(
      activeEvents,
      totalsByEvent,
      event => relationName(event.business_unit, 'business_unit_name', 'Unassigned'),
    )
    const activeByBuyer = aggregateBy(activeEvents, totalsByEvent, event => event.buyer_name || 'Unassigned')

    const savingsColumns: ReportColumn[] = [
      { key: 'name', label: 'Group' },
      { key: 'projects', label: 'Projects', format: 'number' },
      { key: 'reduction', label: 'Cost Reduction', format: 'currency' },
      { key: 'avoidance', label: 'Cost Avoidance', format: 'currency' },
      { key: 'savings', label: 'Total Savings', format: 'currency' },
    ]

    if (reportId === 'pipeline') {
      return {
        title: 'Sourcing Project Pipeline',
        description: 'Active sourcing work with ownership, supplier, due date, and current workflow status.',
        filename: 'sourcing-project-pipeline.csv',
        columns: [
          { key: 'project', label: 'Project' },
          { key: 'type', label: 'Type' },
          { key: 'owner', label: 'Owner' },
          { key: 'businessUnit', label: 'Business Unit' },
          { key: 'supplier', label: 'Supplier' },
          { key: 'dueDate', label: 'Due Date', format: 'date' },
          { key: 'status', label: 'Status', format: 'status' },
        ],
        rows: projectRows.filter(row => !INACTIVE_STATUSES.has(String(row.status))),
      }
    }

    if (reportId === 'savings-project') {
      return {
        title: 'Savings by Project',
        description: 'Reported cost reduction, cost avoidance, and total savings for each sourcing project.',
        filename: 'savings-by-project.csv',
        columns: [
          { key: 'project', label: 'Project' },
          { key: 'owner', label: 'Owner' },
          { key: 'businessUnit', label: 'Business Unit' },
          { key: 'status', label: 'Status', format: 'status' },
          { key: 'reduction', label: 'Cost Reduction', format: 'currency' },
          { key: 'avoidance', label: 'Cost Avoidance', format: 'currency' },
          { key: 'savings', label: 'Total Savings', format: 'currency' },
        ],
        rows: sortRows(projectRows, 'savings'),
      }
    }

    const groupedRows = (groups: ReturnType<typeof aggregateBy>, pipelineOnly = false): ReportRow[] =>
      Array.from(groups.entries()).map(([name, values]) => ({
        name,
        projects: pipelineOnly ? values.active : values.projects,
        active: values.active,
        reduction: values.reduction,
        avoidance: values.avoidance,
        savings: values.savings,
      }))

    if (reportId === 'savings-business-unit' || reportId === 'savings-buyer') {
      const byUnit = reportId === 'savings-business-unit'
      return {
        title: byUnit ? 'Savings by Business Unit' : 'Savings by Buyer',
        description: byUnit
          ? 'Savings attributed to the business unit that owns each sourcing project.'
          : 'Savings attributed to the buyer or project owner responsible for each sourcing project.',
        filename: byUnit ? 'savings-by-business-unit.csv' : 'savings-by-buyer.csv',
        columns: [
          { ...savingsColumns[0], label: byUnit ? 'Business Unit' : 'Buyer' },
          ...savingsColumns.slice(1),
        ],
        rows: sortRows(groupedRows(byUnit ? byBusinessUnit : byBuyer), 'savings'),
      }
    }

    if (reportId === 'projects-business-unit' || reportId === 'projects-buyer') {
      const byUnit = reportId === 'projects-business-unit'
      return {
        title: byUnit ? 'Projects by Business Unit' : 'Projects by Buyer',
        description: 'Total and active sourcing project counts for the selected portfolio scope.',
        filename: byUnit ? 'projects-by-business-unit.csv' : 'projects-by-buyer.csv',
        columns: [
          { key: 'name', label: byUnit ? 'Business Unit' : 'Buyer' },
          { key: 'projects', label: 'Total Projects', format: 'number' },
          { key: 'active', label: 'Active Projects', format: 'number' },
        ],
        rows: sortRows(groupedRows(byUnit ? byBusinessUnit : byBuyer), 'projects'),
      }
    }

    const byUnit = reportId === 'pipeline-business-unit'
    return {
      title: byUnit ? 'Pipeline by Business Unit' : 'Pipeline by Buyer',
      description: 'Active sourcing projects and their associated forecast or booked savings.',
      filename: byUnit ? 'pipeline-by-business-unit.csv' : 'pipeline-by-buyer.csv',
      columns: [
        { key: 'name', label: byUnit ? 'Business Unit' : 'Buyer' },
        { key: 'projects', label: 'Pipeline Projects', format: 'number' },
        { key: 'savings', label: 'Pipeline Savings', format: 'currency' },
      ],
      rows: sortRows(groupedRows(byUnit ? activeByBusinessUnit : activeByBuyer, true), 'savings'),
    }
  }, [filteredEvents, savingsCalcs, reportId])

  const filtersActive = Boolean(typeFilter || statusFilter || businessUnitFilter || buyerFilter)

  const resetFilters = () => {
    setTypeFilter('')
    setStatusFilter('')
    setBusinessUnitFilter('')
    setBuyerFilter('')
  }

  return (
    <div className="mt-6 space-y-6">
      <Card className="p-5 sm:p-6">
        <div className="grid gap-5 lg:grid-cols-[minmax(0,360px)_1fr_auto] lg:items-end">
          <div>
            <label htmlFor="report-picker" className="text-sm font-semibold text-[var(--text)]">Choose report</label>
            <Select
              id="report-picker"
              value={reportId}
              onChange={event => setReportId(event.target.value as ReportId)}
              className="mt-2"
            >
              {['Pipeline', 'Savings', 'Projects'].map(group => (
                <optgroup key={group} label={group}>
                  {REPORT_OPTIONS.filter(option => option.group === group).map(option => (
                    <option key={option.id} value={option.id}>{option.label}</option>
                  ))}
                </optgroup>
              ))}
            </Select>
          </div>
          <div>
            <div className="flex items-center gap-2 text-[var(--brand-ink)]">
              <FileBarChart2 className="h-4 w-4" aria-hidden="true" />
              <h2 className="text-base font-semibold">{report.title}</h2>
            </div>
            <p className="mt-1 text-sm text-[var(--text-2)]">{report.description}</p>
          </div>
          <Button onClick={() => downloadCSV(report.filename, report.columns, report.rows)} disabled={report.rows.length === 0}>
            <Download className="h-4 w-4" aria-hidden="true" />
            Export CSV
          </Button>
        </div>
      </Card>

      <Card className="p-5 sm:p-6">
        <div className="mb-4 flex flex-wrap items-center justify-between gap-3">
          <div className="flex items-center gap-2">
            <Filter className="h-4 w-4 text-[var(--brand-ink)]" aria-hidden="true" />
            <h2 className="text-sm font-semibold text-[var(--text)]">Portfolio filters</h2>
          </div>
          {filtersActive && (
            <button onClick={resetFilters} className="inline-flex items-center gap-1.5 text-xs font-semibold text-[var(--brand-ink)] hover:underline">
              <RotateCcw className="h-3.5 w-3.5" aria-hidden="true" />
              Clear filters
            </button>
          )}
        </div>
        <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 xl:grid-cols-4">
          <FilterSelect label="Project type" value={typeFilter} onChange={setTypeFilter} options={eventTypes} allLabel="All project types" />
          <FilterSelect label="Status" value={statusFilter} onChange={setStatusFilter} options={statuses} allLabel="All statuses" />
          <FilterSelect label="Business unit" value={businessUnitFilter} onChange={setBusinessUnitFilter} options={businessUnits} allLabel="All business units" />
          <FilterSelect label="Buyer" value={buyerFilter} onChange={setBuyerFilter} options={buyers} allLabel="All buyers" />
        </div>
      </Card>

      <Card className="overflow-hidden">
        <div className="flex flex-wrap items-center justify-between gap-3 border-b border-[var(--border)] px-5 py-4 sm:px-6">
          <div>
            <h2 className="text-sm font-semibold text-[var(--text)]">{report.title}</h2>
            <p className="mt-1 text-xs text-[var(--text-3)]">Current filters · {report.rows.length} row{report.rows.length === 1 ? '' : 's'}</p>
          </div>
          <span className="rounded-full bg-[var(--brand-soft)] px-2.5 py-1 text-xs font-medium text-[var(--brand-ink)]">
            Live workspace data
          </span>
        </div>
        <div className="overflow-x-auto">
          <table className="w-full min-w-[760px]">
            <caption className="sr-only">{report.title}</caption>
            <thead>
              <tr className="border-b border-[var(--border)] bg-[var(--surface-2)]">
                {report.columns.map(column => (
                  <th
                    key={column.key}
                    scope="col"
                    className={`px-4 py-3 text-xs font-semibold uppercase tracking-wider text-[var(--text-3)] ${column.format === 'currency' || column.format === 'number' ? 'text-right' : 'text-left'}`}
                  >
                    {column.label}
                  </th>
                ))}
              </tr>
            </thead>
            <tbody className="divide-y divide-[var(--border)]">
              {report.rows.length === 0 ? (
                <tr>
                  <td colSpan={report.columns.length} className="px-5 py-12 text-center text-sm text-[var(--text-3)]">
                    No rows match the selected report and filters.
                  </td>
                </tr>
              ) : report.rows.map((row, rowIndex) => (
                <tr key={`${reportId}-${rowIndex}`} className="transition-colors hover:bg-[var(--surface-2)]">
                  {report.columns.map(column => {
                    const formatted = formatValue(row[column.key], column.format)
                    const numeric = column.format === 'currency' || column.format === 'number'
                    return (
                      <td key={column.key} className={`px-4 py-3 text-sm ${numeric ? 'text-right font-medium tabular-nums text-[var(--text)]' : 'text-left text-[var(--text-2)]'}`}>
                        {column.format === 'status' ? (
                          <span className={`inline-flex rounded-full px-2.5 py-0.5 text-xs font-medium ${statusColor(formatted)}`}>{formatted}</span>
                        ) : formatted}
                      </td>
                    )
                  })}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </Card>
    </div>
  )
}

function FilterSelect({
  label,
  value,
  onChange,
  options,
  allLabel,
}: {
  label: string
  value: string
  onChange: (value: string) => void
  options: string[]
  allLabel: string
}) {
  const id = `report-filter-${label.toLowerCase().replace(/\s+/g, '-')}`
  return (
    <div>
      <label htmlFor={id} className="text-xs font-medium text-[var(--text-3)]">{label}</label>
      <Select id={id} value={value} onChange={event => onChange(event.target.value)} className="mt-1.5">
        <option value="">{allLabel}</option>
        {options.map(option => <option key={option} value={option}>{option}</option>)}
      </Select>
    </div>
  )
}
