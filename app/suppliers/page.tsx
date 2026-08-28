import Link from 'next/link'
import { Plus } from 'lucide-react'
import { createClient } from '@/lib/supabase/server'
import { fetchPortfolioRows } from '@/lib/supabase/portfolio-query'
import { SuppliersView, type SupplierSummary } from '@/components/suppliers-view'
import { PageHeader } from '@/components/ui/page-header'
import { formatDate } from '@/lib/utils'
import { dateKeyInTimeZone } from '@/lib/supplier-readiness'
import { assessSupplierAttention } from '@/lib/supplier-attention'
import {
  supplierGovernanceSummaries,
  type SupplierPerformanceReviewSummaryRow,
  type SupplierRiskSummaryRow,
} from '@/lib/supplier-governance-report'

type RelatedEvent = {
  id: string
  incumbent_supplier_id: string | null
  awarded_supplier_id: string | null
}

export default async function SuppliersPage() {
  const supabase = await createClient()

  const [
    { data: suppliers, error: suppliersError },
    { data: events, error: eventsError },
    { data: supplierReviews, error: supplierReviewsError },
    { data: supplierRisks, error: supplierRisksError },
    { data: settings, error: settingsError },
  ] = await Promise.all([
    fetchPortfolioRows('Suppliers', (from, to) => (
      supabase
        .from('suppliers')
        .select(`
          id, supplier_name, supplier_status, preferred_flag, diversity_flag,
          risk_rating, next_review_date, created_at
        `, { count: 'exact' })
        .order('supplier_name', { ascending: true })
        .order('id', { ascending: true })
        .range(from, to)
    )),
    fetchPortfolioRows('Projects', (from, to) => (
      supabase
        .from('sourcing_events')
        .select('id, incumbent_supplier_id, awarded_supplier_id', { count: 'exact' })
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
    fetchPortfolioRows('Supplier risks', (from, to) => (
      supabase.from('supplier_risks').select('id, supplier_id, severity, risk_status', { count: 'exact' })
        .order('supplier_id', { ascending: true })
        .order('id', { ascending: true })
        .range(from, to)
    )),
    supabase.from('organization_settings').select('timezone').maybeSingle(),
  ])

  const loadError = suppliersError?.message
    || eventsError?.message
    || supplierReviewsError?.message
    || supplierRisksError?.message
    || settingsError?.message
    || null
  const asOfDate = dateKeyInTimeZone(new Date(), settings?.timezone || 'America/Chicago')
  const governance = supplierGovernanceSummaries(
    (supplierReviews || []) as SupplierPerformanceReviewSummaryRow[],
    (supplierRisks || []) as SupplierRiskSummaryRow[],
  )

  const incumbentProjectsBySupplier = new Map<string, Set<string>>()
  const awardedProjectsBySupplier = new Map<string, Set<string>>()
  for (const event of (events || []) as RelatedEvent[]) {
    if (event.incumbent_supplier_id) {
      const ids = incumbentProjectsBySupplier.get(event.incumbent_supplier_id) ?? new Set<string>()
      ids.add(event.id)
      incumbentProjectsBySupplier.set(event.incumbent_supplier_id, ids)
    }
    if (event.awarded_supplier_id) {
      const ids = awardedProjectsBySupplier.get(event.awarded_supplier_id) ?? new Set<string>()
      ids.add(event.id)
      awardedProjectsBySupplier.set(event.awarded_supplier_id, ids)
    }
  }

  const supplierSummaries: SupplierSummary[] = (suppliers || []).map(supplier => {
    const incumbentEvents = incumbentProjectsBySupplier.get(supplier.id) ?? new Set<string>()
    const awardedEvents = awardedProjectsBySupplier.get(supplier.id) ?? new Set<string>()
    const linkedEventIds = new Set([
      ...incumbentEvents,
      ...awardedEvents,
    ])
    const supplierGovernance = governance.get(supplier.id)
    const attention = assessSupplierAttention({
      status: supplier.supplier_status || 'Active',
      risk: supplier.risk_rating,
      nextReviewDate: supplier.next_review_date,
      performanceNextReviewDate: supplierGovernance?.performanceNextReviewDate || null,
      criticalRiskIssues: supplierGovernance?.criticalRisks || 0,
      highRiskIssues: supplierGovernance?.highRisks || 0,
    }, asOfDate)

    return {
      id: supplier.id,
      name: supplier.supplier_name,
      status: supplier.supplier_status || 'Active',
      preferred: Boolean(supplier.preferred_flag),
      diverse: Boolean(supplier.diversity_flag),
      risk: supplier.risk_rating,
      incumbentProjects: incumbentEvents.size,
      awardedProjects: awardedEvents.size,
      linkedProjects: linkedEventIds.size,
      needsAttention: attention.reasons.length > 0,
      // Format timestamps on the server so hydration cannot change the date
      // when the browser is in a different timezone.
      addedOn: formatDate(supplier.created_at),
    }
  })

  return (
    <div className="mx-auto w-full max-w-[1600px] p-4 sm:p-6 lg:p-8">
      <PageHeader
        eyebrow="Supplier intelligence"
        title="Suppliers"
        description="A portfolio view of supplier relationships, sourcing activity, diversity, preference, and risk."
        actions={(
          <Link
            href="/suppliers/new"
            className="inline-flex items-center gap-2 rounded-lg bg-[var(--brand)] px-4 py-2.5 text-sm font-semibold text-[var(--on-brand)] shadow-sm transition-colors hover:bg-[var(--brand-hover)] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--brand)] focus-visible:ring-offset-2"
          >
            <Plus className="h-4 w-4" aria-hidden="true" />
            New supplier
          </Link>
        )}
      />

      {loadError ? (
        <div className="mt-6 rounded-xl bg-red-50 p-4 text-sm text-red-700 dark:bg-red-900/30 dark:text-red-300" role="alert">
          <strong>These figures are incomplete.</strong> A query failed: {loadError}. Do not report
          from this page until it loads cleanly.
        </div>
      ) : null}

      <SuppliersView suppliers={supplierSummaries} />
    </div>
  )
}
