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

  const { data: event } = await supabase
    .from('sourcing_events')
    .select(`
      *,
      category:categories(category_name),
      business_unit:business_units(business_unit_name),
      cost_center:cost_centers(cost_center_name),
      incumbent_supplier:suppliers!sourcing_events_incumbent_supplier_id_fkey(supplier_name),
      awarded_supplier:suppliers!sourcing_events_awarded_supplier_id_fkey(supplier_name)
    `)
    .eq('id', eventId)
    .single()

  if (!event) notFound()

  const [{ data: scopeLines }, { data: suppliers }] = await Promise.all([
    supabase.from('event_scope_lines')
      .select('id, line_number, item_service_name, uom')
      .eq('event_id', eventId)
      .order('line_number', { ascending: true }),
    supabase.from('suppliers')
      .select('id, supplier_name')
      .order('supplier_name'),
  ])

  return (
    <div className="p-8">
      <Link href="/events" className="mb-4 flex items-center gap-2 text-sm text-gray-600 hover:text-gray-900 dark:text-gray-400 dark:hover:text-gray-200">
        <ArrowLeft className="h-4 w-4" />
        Back to Projects
      </Link>
      <EventDetail event={event} scopeLines={scopeLines || []} suppliers={suppliers || []} />
    </div>
  )
}