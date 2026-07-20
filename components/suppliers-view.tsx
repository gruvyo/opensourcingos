'use client'

import { useState, useMemo } from 'react'
import Link from 'next/link'
import { Search, Building2, LayoutGrid, List, Users } from 'lucide-react'
import { clsx } from 'clsx'

type Supplier = {
  id: string
  supplier_name: string
  created_at: string | null
  events_as_incumbent: any[]
  events_as_awarded: any[]
  event_count: number
}

export function SuppliersView({ suppliers }: { suppliers: Supplier[] }) {
  const [search, setSearch] = useState('')
  const [view, setView] = useState<'cards' | 'table'>('cards')

  const filtered = useMemo(() => {
    return suppliers.filter((s) =>
      s.supplier_name.toLowerCase().includes(search.toLowerCase())
    )
  }, [suppliers, search])

  return (
    <div className="mt-6">
      {/* Toolbar: search + view toggle */}
      <div className="mb-4 flex flex-wrap items-center gap-3">
        <div className="relative flex-1 min-w-[200px]">
          <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-gray-400" />
          <input
            type="text"
            placeholder="Search suppliers..."
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            className="w-full rounded-lg border border-gray-300 pl-10 pr-3 py-2 text-sm focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500 dark:border-gray-600 dark:bg-gray-800 dark:text-gray-100"
          />
        </div>
        <div className="flex rounded-lg border border-gray-300 dark:border-gray-600">
          <button
            onClick={() => setView('cards')}
            className={clsx(
              'flex items-center gap-1.5 rounded-l-lg px-3 py-2 text-sm font-medium transition-colors',
              view === 'cards'
                ? 'bg-indigo-50 text-indigo-700 dark:bg-indigo-900/30 dark:text-indigo-300'
                : 'text-gray-600 hover:bg-gray-50 dark:text-gray-400 dark:hover:bg-gray-700'
            )}
          >
            <LayoutGrid className="h-4 w-4" />
            Cards
          </button>
          <button
            onClick={() => setView('table')}
            className={clsx(
              'flex items-center gap-1.5 rounded-r-lg px-3 py-2 text-sm font-medium transition-colors',
              view === 'table'
                ? 'bg-indigo-50 text-indigo-700 dark:bg-indigo-900/30 dark:text-indigo-300'
                : 'text-gray-600 hover:bg-gray-50 dark:text-gray-400 dark:hover:bg-gray-700'
            )}
          >
            <List className="h-4 w-4" />
            Table
          </button>
        </div>
      </div>

      {filtered.length === 0 ? (
        <div className="rounded-lg border border-gray-200 bg-white p-12 text-center shadow-sm dark:border-gray-700 dark:bg-gray-800">
          <Users className="mx-auto mb-3 h-10 w-10 text-gray-300 dark:text-gray-600" />
          <h3 className="text-lg font-medium text-gray-900 dark:text-gray-100">No suppliers found</h3>
          <p className="mt-1 text-sm text-gray-500 dark:text-gray-400">
            Suppliers are added when you create a project and click "New" next to the supplier field.
          </p>
        </div>
      ) : view === 'cards' ? (
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
          {filtered.map((supplier) => (
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
      ) : (
        <div className="overflow-x-auto rounded-lg border border-gray-200 bg-white shadow-sm dark:border-gray-700 dark:bg-gray-800">
          <table className="w-full min-w-[600px]">
            <thead>
              <tr className="border-b border-gray-200 bg-gray-50 dark:border-gray-700 dark:bg-gray-900/50">
                <th className="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-gray-500 dark:text-gray-400">Supplier Name</th>
                <th className="px-4 py-3 text-right text-xs font-semibold uppercase tracking-wider text-gray-500 dark:text-gray-400">Projects</th>
                <th className="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-gray-500 dark:text-gray-400">Added</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-200 dark:divide-gray-700">
              {filtered.map((supplier) => (
                <tr key={supplier.id} className="hover:bg-gray-50 dark:hover:bg-gray-700/50">
                  <td className="px-4 py-3">
                    <div className="flex items-center gap-2">
                      <Building2 className="h-4 w-4 shrink-0 text-indigo-500" />
                      <span className="text-sm font-medium text-gray-900 dark:text-gray-100">{supplier.supplier_name}</span>
                    </div>
                  </td>
                  <td className="px-4 py-3 text-right text-sm text-gray-600 dark:text-gray-400">
                    {supplier.event_count}
                  </td>
                  <td className="px-4 py-3 text-sm text-gray-500 dark:text-gray-400">
                    {supplier.created_at ? new Date(supplier.created_at).toLocaleDateString('en-US', { year: 'numeric', month: 'short', day: 'numeric' }) : '—'}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      <p className="mt-4 text-sm text-gray-500 dark:text-gray-400">
        Showing {filtered.length} of {suppliers.length} suppliers
      </p>
    </div>
  )
}