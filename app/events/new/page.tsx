import { createClient } from '@/lib/supabase/server'
import { EventForm } from '@/components/event-form'
import Link from 'next/link'
import { ArrowLeft } from 'lucide-react'

export default async function NewEventPage() {
  const supabase = await createClient()

  const [{ data: categories }, { data: businessUnits }, { data: costCenters }, { data: suppliers }] = await Promise.all([
    supabase.from('categories').select('id, category_name').order('category_name'),
    supabase.from('business_units').select('id, business_unit_name').order('business_unit_name'),
    supabase.from('cost_centers').select('id, cost_center_name, business_unit_id').order('cost_center_name'),
    supabase.from('suppliers').select('id, supplier_name').order('supplier_name'),
  ])

  return (
    <div className="p-8">
      <Link href="/events" className="mb-4 flex items-center gap-2 text-sm text-gray-600 hover:text-gray-900">
        <ArrowLeft className="h-4 w-4" />
        Back to Events
      </Link>
      <h1 className="text-2xl font-bold text-gray-900">New Sourcing Event</h1>
      <p className="mt-1 text-sm text-gray-600">
        Create a new procurement sourcing event
      </p>
      <EventForm
        categories={categories || []}
        businessUnits={businessUnits || []}
        costCenters={costCenters || []}
        suppliers={suppliers || []}
      />
    </div>
  )
}
