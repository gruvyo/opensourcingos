'use client'

import { useState, useMemo } from 'react'
import { Search, Building2, LayoutGrid, List, Users } from 'lucide-react'
import { clsx } from 'clsx'
import { Card } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { Badge } from '@/components/ui/badge'
import { formatDate } from '@/lib/utils'

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
          <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-[var(--text-3)]" />
          <Input
            type="text"
            placeholder="Search suppliers..."
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            className="pl-10"
          />
        </div>
        <div className="flex overflow-hidden rounded-md border border-[var(--border-strong)]">
          <button
            onClick={() => setView('cards')}
            aria-pressed={view === 'cards'}
            className={clsx(
              'flex items-center gap-1.5 px-3 py-2 text-sm font-medium transition-colors',
              view === 'cards'
                ? 'bg-[var(--brand-soft)] text-[var(--brand-ink)]'
                : 'text-[var(--text-2)] hover:bg-[var(--surface-2)]'
            )}
          >
            <LayoutGrid className="h-4 w-4" />
            Cards
          </button>
          <button
            onClick={() => setView('table')}
            aria-pressed={view === 'table'}
            className={clsx(
              'flex items-center gap-1.5 border-l border-[var(--border-strong)] px-3 py-2 text-sm font-medium transition-colors',
              view === 'table'
                ? 'bg-[var(--brand-soft)] text-[var(--brand-ink)]'
                : 'text-[var(--text-2)] hover:bg-[var(--surface-2)]'
            )}
          >
            <List className="h-4 w-4" />
            Table
          </button>
        </div>
      </div>

      {filtered.length === 0 ? (
        <Card className="p-12 text-center">
          <Users className="mx-auto mb-3 h-10 w-10 text-[var(--text-3)]" />
          <h3 className="text-lg font-medium text-[var(--text)]">No suppliers found</h3>
          <p className="mt-1 text-sm text-[var(--text-2)]">
            Suppliers are added when you create a project and click &ldquo;New&rdquo; next to the supplier field.
          </p>
        </Card>
      ) : view === 'cards' ? (
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
          {filtered.map((supplier) => (
            <Card key={supplier.id} className="p-5">
              <div className="flex items-start gap-3">
                <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-lg bg-[var(--brand-soft)]">
                  <Building2 className="h-5 w-5 text-[var(--brand-ink)]" />
                </div>
                <div className="min-w-0 flex-1">
                  <h3 className="truncate text-sm font-semibold text-[var(--text)]">
                    {supplier.supplier_name}
                  </h3>
                  <p className="mt-1 text-xs text-[var(--text-3)]">
                    {supplier.event_count} project{supplier.event_count !== 1 ? 's' : ''}
                  </p>
                </div>
              </div>
            </Card>
          ))}
        </div>
      ) : (
        <Card className="overflow-x-auto">
          <table className="w-full min-w-[600px]">
            <thead>
              <tr className="border-b border-[var(--border)] bg-[var(--surface-2)]">
                <th className="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-[var(--text-3)]">Supplier Name</th>
                <th className="px-4 py-3 text-right text-xs font-semibold uppercase tracking-wider text-[var(--text-3)]">Projects</th>
                <th className="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-[var(--text-3)]">Added</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-[var(--border)]">
              {filtered.map((supplier) => (
                <tr key={supplier.id} className="hover:bg-[var(--surface-2)]">
                  <td className="px-4 py-3">
                    <div className="flex items-center gap-2">
                      <Building2 className="h-4 w-4 shrink-0 text-[var(--brand-ink)]" />
                      <span className="text-sm font-medium text-[var(--text)]">{supplier.supplier_name}</span>
                    </div>
                  </td>
                  <td className="px-4 py-3 text-right text-sm text-[var(--text-2)]">
                    {supplier.event_count}
                  </td>
                  <td className="px-4 py-3 text-sm text-[var(--text-3)]">
                    {supplier.created_at ? formatDate(supplier.created_at) : '—'}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </Card>
      )}

      <p className="mt-4 text-sm text-[var(--text-3)]">
        Showing {filtered.length} of {suppliers.length} suppliers
      </p>
    </div>
  )
}
