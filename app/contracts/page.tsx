import { createClient } from '@/lib/supabase/server'
import Link from 'next/link'
import { formatDate, statusColor } from '@/lib/utils'
import { FileText, Clock, Calendar } from 'lucide-react'

function getFirst(obj: any): any {
  if (!obj) return null
  if (Array.isArray(obj)) return obj[0] || null
  return obj
}

function daysBetween(start: string, end: string): number {
  if (!start || !end) return 0
  const diff = new Date(end).getTime() - new Date(start).getTime()
  return Math.round(diff / (1000 * 60 * 60 * 24))
}

export default async function ContractsPage() {
  const supabase = await createClient()

  const { data: events } = await supabase
    .from('sourcing_events')
    .select(`
      id, event_name, event_type, event_status,
      contract_start_date, contract_end_date,
      category:categories(category_name),
      incumbent_supplier:suppliers!sourcing_events_incumbent_supplier_id_fkey(supplier_name),
      awarded_supplier:suppliers!sourcing_events_awarded_supplier_id_fkey(supplier_name)
    `)
    .not('contract_start_date', 'is', null)
    .order('contract_end_date', { ascending: true, nullsFirst: false })

  const allEvents = events || []
  const now = new Date()
  const active = allEvents.filter((e: any) => {
    if (!e.contract_start_date || !e.contract_end_date) return false
    return new Date(e.contract_start_date) <= now && new Date(e.contract_end_date) >= now
  })
  const expiringSoon = allEvents.filter((e: any) => {
    if (!e.contract_end_date) return false
    const days = daysBetween(now.toISOString().split('T')[0], e.contract_end_date)
    return days >= 0 && days <= 90
  })
  const expired = allEvents.filter((e: any) => {
    if (!e.contract_end_date) return false
    return new Date(e.contract_end_date) < now
  })

  return (
    <div className="p-8">
      <div className="mb-6">
        <h1 className="text-2xl font-bold text-gray-900 dark:text-gray-100">Contracts</h1>
        <p className="mt-1 text-sm text-gray-600 dark:text-gray-400">
          Track contract periods and expiration dates
        </p>
      </div>

      {/* Summary cards */}
      <div className="grid grid-cols-2 gap-4 lg:grid-cols-4">
        <div className="rounded-lg border border-gray-200 bg-white p-6 shadow-sm dark:border-gray-700 dark:bg-gray-800">
          <p className="text-sm font-medium text-gray-500 dark:text-gray-400">Total Contracts</p>
          <p className="mt-2 text-2xl font-bold text-gray-900 dark:text-gray-100">{allEvents.length}</p>
        </div>
        <div className="rounded-lg border border-gray-200 bg-white p-6 shadow-sm dark:border-gray-700 dark:bg-gray-800">
          <p className="text-sm font-medium text-gray-500 dark:text-gray-400">Active</p>
          <p className="mt-2 text-2xl font-bold text-green-600 dark:text-green-400">{active.length}</p>
        </div>
        <div className="rounded-lg border border-gray-200 bg-white p-6 shadow-sm dark:border-gray-700 dark:bg-gray-800">
          <p className="text-sm font-medium text-gray-500 dark:text-gray-400">Expiring (90 days)</p>
          <p className="mt-2 text-2xl font-bold text-amber-600 dark:text-amber-400">{expiringSoon.length}</p>
        </div>
        <div className="rounded-lg border border-gray-200 bg-white p-6 shadow-sm dark:border-gray-700 dark:bg-gray-800">
          <p className="text-sm font-medium text-gray-500 dark:text-gray-400">Expired</p>
          <p className="mt-2 text-2xl font-bold text-red-600 dark:text-red-400">{expired.length}</p>
        </div>
      </div>

      {/* Contracts table */}
      <div className="mt-6 overflow-x-auto rounded-lg border border-gray-200 bg-white shadow-sm dark:border-gray-700 dark:bg-gray-800">
        <div className="border-b border-gray-200 px-6 py-4 dark:border-gray-700">
          <h3 className="text-sm font-semibold text-gray-900 dark:text-gray-100">All Contracts</h3>
        </div>
        <table className="w-full min-w-[800px]">
          <thead>
            <tr className="border-b border-gray-200 bg-gray-50 dark:border-gray-700 dark:bg-gray-900/50">
              <th className="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-gray-500 dark:text-gray-400">Project</th>
              <th className="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-gray-500 dark:text-gray-400">Supplier</th>
              <th className="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-gray-500 dark:text-gray-400">Category</th>
              <th className="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-gray-500 dark:text-gray-400">Contract Start</th>
              <th className="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-gray-500 dark:text-gray-400">Contract End</th>
              <th className="px-4 py-3 text-right text-xs font-semibold uppercase tracking-wider text-gray-500 dark:text-gray-400">Days Left</th>
              <th className="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-gray-500 dark:text-gray-400">Status</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-gray-200 dark:divide-gray-700">
            {allEvents.length === 0 ? (
              <tr>
                <td colSpan={7} className="px-4 py-12 text-center">
                  <FileText className="mx-auto mb-2 h-8 w-8 text-gray-300 dark:text-gray-600" />
                  <p className="text-sm text-gray-500 dark:text-gray-400">No contracts with dates yet</p>
                  <p className="mt-1 text-xs text-gray-400 dark:text-gray-500">
                    Contracts appear when sourcing events have contract start/end dates set
                  </p>
                </td>
              </tr>
            ) : (
              allEvents.map((event: any) => {
                const daysLeft = event.contract_end_date ? daysBetween(now.toISOString().split('T')[0], event.contract_end_date) : null
                const isExpired = daysLeft !== null && daysLeft < 0
                const isExpiring = daysLeft !== null && daysLeft >= 0 && daysLeft <= 90
                return (
                  <tr key={event.id} className="hover:bg-gray-50 dark:hover:bg-gray-700/50">
                    <td className="px-4 py-3">
                      <Link href={`/events/${event.id}`} className="text-sm font-medium text-indigo-600 hover:text-indigo-800 dark:text-indigo-400">
                        {event.event_name}
                      </Link>
                    </td>
                    <td className="px-4 py-3 text-sm text-gray-600 dark:text-gray-400">
                      {getFirst(event.awarded_supplier)?.supplier_name || getFirst(event.incumbent_supplier)?.supplier_name || '—'}
                    </td>
                    <td className="px-4 py-3 text-sm text-gray-600 dark:text-gray-400">
                      {getFirst(event.category)?.category_name || '—'}
                    </td>
                    <td className="px-4 py-3 text-sm text-gray-600 dark:text-gray-400">{formatDate(event.contract_start_date)}</td>
                    <td className="px-4 py-3 text-sm text-gray-600 dark:text-gray-400">{formatDate(event.contract_end_date)}</td>
                    <td className="px-4 py-3 text-right">
                      {daysLeft !== null && (
                        <span className={`text-sm font-medium ${
                          isExpired ? 'text-red-600 dark:text-red-400' :
                          isExpiring ? 'text-amber-600 dark:text-amber-400' :
                          'text-gray-600 dark:text-gray-400'
                        }`}>
                          {isExpired ? `${Math.abs(daysLeft)}d ago` : `${daysLeft}d`}
                        </span>
                      )}
                    </td>
                    <td className="px-4 py-3">
                      <span className={`inline-flex rounded-full px-2.5 py-0.5 text-xs font-medium ${statusColor(event.event_status)}`}>
                        {event.event_status}
                      </span>
                    </td>
                  </tr>
                )
              })
            )}
          </tbody>
        </table>
      </div>
    </div>
  )
}