import Link from 'next/link'
import { ArrowLeft, Building2, CalendarDays, ExternalLink, History, Landmark, PiggyBank, TrendingUp } from 'lucide-react'
import { notFound } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { SupplierForm, type SupplierFormValues } from '@/components/supplier-form'
import { Badge, type BadgeTone } from '@/components/ui/badge'
import { Card } from '@/components/ui/card'
import { PageHeader } from '@/components/ui/page-header'
import { formatCurrency, formatDate, formatReduction } from '@/lib/utils'

type PageProps = { params: Promise<{ supplierId: string }> }
type EventRow = { id: string; event_name: string; event_status: string | null; project_type: string | null; awarded_supplier_id: string | null; event_start_date: string | null; contract_start_date: string | null }

function statusTone(status: string | null): BadgeTone {
  if (status === 'Closed' || status === 'Realized' || status === 'Finance Validated') return 'success'
  if (status === 'Cancelled' || status === 'Rejected') return 'danger'
  if (status === 'Hold') return 'warning'
  return 'info'
}

function sum(rows: Array<Record<string, unknown>>, key: string) {
  return rows.reduce((total, row) => total + (Number(row[key]) || 0), 0)
}

export default async function SupplierProfilePage({ params }: PageProps) {
  const { supplierId } = await params
  const supabase = await createClient()
  const { data: authData } = await supabase.auth.getUser()
  const { data: profile } = authData.user
    ? await supabase.from('profiles').select('organization_id, role').eq('id', authData.user.id).maybeSingle()
    : { data: null }

  const [{ data: supplier, error: supplierError }, { data: owners }, { data: currencySettings }] = await Promise.all([
    supabase.from('suppliers').select('*').eq('id', supplierId).maybeSingle(),
    profile?.organization_id ? supabase.from('profiles').select('id, full_name, email').eq('organization_id', profile.organization_id).order('full_name') : Promise.resolve({ data: [] }),
    profile?.organization_id ? supabase.from('organization_settings').select('currency_code, savings_realization_enabled').eq('organization_id', profile.organization_id).maybeSingle() : Promise.resolve({ data: null }),
  ])

  if (supplierError || !supplier) notFound()

  const { data: eventsData, error: eventsError } = await supabase
    .from('sourcing_events')
    .select('id, event_name, event_status, project_type, awarded_supplier_id, event_start_date, contract_start_date')
    .or(`incumbent_supplier_id.eq.${supplierId},awarded_supplier_id.eq.${supplierId}`)
    .order('created_at', { ascending: false })
  const events = (eventsData || []) as EventRow[]
  const eventIds = events.map(event => event.id)

  const [{ data: calculations, error: calculationsError }, { data: periods, error: periodsError }, { data: audit, error: auditError }] = await Promise.all([
    eventIds.length ? supabase.from('savings_calculations').select('id, event_id, calculation_name, calculation_status, gross_savings_amount, cost_reduction_amount, cost_avoidance_amount, created_at').in('event_id', eventIds).order('created_at', { ascending: false }) : Promise.resolve({ data: [], error: null }),
    eventIds.length && currencySettings?.savings_realization_enabled ? supabase.from('realization_periods').select('id, event_id, period_name, period_end_date, realized_savings, projected_savings, realization_status, finance_validated').in('event_id', eventIds).order('period_end_date', { ascending: false }) : Promise.resolve({ data: [], error: null }),
    supabase.from('audit_log').select('id, action, actor_id, before_data, after_data, created_at').eq('entity_type', 'supplier').eq('entity_id', supplierId).order('created_at', { ascending: false }).limit(20),
  ])

  const loadError = eventsError?.message || calculationsError?.message || periodsError?.message || auditError?.message
  const calculationRows = (calculations || []) as Array<Record<string, unknown>>
  const periodRows = (periods || []) as Array<Record<string, unknown>>
  const eventMap = new Map(events.map(event => [event.id, event.event_name]))
  const ownerMap = new Map((owners || []).map(owner => [owner.id, owner.full_name || owner.email || 'Workspace member']))
  const currency = currencySettings?.currency_code || 'USD'
  const savingsRealizationEnabled = currencySettings?.savings_realization_enabled ?? false
  const canEdit = profile?.role === 'admin' || profile?.role === 'procurement_user'
  const values: SupplierFormValues = {
    supplierName: supplier.supplier_name,
    supplierStatus: supplier.supplier_status || 'Active',
    riskRating: supplier.risk_rating || '',
    website: supplier.website || '',
    countryCode: supplier.country_code || '',
    relationshipOwnerId: supplier.relationship_owner_id || '',
    nextReviewDate: supplier.next_review_date || '',
    notes: supplier.notes || '',
    preferred: Boolean(supplier.preferred_flag),
    diverse: Boolean(supplier.diversity_flag),
  }

  return (
    <div className="mx-auto w-full max-w-[1500px] p-4 sm:p-6 lg:p-8">
      <Link href="/suppliers" className="mb-4 inline-flex items-center gap-2 text-sm font-medium text-[var(--text-2)] hover:text-[var(--text)]"><ArrowLeft className="h-4 w-4" aria-hidden="true" />Back to suppliers</Link>
      <PageHeader
        eyebrow="Supplier profile"
        title={supplier.supplier_name}
        description={`Relationship details, sourcing activity, award outcomes, savings${savingsRealizationEnabled ? ', realization' : ''}, and change history.`}
        actions={<div className="flex flex-wrap gap-2"><Badge tone={supplier.preferred_flag ? 'brand' : 'neutral'}>{supplier.preferred_flag ? 'Preferred' : 'Standard'}</Badge><Badge tone={supplier.risk_rating === 'High' ? 'danger' : supplier.risk_rating === 'Medium' ? 'warning' : 'success'}>{supplier.risk_rating || 'Unrated'} risk</Badge></div>}
      />

      {loadError ? <div className="mt-6 rounded-xl bg-red-50 p-4 text-sm text-red-700 dark:bg-red-900/30 dark:text-red-300" role="alert">Some supplier history could not be loaded: {loadError}</div> : null}

      <section aria-label="Supplier summary" className="mt-6 grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        {[
          { label: 'Linked projects', value: events.length, icon: Building2 },
          { label: 'Awards', value: events.filter(event => event.awarded_supplier_id === supplierId).length, icon: Landmark },
          { label: 'Negotiated savings', value: formatCurrency(sum(calculationRows, 'gross_savings_amount'), currency), icon: PiggyBank },
          ...(savingsRealizationEnabled ? [{ label: 'Realized savings', value: formatCurrency(sum(periodRows, 'realized_savings'), currency), icon: TrendingUp }] : []),
        ].map(item => <Card key={item.label} className="p-5"><item.icon className="h-5 w-5 text-[var(--brand-ink)]" aria-hidden="true" /><p className="mt-4 text-xs font-semibold uppercase tracking-wider text-[var(--text-3)]">{item.label}</p><p className="mt-1 text-xl font-bold text-[var(--text)]">{item.value}</p></Card>)}
      </section>

      <div className="mt-6 grid gap-6 xl:grid-cols-[minmax(0,1fr)_420px]">
        <div className="space-y-6">
          {savingsRealizationEnabled ? <Card className="overflow-hidden">
            <div className="border-b border-[var(--border)] px-5 py-4"><h2 className="text-sm font-semibold text-[var(--text)]">Projects & awards</h2></div>
            {events.length ? <div className="overflow-x-auto"><table className="w-full min-w-[700px] text-sm"><caption className="sr-only">Projects and award relationships for {supplier.supplier_name}</caption><thead><tr className="bg-[var(--surface-2)] text-left text-[11px] uppercase tracking-wider text-[var(--text-3)]"><th scope="col" className="px-5 py-3">Project</th><th scope="col" className="px-4 py-3">Status</th><th scope="col" className="px-4 py-3">Relationship</th><th scope="col" className="px-5 py-3">Started</th></tr></thead><tbody className="divide-y divide-[var(--border)]">{events.map(event => <tr key={event.id}><td className="px-5 py-3"><Link href={`/events/${event.id}`} className="font-medium text-[var(--brand-ink)] hover:underline">{event.event_name}</Link></td><td className="px-4 py-3"><Badge tone={statusTone(event.event_status)}>{event.event_status || 'Pipeline'}</Badge></td><td className="px-4 py-3">{event.awarded_supplier_id === supplierId ? <Badge tone="success">Awarded</Badge> : <span className="text-[var(--text-2)]">Incumbent</span>}</td><td className="px-5 py-3 text-[var(--text-3)]">{formatDate(event.event_start_date)}</td></tr>)}</tbody></table></div> : <p className="p-6 text-sm text-[var(--text-2)]">No sourcing projects are linked yet.</p>}
          </Card> : null}

          <Card className="overflow-hidden">
            <div className="border-b border-[var(--border)] px-5 py-4"><h2 className="text-sm font-semibold text-[var(--text)]">Savings history</h2></div>
            {calculationRows.length ? <div className="divide-y divide-[var(--border)]">{calculationRows.map(row => <div key={String(row.id)} className="grid gap-3 px-5 py-4 sm:grid-cols-[1fr_auto_auto]"><div><p className="font-medium text-[var(--text)]">{String(row.calculation_name)}</p><p className="mt-1 text-xs text-[var(--text-3)]">{eventMap.get(String(row.event_id)) || 'Project'} · {String(row.calculation_status)}</p></div><div className="sm:text-right"><p className="text-xs text-[var(--text-3)]">Cost reduction</p><p className="font-semibold text-[var(--text)]">{formatReduction(row.cost_reduction_amount as number | null, currency)}</p></div><div className="sm:text-right"><p className="text-xs text-[var(--text-3)]">Total</p><p className="font-semibold text-[var(--text)]">{formatCurrency(Number(row.gross_savings_amount), currency)}</p></div></div>)}</div> : <p className="p-6 text-sm text-[var(--text-2)]">No savings calculations are linked yet.</p>}
          </Card>

          <Card className="overflow-hidden">
            <div className="border-b border-[var(--border)] px-5 py-4"><h2 className="text-sm font-semibold text-[var(--text)]">Realization history</h2></div>
            {periodRows.length ? <div className="divide-y divide-[var(--border)]">{periodRows.map(row => <div key={String(row.id)} className="flex flex-col gap-2 px-5 py-4 sm:flex-row sm:items-center"><CalendarDays className="h-4 w-4 text-[var(--text-3)]" aria-hidden="true" /><div className="min-w-0 flex-1"><p className="font-medium text-[var(--text)]">{String(row.period_name)}</p><p className="text-xs text-[var(--text-3)]">{eventMap.get(String(row.event_id)) || 'Project'} · through {formatDate(String(row.period_end_date))}</p></div><Badge tone={row.finance_validated ? 'success' : 'neutral'}>{row.finance_validated ? 'Finance validated' : String(row.realization_status)}</Badge><p className="font-semibold text-[var(--text)] sm:w-28 sm:text-right">{formatCurrency(Number(row.realized_savings), currency)}</p></div>)}</div> : <p className="p-6 text-sm text-[var(--text-2)]">No realization periods are linked yet.</p>}
          </Card>
        </div>

        <aside className="space-y-6">
          <Card className="p-5"><div className="flex items-center justify-between gap-3"><h2 className="text-sm font-semibold text-[var(--text)]">Relationship profile</h2>{supplier.website ? <a href={supplier.website} target="_blank" rel="noreferrer" className="inline-flex items-center gap-1 text-xs font-medium text-[var(--brand-ink)] hover:underline">Website <ExternalLink className="h-3 w-3" aria-hidden="true" /></a> : null}</div><div className="mt-5">{canEdit ? <SupplierForm supplierId={supplierId} values={values} owners={(owners || []).map(owner => ({ id: owner.id, label: owner.full_name || owner.email || 'Workspace member' }))} /> : <dl className="space-y-3 text-sm"><div><dt className="text-[var(--text-3)]">Owner</dt><dd className="font-medium text-[var(--text)]">{ownerMap.get(supplier.relationship_owner_id) || 'Unassigned'}</dd></div><div><dt className="text-[var(--text-3)]">Next review</dt><dd className="font-medium text-[var(--text)]">{formatDate(supplier.next_review_date)}</dd></div><div><dt className="text-[var(--text-3)]">Notes</dt><dd className="mt-1 whitespace-pre-wrap text-[var(--text-2)]">{supplier.notes || '—'}</dd></div></dl>}</div></Card>

          <Card className="overflow-hidden"><div className="flex items-center gap-2 border-b border-[var(--border)] px-5 py-4"><History className="h-4 w-4 text-[var(--text-3)]" aria-hidden="true" /><h2 className="text-sm font-semibold text-[var(--text)]">Change history</h2></div>{(audit || []).length ? <div className="divide-y divide-[var(--border)]">{(audit || []).map(entry => <div key={entry.id} className="px-5 py-3 text-sm"><p className="font-medium capitalize text-[var(--text)]">Supplier {entry.action}d</p><p className="mt-1 text-xs text-[var(--text-3)]">{formatDate(entry.created_at)}{entry.actor_id ? ` · ${ownerMap.get(entry.actor_id) || 'Workspace member'}` : ''}</p></div>)}</div> : <p className="p-5 text-sm text-[var(--text-2)]">History begins with the next saved change.</p>}</Card>
        </aside>
      </div>
    </div>
  )
}
