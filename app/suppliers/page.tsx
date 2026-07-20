import { createClient } from '@/lib/supabase/server'
import Link from 'next/link'
import { Users, Plus, Building2 } from 'lucide-react'

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

      {suppliersWithCounts.length === 0 ? (
        <div className="mt-8 rounded-lg border border-gray-200 bg-white p-12 text-center shadow-sm dark:border-gray-700 dark:bg-gray-800">
          <Users className="mx-auto mb-3 h-10 w-10 text-gray-300 dark:text-gray-600" />
          <h3 className="text-lg font-medium text-gray-900 dark:text-gray-100">No suppliers yet</h3>
          <p className="mt-1 text-sm text-gray-500 dark:text-gray-400">
            Suppliers are added automatically when you create a project and select "New" next to the supplier field.
          </p>
        </div>
      ) : (
        <div className="mt-6 grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
          {suppliersWithCounts.map((supplier: any) => (
            <div
              key={supplier.id}
              className="rounded-lg border border-gray-200 bg-white p-5 shadow-sm dark:border-gray-700 dark:bg-gray-800"
            >
              <div className="flex items-start gap-3">
                <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-lg bg-indigo-50 dark:bg-indigo-900/30">
                  <Building2 className="h-5 w-5 text-indigo-600 dark:text-indigo-400" />
                </div>
                <div className="min-w-0 flex-1">
                  <h3 className="truncate text-sm font-semibold text-gray-900 dark:text-gray-100">
                    {supplier.supplier_name}
                  </h3>
                  <p className="mt-1 text-xs text-gray-500 dark:text-gray-400">
                    {supplier.event_count} project{supplier.event_count !== 1 ? 's' : ''}
                  </p>
                </div>
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  )
}