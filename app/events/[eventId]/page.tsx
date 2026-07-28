import { createClient } from '@/lib/supabase/server'
import { EventDetail } from '@/components/event-detail'
import Link from 'next/link'
import { ArrowLeft } from 'lucide-react'
import { notFound } from 'next/navigation'

export default async function EventDetailPage({
  params,
}: {
  params: Promise<{ eventId: string }>
}) {
  const { eventId } = await params
  const supabase = await createClient()

  const [
    { data: event, error: eventError },
    { data: scopeLines, error: scopeLinesError },
    { data: suppliers, error: suppliersError },
    { data: categories, error: categoriesError },
    { data: businessUnits, error: businessUnitsError },
    { data: costCenters, error: costCentersError },
  ] = await Promise.all([
    supabase.from('sourcing_events')
      .select(`
        *,
        category:categories(category_name),
        business_unit:business_units(business_unit_name),
        cost_center:cost_centers(cost_center_name),
        incumbent_supplier:suppliers!sourcing_events_incumbent_supplier_id_fkey(supplier_name),
        awarded_supplier:suppliers!sourcing_events_awarded_supplier_id_fkey(supplier_name)
      `)
      .eq('id', eventId)
      .single(),
    supabase.from('event_scope_lines')
      .select('id, line_number, item_service_name, uom')
      .eq('event_id', eventId)
      .order('line_number', { ascending: true }),
    supabase.from('suppliers')
      .select('id, supplier_name')
      .order('supplier_name'),
    supabase.from('categories')
      .select('id, category_name')
      .order('category_name'),
    supabase.from('business_units')
      .select('id, business_unit_name')
      .order('business_unit_name'),
    supabase.from('cost_centers')
      .select('id, cost_center_name')
      .order('cost_center_name'),
  ])

  if (!event) notFound()

  // .single() legitimately errors (PGRST116) when the row doesn't exist —
  // that's not a load failure, it's handled by notFound() above.
  const loadError = (eventError && eventError.code !== 'PGRST116' ? eventError.message : null)
    || scopeLinesError?.message || suppliersError?.message || categoriesError?.message
    || businessUnitsError?.message || costCentersError?.message || null

  return (
    <div className="p-8">
      <Link href="/events" className="mb-4 flex items-center gap-2 text-sm text-gray-600 hover:text-gray-900 dark:text-gray-400 dark:hover:text-gray-200">
        <ArrowLeft className="h-4 w-4" />
        Back to Projects
      </Link>

      {loadError && (
        <div className="mb-4 rounded-lg bg-red-50 p-4 text-sm text-red-700 dark:bg-red-900/30 dark:text-red-300" role="alert">
          <strong>These figures are incomplete.</strong> A query failed: {loadError}. Do not report
          from this page until it loads cleanly.
        </div>
      )}

      <EventDetail
        event={event}
        scopeLines={scopeLines || []}
        suppliers={suppliers || []}
        categories={categories || []}
        businessUnits={businessUnits || []}
        costCenters={costCenters || []}
      />
    </div>
  )
}