'use client'

import { useMemo, useState } from 'react'
import { AlertTriangle, Download, FileBarChart2, Filter, RotateCcw } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Card } from '@/components/ui/card'
import { Select } from '@/components/ui/input'
import { formatCurrency, formatDate, statusColor } from '@/lib/utils'
import { fixedMoney } from '@/lib/money'
import { getFirst, num, reportedSavings, type SavingsCalcRow } from '@/lib/savings'
import { assessSupplierReadiness, matchesSupplierReadinessFilter, type SupplierReadinessFilter } from '@/lib/supplier-readiness'
import { supplierPortfolioValues } from '@/lib/supplier-portfolio'
import { supplierGovernanceSummaries, type SupplierPerformanceReviewSummaryRow, type SupplierRiskSummaryRow } from '@/lib/supplier-governance-report'
import { supplierPortfolioSegments, type SupplierSegmentDimension } from '@/lib/supplier-segmentation'
import { canonicalCalculationsByEvent } from '@/lib/calculation-integrity'
import { sourcingSavingsPopulation } from '@/lib/savings-population'

type NamedRelation = { category_name?: string; business_unit_name?: string; supplier_name?: string; full_name?: string; email?: string }

type EventRow = {
  id: string
  event_name: string
  event_type: string
  event_status: string
  project_type: string | null
  buyer_name: string | null
  incumbent_supplier_id: string | null
  awarded_supplier_id: string | null
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

type SupplierRow = {
  id: string
  supplier_name: string
  supplier_status: string | null
  risk_rating: string | null
  preferred_flag: boolean | null
  diversity_flag: boolean | null
  next_review_date: string | null
  relationship_owner: unknown
}

type SavingsRow = SavingsCalcRow & {
  id: string
  event_id: string | null
  created_at: string | null
  baseline_total_amount: number | null
}

type RealizationRow = {
  event_id: string | null
  projected_savings: number | null
  realized_savings: number | null
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
  | 'supplier-portfolio'
  | 'supplier-readiness'
  | 'supplier-performance-risk'
  | 'supplier-segmentation'

type ReportValue = string | number | null
type ReportRow = Record<string, ReportValue>
type ColumnFormat = 'text' | 'number' | 'currency' | 'reduction' | 'date' | 'status' | 'percent' | 'score'

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
  estimated: number
  executed: number
}

const INACTIVE_STATUSES = new Set(['Cancelled', 'Complete'])

const REPORT_OPTIONS: Array<{ id: ReportId; label: string; group: string }> = [
  { id: 'pipeline', label: 'Sourcing Project Pipeline', group: 'Pipeline' },
  { id: 'pipeline-business-unit', label: 'Pipeline by Business Unit', group: 'Pipeline' },
  { id: 'pipeline-buyer', label: 'Pipeline by Buyer', group: 'Pipeline' },
  { id: 'savings-project', label: 'Savings by Project', group: 'Savings' },
  { id: 'savings-business-unit', label: 'Savings by Business Unit', group: 'Savings' },
  { id: 'savings-buyer', label: 'Savings by Buyer', group: 'Savings' },
  { id: 'projects-business-unit', label: 'Projects by Business Unit', group: 'Projects' },
  { id: 'projects-buyer', label: 'Projects by Buyer', group: 'Projects' },
  { id: 'supplier-portfolio', label: 'Supplier Portfolio Value', group: 'Suppliers' },
  { id: 'supplier-readiness', label: 'Supplier Relationship Readiness', group: 'Suppliers' },
  { id: 'supplier-performance-risk', label: 'Supplier Performance & Risk', group: 'Suppliers' },
  { id: 'supplier-segmentation', label: 'Supplier Portfolio Segmentation', group: 'Suppliers' },
]

function relationName(relation: unknown, key: keyof NamedRelation, fallback: string): string {
  const value = getFirst<NamedRelation>(relation)?.[key]
  return typeof value === 'string' && value.trim() ? value : fallback
}

function personName(relation: unknown): string | null {
  const person = getFirst<NamedRelation>(relation)
  return person?.full_name || person?.email || null
}

function csvCell(value: ReportValue): string {
  return `"${String(value ?? '').replace(/"/g, '""')}"`
}

function csvReportValue(value: ReportValue, column: ReportColumn): ReportValue {
  return column.format === 'currency' || column.format === 'reduction'
    ? fixedMoney(num(value))
    : value
}

function downloadCSV(filename: string, columns: ReportColumn[], rows: ReportRow[]) {
  const csvRows = [
    columns.map(column => csvCell(column.label)).join(','),
    ...rows.map(row => columns.map(column => csvCell(csvReportValue(row[column.key], column))).join(',')),
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
  if (format === 'reduction') {
    const amount = num(value)
    return amount < 0 ? `(${formatCurrency(Math.abs(amount))})` : formatCurrency(amount)
  }
  if (format === 'date') return formatDate(typeof value === 'string' ? value : null)
  if (format === 'number') return num(value).toLocaleString('en-US')
  if (format === 'score') return value === null ? '—' : `${num(value).toFixed(1)} / 5`
  if (format === 'percent') return value === null ? '—' : `${num(value).toFixed(1)}%`
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
    estimated: number
    executed: number
  }>()

  for (const event of events) {
    const label = getLabel(event)
    const current = groups.get(label) ?? { projects: 0, active: 0, reduction: 0, avoidance: 0, savings: 0, estimated: 0, executed: 0 }
    const savings = totalsByEvent.get(event.id) ?? { reduction: 0, avoidance: 0, total: 0, estimated: 0, executed: 0 }
    current.projects += 1
    current.active += INACTIVE_STATUSES.has(event.event_status) ? 0 : 1
    current.reduction += savings.reduction
    current.avoidance += savings.avoidance
    current.savings += savings.total
    current.estimated += savings.estimated
    current.executed += savings.executed
    groups.set(label, current)
  }

  return groups
}

export function ReportsView({
  events,
  savingsCalcs,
  suppliers,
  supplierReviews,
  supplierRiskIssues,
  realizationPeriods,
  savingsRealizationEnabled,
  asOfDate,
}: {
  events: EventRow[]
  savingsCalcs: SavingsRow[]
  suppliers: SupplierRow[]
  supplierReviews: SupplierPerformanceReviewSummaryRow[]
  supplierRiskIssues: SupplierRiskSummaryRow[]
  realizationPeriods: RealizationRow[]
  savingsRealizationEnabled: boolean
  asOfDate: string
}) {
  const [reportId, setReportId] = useState<ReportId>('pipeline')
  const [typeFilter, setTypeFilter] = useState('')
  const [statusFilter, setStatusFilter] = useState('')
  const [businessUnitFilter, setBusinessUnitFilter] = useState('')
  const [buyerFilter, setBuyerFilter] = useState('')
  const [supplierStatusFilter, setSupplierStatusFilter] = useState('')
  const [supplierRiskFilter, setSupplierRiskFilter] = useState('')
  const [supplierAttributeFilter, setSupplierAttributeFilter] = useState('')
  const [supplierReadinessFilter, setSupplierReadinessFilter] = useState<SupplierReadinessFilter>('')
  const [supplierSegmentDimension, setSupplierSegmentDimension] = useState<SupplierSegmentDimension>('Preferred status')

  const population = useMemo(
    () => sourcingSavingsPopulation(events, savingsCalcs, [], realizationPeriods),
    [events, realizationPeriods, savingsCalcs],
  )
  const sourcingEvents = population.events
  const sourcingSavings = population.calculations
  const sourcingRealization = population.realizationRows

  const canonicalSavings = useMemo(
    () => canonicalCalculationsByEvent(sourcingSavings),
    [sourcingSavings],
  )

  const supplierPortfolio = useMemo(
    () => supplierPortfolioValues(
      sourcingEvents.map(event => ({ id: event.id, awardedSupplierId: event.awarded_supplier_id })),
      sourcingSavings,
      sourcingRealization,
    ),
    [sourcingEvents, sourcingRealization, sourcingSavings],
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
  const supplierStatuses = useMemo(
    () => Array.from(new Set(suppliers.map(supplier => supplier.supplier_status || 'Active'))).sort(),
    [suppliers],
  )
  const supplierRisks = useMemo(
    () => Array.from(new Set(suppliers.map(supplier => supplier.risk_rating || 'Unrated'))).sort(),
    [suppliers],
  )

  const filteredEvents = useMemo(() => sourcingEvents.filter(event => {
    if (typeFilter && event.event_type !== typeFilter) return false
    if (statusFilter && event.event_status !== statusFilter) return false
    if (businessUnitFilter && relationName(event.business_unit, 'business_unit_name', 'Unassigned') !== businessUnitFilter) return false
    if (buyerFilter && (event.buyer_name || 'Unassigned') !== buyerFilter) return false
    return true
  }), [sourcingEvents, typeFilter, statusFilter, businessUnitFilter, buyerFilter])

  const filteredSuppliers = useMemo(() => suppliers.filter(supplier => {
    const status = supplier.supplier_status || 'Active'
    const risk = supplier.risk_rating || 'Unrated'
    const readiness = assessSupplierReadiness({
      relationshipOwner: personName(supplier.relationship_owner),
      nextReviewDate: supplier.next_review_date,
      risk: supplier.risk_rating,
    }, asOfDate)
    if (supplierStatusFilter && status !== supplierStatusFilter) return false
    if (supplierRiskFilter && risk !== supplierRiskFilter) return false
    if (supplierAttributeFilter === 'Preferred' && !supplier.preferred_flag) return false
    if (supplierAttributeFilter === 'Diverse' && !supplier.diversity_flag) return false
    return reportId !== 'supplier-readiness' || matchesSupplierReadinessFilter(readiness, supplierReadinessFilter)
  }), [asOfDate, reportId, supplierAttributeFilter, supplierReadinessFilter, supplierRiskFilter, supplierStatusFilter, suppliers])

  const report = useMemo<ReportDefinition>(() => {
    if (reportId === 'supplier-segmentation') {
      const rows = supplierPortfolioSegments(
        filteredSuppliers.map(supplier => ({
          id: supplier.id,
          supplierStatus: supplier.supplier_status,
          riskRating: supplier.risk_rating,
          preferred: Boolean(supplier.preferred_flag),
          diverse: Boolean(supplier.diversity_flag),
        })),
        supplierPortfolio.values,
        supplierSegmentDimension,
      ).map(segment => ({
        segment: segment.label,
        suppliers: segment.suppliers,
        awardedSuppliers: segment.awardedSuppliers,
        awards: segment.awards,
        spendAddressed: segment.spendAddressed,
        spendShare: segment.spendShare,
        estimated: segment.estimatedSavings,
        executed: segment.executedSavings,
        totalSavings: segment.totalSavings,
        savingsShare: segment.savingsShare,
        realized: segment.realizedSavings,
      }))

      return {
        title: 'Supplier Portfolio Segmentation',
        description: `Awarded spend and savings grouped by ${supplierSegmentDimension.toLowerCase()}, with no invented targets or thresholds.`,
        filename: 'supplier-portfolio-segmentation.csv',
        columns: [
          { key: 'segment', label: supplierSegmentDimension },
          { key: 'suppliers', label: 'Suppliers', format: 'number' },
          { key: 'awardedSuppliers', label: 'Awarded Suppliers', format: 'number' },
          { key: 'awards', label: 'Awards', format: 'number' },
          { key: 'spendAddressed', label: 'Spend Addressed', format: 'currency' },
          { key: 'spendShare', label: 'Spend Share', format: 'percent' },
          { key: 'estimated', label: 'Estimated Pipeline', format: 'currency' },
          { key: 'executed', label: 'Executed Savings', format: 'currency' },
          { key: 'totalSavings', label: 'Total Savings', format: 'currency' },
          { key: 'savingsShare', label: 'Savings Share', format: 'percent' },
          ...(savingsRealizationEnabled ? [{ key: 'realized', label: 'Realized Savings', format: 'currency' as const }] : []),
        ],
        rows,
      }
    }

    if (reportId === 'supplier-performance-risk') {
      const governance = supplierGovernanceSummaries(supplierReviews, supplierRiskIssues)
      const rows = filteredSuppliers.map(supplier => {
        const summary = governance.get(supplier.id)
        return {
          supplier: supplier.supplier_name,
          status: supplier.supplier_status || 'Active',
          relationshipRisk: supplier.risk_rating || 'Unrated',
          owner: personName(supplier.relationship_owner) || 'Unassigned',
          latestReview: summary?.latestReviewDate || null,
          latestScore: summary?.latestOverallScore ?? null,
          performanceNextReview: summary?.performanceNextReviewDate || null,
          relationshipNextReview: supplier.next_review_date,
          unresolvedRisks: summary?.unresolvedRisks || 0,
          criticalRisks: summary?.criticalRisks || 0,
          highRisks: summary?.highRisks || 0,
          mediumRisks: summary?.mediumRisks || 0,
          lowRisks: summary?.lowRisks || 0,
        }
      }).sort((a, b) => (
        b.criticalRisks - a.criticalRisks
        || b.highRisks - a.highRisks
        || b.unresolvedRisks - a.unresolvedRisks
        || (a.latestScore ?? 6) - (b.latestScore ?? 6)
        || a.supplier.localeCompare(b.supplier)
      ))

      return {
        title: 'Supplier Performance & Risk',
        description: 'Latest explicit performance score, separately labeled review plans, and unresolved structured risks. Historical scores are not silently averaged.',
        filename: 'supplier-performance-risk.csv',
        columns: [
          { key: 'supplier', label: 'Supplier' },
          { key: 'status', label: 'Status' },
          { key: 'relationshipRisk', label: 'Relationship Risk' },
          { key: 'owner', label: 'Relationship Owner' },
          { key: 'latestReview', label: 'Latest Performance Review', format: 'date' },
          { key: 'latestScore', label: 'Latest Overall Score', format: 'score' },
          { key: 'performanceNextReview', label: 'Performance Next Review', format: 'date' },
          { key: 'relationshipNextReview', label: 'Relationship Next Review', format: 'date' },
          { key: 'unresolvedRisks', label: 'Unresolved Risks', format: 'number' },
          { key: 'criticalRisks', label: 'Critical', format: 'number' },
          { key: 'highRisks', label: 'High', format: 'number' },
          { key: 'mediumRisks', label: 'Medium', format: 'number' },
          { key: 'lowRisks', label: 'Low', format: 'number' },
        ],
        rows,
      }
    }

    if (reportId === 'supplier-portfolio') {
      const rows = filteredSuppliers.map(supplier => {
        const value = supplierPortfolio.values.get(supplier.id)
        return {
          supplier: supplier.supplier_name,
          status: supplier.supplier_status || 'Active',
          risk: supplier.risk_rating || 'Unrated',
          preferred: supplier.preferred_flag ? 'Yes' : 'No',
          diverse: supplier.diversity_flag ? 'Yes' : 'No',
          awards: value?.awards || 0,
          spendAddressed: value?.spendAddressed || 0,
          spendShare: value?.spendShare ?? null,
          estimated: value?.estimatedSavings || 0,
          executed: value?.executedSavings || 0,
          totalSavings: value?.totalSavings || 0,
          savingsShare: value?.savingsShare ?? null,
          realized: value?.realizedSavings || 0,
          realizationRate: value?.realizationRate ?? null,
        }
      }).sort((a, b) => b.spendAddressed - a.spendAddressed || b.totalSavings - a.totalSavings || a.supplier.localeCompare(b.supplier))

      return {
        title: 'Supplier Portfolio Value',
        description: 'Awarded-project spend, estimated and executed savings, concentration, and supplier attributes.',
        filename: 'supplier-portfolio-value.csv',
        columns: [
          { key: 'supplier', label: 'Supplier' },
          { key: 'status', label: 'Status' },
          { key: 'risk', label: 'Risk' },
          { key: 'preferred', label: 'Preferred' },
          { key: 'diverse', label: 'Diverse' },
          { key: 'awards', label: 'Awards', format: 'number' },
          { key: 'spendAddressed', label: 'Spend Addressed', format: 'currency' },
          { key: 'spendShare', label: 'Spend Share', format: 'percent' },
          { key: 'estimated', label: 'Estimated Pipeline', format: 'currency' },
          { key: 'executed', label: 'Executed Savings', format: 'currency' },
          { key: 'totalSavings', label: 'Total Savings', format: 'currency' },
          { key: 'savingsShare', label: 'Savings Share', format: 'percent' },
          ...(savingsRealizationEnabled ? [
            { key: 'realized', label: 'Realized Savings', format: 'currency' as const },
            { key: 'realizationRate', label: 'Realization Rate', format: 'percent' as const },
          ] : []),
        ],
        rows,
      }
    }

    if (reportId === 'supplier-readiness') {
      const linkedProjectsBySupplier = new Map<string, Set<string>>()
      const awardsBySupplier = new Map<string, Set<string>>()
      for (const event of events) {
        for (const supplierId of [event.incumbent_supplier_id, event.awarded_supplier_id]) {
          if (!supplierId) continue
          const linked = linkedProjectsBySupplier.get(supplierId) ?? new Set<string>()
          linked.add(event.id)
          linkedProjectsBySupplier.set(supplierId, linked)
        }
        if (event.awarded_supplier_id) {
          const awards = awardsBySupplier.get(event.awarded_supplier_id) ?? new Set<string>()
          awards.add(event.id)
          awardsBySupplier.set(event.awarded_supplier_id, awards)
        }
      }

      const rows = filteredSuppliers.map(supplier => {
        const owner = personName(supplier.relationship_owner)
        const readiness = assessSupplierReadiness({
          relationshipOwner: owner,
          nextReviewDate: supplier.next_review_date,
          risk: supplier.risk_rating,
        }, asOfDate)
        return {
          supplier: supplier.supplier_name,
          status: supplier.supplier_status || 'Active',
          risk: supplier.risk_rating || 'Unrated',
          owner: owner || 'Unassigned',
          nextReview: supplier.next_review_date,
          preferred: supplier.preferred_flag ? 'Yes' : 'No',
          diverse: supplier.diversity_flag ? 'Yes' : 'No',
          linkedProjects: linkedProjectsBySupplier.get(supplier.id)?.size || 0,
          awards: awardsBySupplier.get(supplier.id)?.size || 0,
          attention: readiness.alerts.join('; ') || '—',
          setupGaps: readiness.gaps.join('; ') || 'Complete',
          _priority: readiness.priority,
        }
      }).sort((a, b) => a._priority - b._priority || a.supplier.localeCompare(b.supplier))

      return {
        title: 'Supplier Relationship Readiness',
        description: 'Ownership, review planning, risk coverage, attributes, and project linkage for every supplier relationship.',
        filename: 'supplier-relationship-readiness.csv',
        columns: [
          { key: 'supplier', label: 'Supplier' },
          { key: 'status', label: 'Status' },
          { key: 'risk', label: 'Risk' },
          { key: 'owner', label: 'Relationship Owner' },
          { key: 'nextReview', label: 'Next Review', format: 'date' },
          { key: 'preferred', label: 'Preferred' },
          { key: 'diverse', label: 'Diverse' },
          { key: 'linkedProjects', label: 'Linked Projects', format: 'number' },
          { key: 'awards', label: 'Awards', format: 'number' },
          { key: 'attention', label: 'Attention' },
          { key: 'setupGaps', label: 'Setup Gaps' },
        ],
        rows,
      }
    }

    const filteredIds = new Set(filteredEvents.map(event => event.id))
    const totalsByEvent = new Map<string, SavingsTotals>()
    for (const calculation of canonicalSavings.calculations) {
      if (!calculation.event_id || !filteredIds.has(calculation.event_id)) continue
      const current = totalsByEvent.get(calculation.event_id) ?? { reduction: 0, avoidance: 0, total: 0, estimated: 0, executed: 0 }
      current.reduction += num(calculation.cost_reduction_amount)
      current.avoidance += num(calculation.cost_avoidance_amount)
      current.total += reportedSavings(calculation)
      if (calculation.calculation_status === 'executed') current.executed += reportedSavings(calculation)
      else current.estimated += reportedSavings(calculation)
      totalsByEvent.set(calculation.event_id, current)
    }

    const projectRows = filteredEvents.map(event => {
      const savings = totalsByEvent.get(event.id) ?? { reduction: 0, avoidance: 0, total: 0, estimated: 0, executed: 0 }
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
        estimated: savings.estimated,
        executed: savings.executed,
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
      { key: 'reduction', label: 'Cost Reduction', format: 'reduction' },
      { key: 'avoidance', label: 'Cost Avoidance', format: 'currency' },
      { key: 'savings', label: 'Total Savings', format: 'currency' },
      { key: 'estimated', label: 'Estimated Pipeline', format: 'currency' },
      { key: 'executed', label: 'Executed Savings', format: 'currency' },
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
          { key: 'reduction', label: 'Cost Reduction', format: 'reduction' },
          { key: 'avoidance', label: 'Cost Avoidance', format: 'currency' },
          { key: 'savings', label: 'Total Savings', format: 'currency' },
          { key: 'estimated', label: 'Estimated Pipeline', format: 'currency' },
          { key: 'executed', label: 'Executed Savings', format: 'currency' },
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
        estimated: values.estimated,
        executed: values.executed,
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
  }, [asOfDate, canonicalSavings, events, filteredEvents, filteredSuppliers, reportId, savingsRealizationEnabled, supplierPortfolio, supplierReviews, supplierRiskIssues, supplierSegmentDimension])

  const supplierReport = reportId === 'supplier-readiness' || reportId === 'supplier-portfolio' || reportId === 'supplier-performance-risk' || reportId === 'supplier-segmentation'
  const readinessReport = reportId === 'supplier-readiness'
  const segmentationReport = reportId === 'supplier-segmentation'
  const filtersActive = supplierReport
    ? Boolean(supplierStatusFilter || supplierRiskFilter || supplierAttributeFilter || (readinessReport && supplierReadinessFilter))
    : Boolean(typeFilter || statusFilter || businessUnitFilter || buyerFilter)

  const resetFilters = () => {
    if (supplierReport) {
      setSupplierStatusFilter('')
      setSupplierRiskFilter('')
      setSupplierAttributeFilter('')
      setSupplierReadinessFilter('')
    } else {
      setTypeFilter('')
      setStatusFilter('')
      setBusinessUnitFilter('')
      setBuyerFilter('')
    }
  }

  return (
    <div className="mt-6 space-y-6">
      {canonicalSavings.dataQuality.duplicateCalculationEvents > 0 && (
        <div role="alert" className="flex items-start gap-3 rounded-lg border border-amber-200 bg-amber-50 p-4 text-sm text-amber-800 dark:border-amber-800 dark:bg-amber-900/30 dark:text-amber-200">
          <AlertTriangle className="mt-0.5 h-5 w-5 shrink-0" aria-hidden="true" />
          <p>
            <strong>Duplicate savings records detected.</strong>{' '}
            {canonicalSavings.dataQuality.duplicateCalculationEvents} project{canonicalSavings.dataQuality.duplicateCalculationEvents === 1 ? '' : 's'} had more than one calculation.
            These reports use the earliest record once to prevent double counting. Ask a workspace administrator to investigate the data.
          </p>
        </div>
      )}
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
              {['Pipeline', 'Savings', 'Projects', 'Suppliers'].map(group => (
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
            <h2 className="text-sm font-semibold text-[var(--text)]">{supplierReport ? 'Supplier filters' : 'Portfolio filters'}</h2>
          </div>
          {filtersActive && (
            <button type="button" onClick={resetFilters} className="inline-flex items-center gap-1.5 text-xs font-semibold text-[var(--brand-ink)] hover:underline">
              <RotateCcw className="h-3.5 w-3.5" aria-hidden="true" />
              Clear filters
            </button>
          )}
        </div>
        {supplierReport ? (
          <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 xl:grid-cols-4">
            <FilterSelect label="Supplier status" value={supplierStatusFilter} onChange={setSupplierStatusFilter} options={supplierStatuses} allLabel="All supplier statuses" />
            <FilterSelect label="Risk" value={supplierRiskFilter} onChange={setSupplierRiskFilter} options={supplierRisks} allLabel="All risk ratings" />
            <FilterSelect label="Attribute" value={supplierAttributeFilter} onChange={setSupplierAttributeFilter} options={['Preferred', 'Diverse']} allLabel="All attributes" />
            {readinessReport && <FilterSelect label="Readiness" value={supplierReadinessFilter} onChange={value => setSupplierReadinessFilter(value as SupplierReadinessFilter)} options={['Needs attention', 'Setup incomplete', 'Ready']} allLabel="All readiness states" />}
            {segmentationReport && (
              <div>
                <label htmlFor="report-segment-by" className="text-xs font-medium text-[var(--text-3)]">Segment by</label>
                <Select
                  id="report-segment-by"
                  value={supplierSegmentDimension}
                  onChange={event => setSupplierSegmentDimension(event.target.value as SupplierSegmentDimension)}
                  className="mt-1.5"
                >
                  {(['Preferred status', 'Diversity', 'Relationship risk', 'Supplier status'] as SupplierSegmentDimension[]).map(option => (
                    <option key={option} value={option}>{option}</option>
                  ))}
                </Select>
              </div>
            )}
          </div>
        ) : (
          <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 xl:grid-cols-4">
            <FilterSelect label="Project type" value={typeFilter} onChange={setTypeFilter} options={eventTypes} allLabel="All project types" />
            <FilterSelect label="Status" value={statusFilter} onChange={setStatusFilter} options={statuses} allLabel="All statuses" />
            <FilterSelect label="Business unit" value={businessUnitFilter} onChange={setBusinessUnitFilter} options={businessUnits} allLabel="All business units" />
            <FilterSelect label="Buyer" value={buyerFilter} onChange={setBuyerFilter} options={buyers} allLabel="All buyers" />
          </div>
        )}
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
                    className={`px-4 py-3 text-xs font-semibold uppercase tracking-wider text-[var(--text-3)] ${column.format === 'currency' || column.format === 'number' || column.format === 'percent' || column.format === 'score' ? 'text-right' : 'text-left'}`}
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
                    const numeric = column.format === 'currency' || column.format === 'reduction' || column.format === 'number' || column.format === 'percent' || column.format === 'score'
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
