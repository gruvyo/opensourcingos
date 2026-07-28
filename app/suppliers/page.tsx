import { createClient } from '@/lib/supabase/server'
import Link from 'next/link'
import { Plus } from 'lucide-react'
import { SuppliersView } from '@/components/suppliers-view'

export default async function SuppliersPage() {
  const supabase = await createClient()

  const { data: suppliers, error: suppliersError } = await supabase
    .from('suppliers')
    .select(`
      id, supplier_name, created_at,
      events_as_incumbent:sourcing_events!sourcing_events_incumbent_supplier_id_fkey(id),
      events_as_awarded:sourcing_events!sourcing_events_awarded_supplier_id_fkey(id)
    `)
    .order('supplier_name', { ascending: true })

  // A failed query here would render as "0 suppliers", which is indistinguishable
  // from a genuinely empty directory. Say which one it is.
  const loadError = suppliersError?.message || null

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
      <div className="flex items-center justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold text-[var(--text)]">Suppliers</h1>
          <p className="mt-1 text-sm text-[var(--text-2)]">
            Supplier directory — {suppliersWithCounts.length} total
          </p>
        </div>
        <Link
          href="/events/new"
          className="inline-flex shrink-0 items-center gap-2 rounded-md bg-[var(--brand)] px-4 py-2 text-sm font-semibold text-[var(--on-brand)] transition-colors hover:bg-[var(--brand-hover)]"
        >
          <Plus className="h-4 w-4" />
          Add via New Project
        </Link>
      </div>

      {loadError && (
        <div className="mt-6 rounded-lg bg-red-50 p-4 text-sm text-red-700 dark:bg-red-900/30 dark:text-red-300" role="alert">
          <strong>These figures are incomplete.</strong> A query failed: {loadError}. Do not report
          from this page until it loads cleanly.
        </div>
      )}

      <SuppliersView suppliers={suppliersWithCounts} />
    </div>
  )
}