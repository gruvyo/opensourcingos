import Link from 'next/link'
import { Plus } from 'lucide-react'
import { createClient } from '@/lib/supabase/server'
import { SuppliersView, type SupplierSummary } from '@/components/suppliers-view'
import { PageHeader } from '@/components/ui/page-header'

type RelatedEvent = { id: string }

function relatedEvents(value: unknown): RelatedEvent[] {
  if (!Array.isArray(value)) return []
  return value.filter((event): event is RelatedEvent => (
    typeof event === 'object'
    && event !== null
    && typeof (event as { id?: unknown }).id === 'string'
  ))
}

export default async function SuppliersPage() {
  const supabase = await createClient()

  const { data: suppliers, error: suppliersError } = await supabase
    .from('suppliers')
    .select(`
      id, supplier_name, supplier_status, preferred_flag, diversity_flag,
      risk_rating, created_at,
      events_as_incumbent:sourcing_events!sourcing_events_incumbent_supplier_id_fkey(id),
      events_as_awarded:sourcing_events!sourcing_events_awarded_supplier_id_fkey(id)
    `)
    .order('supplier_name', { ascending: true })

  const loadError = suppliersError?.message || null

  const supplierSummaries: SupplierSummary[] = (suppliers || []).map(supplier => {
    const incumbentEvents = relatedEvents(supplier.events_as_incumbent)
    const awardedEvents = relatedEvents(supplier.events_as_awarded)
    const linkedEventIds = new Set([
      ...incumbentEvents.map(event => event.id),
      ...awardedEvents.map(event => event.id),
    ])

    return {
      id: supplier.id,
      name: supplier.supplier_name,
      status: supplier.supplier_status || 'Active',
      preferred: Boolean(supplier.preferred_flag),
      diverse: Boolean(supplier.diversity_flag),
      risk: supplier.risk_rating,
      incumbentProjects: incumbentEvents.length,
      awardedProjects: awardedEvents.length,
      linkedProjects: linkedEventIds.size,
      createdAt: supplier.created_at,
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
            href="/events/new"
            className="inline-flex items-center gap-2 rounded-lg bg-[var(--brand)] px-4 py-2.5 text-sm font-semibold text-[var(--on-brand)] shadow-sm transition-colors hover:bg-[var(--brand-hover)] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--brand)] focus-visible:ring-offset-2"
          >
            <Plus className="h-4 w-4" aria-hidden="true" />
            New sourcing project
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
