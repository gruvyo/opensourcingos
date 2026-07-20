import { createClient } from '@/lib/supabase/server'
import { EventsList } from '@/components/events-list'
import Link from 'next/link'
import { Plus } from 'lucide-react'

export default async function EventsPage() {
  const supabase = await createClient()

  const { data: events } = await supabase
    .from('sourcing_events')
    .select(`
      *,
      category:categories(category_name),
      business_unit:business_units(business_unit_name),
      incumbent_supplier:suppliers!sourcing_events_incumbent_supplier_id_fkey(supplier_name),
      awarded_supplier:suppliers!sourcing_events_awarded_supplier_id_fkey(supplier_name)
    `)
    .order('created_at', { ascending: false })

  return (
    <div className="p-8">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-gray-900 dark:text-gray-100">Projects</h1>
          <p className="mt-1 text-sm text-gray-600 dark:text-gray-400">
            Manage and track all sourcing events and support projects
          </p>
        </div>
        <Link
          href="/events/new"
          className="flex items-center gap-2 rounded-lg bg-indigo-600 px-4 py-2 text-sm font-medium text-white transition-colors hover:bg-indigo-700"
        >
          <Plus className="h-4 w-4" />
          New Project
        </Link>
      </div>

      <EventsList events={events || []} />
    </div>
  )
}
