import { createClient } from '@/lib/supabase/server'
import Link from 'next/link'
import { Plus } from 'lucide-react'
import { SuppliersView } from '@/components/suppliers-view'

export default async function SuppliersPage() {
  const supabase = await createClient()

  const { data: suppliers } = await supabase
    .from('suppliers')
    .select(`
      id, supplier_name, created_at,
      events_as_incumbent:sourcing_events!sourcing_events_incumbent_supplier_id_fkey(id),
      events_as_awarded:sourcing_events!sourcing_events_awarded_supplier_id_fkey(id)
    `)
    .order('supplier_name', { ascending: true })

  // Count events per supplier
  const suppliersWithCounts = (suppliers || []).map((s: any) => {
    const incumbentCount = Array.isArray(s.events_as_incumbent) ? s.events_as_incumbent.length : 0
    const awardedCount = Array.isArray(s.events_as_awarded) ? s.events_as_awarded.length : 0
    return {
      ...s,
      event_count: incumbentCount + awardedCount,
    }
  })

  return (
    <div className="p-8">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-gray-900 dark:text-gray-100">Suppliers</h1>
          <p className="mt-1 text-sm text-gray-600 dark:text-gray-400">
            Supplier directory — {suppliersWithCounts.length} total
          </p>
        </div>
        <Link
          href="/events/new"
          className="flex items-center gap-2 rounded-lg bg-indigo-600 px-4 py-2 text-sm font-medium text-white transition-colors hover:bg-indigo-700"
        >
          <Plus className="h-4 w-4" />
          Add via New Project
        </Link>
      </div>

      <SuppliersView suppliers={suppliersWithCounts} />
    </div>
  )
}