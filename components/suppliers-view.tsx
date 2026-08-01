'use client'

import { useMemo, useState } from 'react'
import {
  Building2,
  CircleAlert,
  LayoutGrid,
  List,
  Network,
  Search,
  ShieldCheck,
  Star,
  Users,
} from 'lucide-react'
import { clsx } from 'clsx'
import { Card } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { Badge, type BadgeTone } from '@/components/ui/badge'
import { formatDate } from '@/lib/utils'

export type SupplierSummary = {
  id: string
  name: string
  status: string
  preferred: boolean
  diverse: boolean
  risk: string | null
  incumbentProjects: number
  awardedProjects: number
  linkedProjects: number
  createdAt: string | null
}

type SupplierFilter = 'all' | 'preferred' | 'diverse' | 'attention'

const filters: { value: SupplierFilter; label: string }[] = [
  { value: 'all', label: 'All suppliers' },
  { value: 'preferred', label: 'Preferred' },
  { value: 'diverse', label: 'Diverse' },
  { value: 'attention', label: 'Needs attention' },
]

function statusTone(status: string): BadgeTone {
  if (status === 'Active') return 'success'
  if (status === 'Blocked') return 'danger'
  if (status === 'Under Review') return 'warning'
  if (status === 'Prospective') return 'info'
  return 'neutral'
}

function riskTone(risk: string | null): BadgeTone {
  if (risk === 'High') return 'danger'
  if (risk === 'Medium') return 'warning'
  if (risk === 'Low') return 'success'
  return 'neutral'
}

function needsAttention(supplier: SupplierSummary): boolean {
  return supplier.risk === 'High'
    || supplier.status === 'Blocked'
    || supplier.status === 'Under Review'
}

function PortfolioStat({
  label,
  value,
  note,
  icon: Icon,
}: {
  label: string
  value: number
  note: string
  icon: typeof Building2
}) {
  return (
    <Card className="p-5">
      <div className="flex items-start justify-between gap-3">
        <div>
          <p className="text-xs font-semibold uppercase tracking-[0.12em] text-[var(--text-3)]">{label}</p>
          <p className="mt-2 text-2xl font-bold tabular-nums text-[var(--text)]">{value}</p>
          <p className="mt-1 text-xs text-[var(--text-3)]">{note}</p>
        </div>
        <div className="grid h-10 w-10 place-items-center rounded-full bg-[var(--brand-soft)] text-[var(--brand-ink)]">
          <Icon className="h-5 w-5" aria-hidden="true" />
        </div>
      </div>
    </Card>
  )
}

export function SuppliersView({ suppliers }: { suppliers: SupplierSummary[] }) {
  const [search, setSearch] = useState('')
  const [filter, setFilter] = useState<SupplierFilter>('all')
  const [view, setView] = useState<'cards' | 'table'>('table')

  const summary = useMemo(() => ({
    preferred: suppliers.filter(supplier => supplier.preferred).length,
    diverse: suppliers.filter(supplier => supplier.diverse).length,
    attention: suppliers.filter(needsAttention).length,
    projects: suppliers.reduce((total, supplier) => total + supplier.linkedProjects, 0),
  }), [suppliers])

  const filtered = useMemo(() => {
    const query = search.trim().toLowerCase()
    return suppliers.filter(supplier => {
      const matchesSearch = !query || supplier.name.toLowerCase().includes(query)
      const matchesFilter = filter === 'all'
        || (filter === 'preferred' && supplier.preferred)
        || (filter === 'diverse' && supplier.diverse)
        || (filter === 'attention' && needsAttention(supplier))
      return matchesSearch && matchesFilter
    })
  }, [filter, search, suppliers])

  return (
    <div className="mt-6">
      <section aria-label="Supplier portfolio summary" className="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <PortfolioStat label="Supplier records" value={suppliers.length} note="Visible in this workspace" icon={Building2} />
        <PortfolioStat label="Preferred" value={summary.preferred} note="Approved strategic relationships" icon={Star} />
        <PortfolioStat label="Needs attention" value={summary.attention} note="High risk, blocked, or under review" icon={CircleAlert} />
        <PortfolioStat label="Project links" value={summary.projects} note={`${summary.diverse} diverse supplier${summary.diverse === 1 ? '' : 's'}`} icon={Network} />
      </section>

      <Card className="mt-6 overflow-hidden">
        <div className="border-b border-[var(--border)] p-4 sm:p-5">
          <div className="flex flex-col gap-3 xl:flex-row xl:items-center xl:justify-between">
            <div className="relative min-w-0 flex-1 xl:max-w-md">
              <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-[var(--text-3)]" aria-hidden="true" />
              <Input
                type="search"
                aria-label="Search suppliers"
                placeholder="Search supplier portfolio..."
                value={search}
                onChange={event => setSearch(event.target.value)}
                className="pl-10"
              />
            </div>

            <div className="flex flex-wrap items-center gap-2">
              <div className="flex flex-wrap gap-1" aria-label="Filter suppliers">
                {filters.map(option => (
                  <button
                    key={option.value}
                    type="button"
                    onClick={() => setFilter(option.value)}
                    aria-pressed={filter === option.value}
                    className={clsx(
                      'rounded-lg px-3 py-2 text-xs font-semibold transition-colors',
                      filter === option.value
                        ? 'bg-[var(--brand-soft)] text-[var(--brand-ink)]'
                        : 'text-[var(--text-2)] hover:bg-[var(--surface-2)] hover:text-[var(--text)]',
                    )}
                  >
                    {option.label}
                  </button>
                ))}
              </div>

              <div className="flex overflow-hidden rounded-lg border border-[var(--border-strong)]" aria-label="Supplier view">
                <button
                  type="button"
                  onClick={() => setView('table')}
                  aria-label="Table view"
                  aria-pressed={view === 'table'}
                  className={clsx(
                    'p-2 transition-colors',
                    view === 'table' ? 'bg-[var(--brand)] text-white' : 'text-[var(--text-2)] hover:bg-[var(--surface-2)]',
                  )}
                >
                  <List className="h-4 w-4" aria-hidden="true" />
                </button>
                <button
                  type="button"
                  onClick={() => setView('cards')}
                  aria-label="Card view"
                  aria-pressed={view === 'cards'}
                  className={clsx(
                    'border-l border-[var(--border-strong)] p-2 transition-colors',
                    view === 'cards' ? 'bg-[var(--brand)] text-white' : 'text-[var(--text-2)] hover:bg-[var(--surface-2)]',
                  )}
                >
                  <LayoutGrid className="h-4 w-4" aria-hidden="true" />
                </button>
              </div>
            </div>
          </div>
        </div>

        {filtered.length === 0 ? (
          <div className="p-12 text-center">
            <Users className="mx-auto mb-3 h-10 w-10 text-[var(--text-3)]" aria-hidden="true" />
            <h2 className="text-lg font-medium text-[var(--text)]">No suppliers match this view</h2>
            <p className="mt-1 text-sm text-[var(--text-2)]">Clear the search or choose another portfolio filter.</p>
          </div>
        ) : view === 'cards' ? (
          <div className="grid grid-cols-1 gap-4 p-4 sm:grid-cols-2 sm:p-5 xl:grid-cols-3">
            {filtered.map(supplier => (
              <article key={supplier.id} className="rounded-xl border border-[var(--border)] bg-[var(--surface)] p-5">
                <div className="flex items-start gap-3">
                  <div className="grid h-10 w-10 shrink-0 place-items-center rounded-lg bg-[var(--brand-soft)] text-[var(--brand-ink)]">
                    <Building2 className="h-5 w-5" aria-hidden="true" />
                  </div>
                  <div className="min-w-0 flex-1">
                    <h2 className="truncate text-sm font-semibold text-[var(--text)]">{supplier.name}</h2>
                    <div className="mt-2 flex flex-wrap gap-1.5">
                      <Badge tone={statusTone(supplier.status)}>{supplier.status}</Badge>
                      {supplier.preferred ? <Badge tone="brand"><Star className="h-3 w-3" /> Preferred</Badge> : null}
                      {supplier.diverse ? <Badge tone="info"><ShieldCheck className="h-3 w-3" /> Diverse</Badge> : null}
                    </div>
                  </div>
                </div>
                <dl className="mt-5 grid grid-cols-3 gap-3 border-t border-[var(--border)] pt-4 text-center">
                  <div><dt className="text-[10px] uppercase tracking-wide text-[var(--text-3)]">Projects</dt><dd className="mt-1 text-sm font-semibold text-[var(--text)]">{supplier.linkedProjects}</dd></div>
                  <div><dt className="text-[10px] uppercase tracking-wide text-[var(--text-3)]">Awards</dt><dd className="mt-1 text-sm font-semibold text-[var(--text)]">{supplier.awardedProjects}</dd></div>
                  <div><dt className="text-[10px] uppercase tracking-wide text-[var(--text-3)]">Risk</dt><dd className="mt-1"><Badge tone={riskTone(supplier.risk)}>{supplier.risk || 'Unrated'}</Badge></dd></div>
                </dl>
              </article>
            ))}
          </div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full min-w-[900px] text-sm">
              <caption className="sr-only">Supplier portfolio with status, risk, attributes, and project activity</caption>
              <thead>
                <tr className="bg-[var(--surface-2)] text-left text-[11px] font-semibold uppercase tracking-wider text-[var(--text-3)]">
                  <th scope="col" className="px-5 py-3 sm:px-6">Supplier</th>
                  <th scope="col" className="px-4 py-3">Status</th>
                  <th scope="col" className="px-4 py-3">Attributes</th>
                  <th scope="col" className="px-4 py-3">Risk</th>
                  <th scope="col" className="px-4 py-3 text-right">Projects</th>
                  <th scope="col" className="px-4 py-3 text-right">Awards</th>
                  <th scope="col" className="px-5 py-3 sm:px-6">Added</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-[var(--border)]">
                {filtered.map(supplier => (
                  <tr key={supplier.id} className="transition-colors hover:bg-[var(--surface-2)]">
                    <th scope="row" className="px-5 py-3 text-left font-medium text-[var(--text)] sm:px-6">
                      <span className="flex items-center gap-2"><Building2 className="h-4 w-4 text-[var(--brand-ink)]" aria-hidden="true" />{supplier.name}</span>
                    </th>
                    <td className="px-4 py-3"><Badge tone={statusTone(supplier.status)}>{supplier.status}</Badge></td>
                    <td className="px-4 py-3">
                      <span className="flex flex-wrap gap-1.5">
                        {supplier.preferred ? <Badge tone="brand">Preferred</Badge> : null}
                        {supplier.diverse ? <Badge tone="info">Diverse</Badge> : null}
                        {!supplier.preferred && !supplier.diverse ? <span className="text-[var(--text-3)]">—</span> : null}
                      </span>
                    </td>
                    <td className="px-4 py-3"><Badge tone={riskTone(supplier.risk)}>{supplier.risk || 'Unrated'}</Badge></td>
                    <td className="px-4 py-3 text-right tabular-nums text-[var(--text-2)]">{supplier.linkedProjects}</td>
                    <td className="px-4 py-3 text-right tabular-nums text-[var(--text-2)]">{supplier.awardedProjects}</td>
                    <td className="px-5 py-3 text-[var(--text-3)] sm:px-6">{formatDate(supplier.createdAt)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}

        <p className="border-t border-[var(--border)] px-5 py-3 text-xs text-[var(--text-3)] sm:px-6">
          Showing {filtered.length} of {suppliers.length} supplier records
        </p>
      </Card>
    </div>
  )
}
