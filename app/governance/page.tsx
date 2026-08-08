import Link from 'next/link'
import { redirect } from 'next/navigation'
import { History, ShieldCheck, UserRoundCheck, UsersRound } from 'lucide-react'
import {
  AUDIT_ACTION_FILTERS,
  AUDIT_ENTITY_FILTERS,
  auditActionLabel,
  auditChanges,
  auditEntityLabel,
  auditSubject,
  formatAuditTimestamp,
  type AuditAction,
  type AuditEntityType,
} from '@/lib/audit-display'
import type { Database } from '@/lib/database.types'
import { requireWorkspace, type WorkspaceRole } from '@/lib/authz'
import { Badge, type BadgeTone } from '@/components/ui/badge'
import { Card } from '@/components/ui/card'
import { PageHeader } from '@/components/ui/page-header'

const PAGE_SIZE = 50

type PageProps = {
  searchParams: Promise<Record<string, string | string[] | undefined>>
}

type AuditRow = Database['public']['Tables']['audit_log']['Row']
type MemberRow = Pick<Database['public']['Tables']['profiles']['Row'], 'id' | 'email' | 'full_name' | 'role'>

const roleLabels: Record<WorkspaceRole, string> = {
  admin: 'Administrator',
  procurement_user: 'Procurement user',
  viewer: 'Viewer',
}

function firstValue(value: string | string[] | undefined) {
  return Array.isArray(value) ? value[0] : value
}

function pageUrl(page: number, entity?: string, action?: string) {
  const params = new URLSearchParams()
  if (entity) params.set('entity', entity)
  if (action) params.set('action', action)
  if (page > 1) params.set('page', String(page))
  const query = params.toString()
  return query ? `/governance?${query}` : '/governance'
}

function actionTone(action: string): BadgeTone {
  if (action === 'insert') return 'success'
  if (action === 'delete') return 'danger'
  return 'info'
}

function roleTone(role: string | null): BadgeTone {
  if (role === 'admin') return 'brand'
  if (role === 'procurement_user') return 'info'
  return 'neutral'
}

export default async function GovernancePage({ searchParams }: PageProps) {
  const requested = await searchParams
  const rawPage = Number.parseInt(firstValue(requested.page) || '1', 10)
  const page = Number.isFinite(rawPage) && rawPage > 0 ? rawPage : 1
  const rawEntity = firstValue(requested.entity)
  const rawAction = firstValue(requested.action)
  const entity = AUDIT_ENTITY_FILTERS.includes(rawEntity as AuditEntityType) ? rawEntity as AuditEntityType : undefined
  const action = AUDIT_ACTION_FILTERS.includes(rawAction as AuditAction) ? rawAction as AuditAction : undefined

  const { supabase, profile } = await requireWorkspace()
  let auditQuery = supabase
    .from('audit_log')
    .select('*', { count: 'exact' })
    .eq('organization_id', profile.organization_id)
    .order('created_at', { ascending: false })
    .order('id', { ascending: false })
    .range((page - 1) * PAGE_SIZE, page * PAGE_SIZE - 1)

  if (entity) auditQuery = auditQuery.eq('entity_type', entity)
  if (action) auditQuery = auditQuery.eq('action', action)

  const [membersResult, organizationResult, settingsResult, auditResult] = await Promise.all([
    supabase
      .from('profiles')
      .select('id, email, full_name, role')
      .eq('organization_id', profile.organization_id)
      .order('full_name', { ascending: true, nullsFirst: false })
      .order('email', { ascending: true, nullsFirst: false }),
    supabase.from('organizations').select('name').eq('id', profile.organization_id).maybeSingle(),
    supabase.from('organization_settings').select('timezone').eq('organization_id', profile.organization_id).maybeSingle(),
    auditQuery,
  ])

  const totalAuditRows = auditResult.count || 0
  const totalPages = Math.max(1, Math.ceil(totalAuditRows / PAGE_SIZE))
  if (page > totalPages) redirect(pageUrl(totalPages, entity, action))

  const members = (membersResult.data || []) as MemberRow[]
  const auditRows = (auditResult.data || []) as AuditRow[]
  const memberById = new Map(members.map(member => [member.id, member]))
  const timezone = settingsResult.data?.timezone || 'America/Chicago'
  const loadError = membersResult.error?.message || organizationResult.error?.message
    || settingsResult.error?.message || auditResult.error?.message || null
  const adminCount = members.filter(member => member.role === 'admin').length

  return (
    <div className="mx-auto w-full max-w-[1500px] p-4 sm:p-6 lg:p-8">
      <PageHeader
        eyebrow="Workspace administration"
        title="Governance"
        description="See who can access this workspace and review its recorded changes. This view is read only."
        actions={<Badge tone="neutral" className="px-3 py-1.5"><ShieldCheck className="h-3.5 w-3.5" aria-hidden="true" />Read only</Badge>}
      />

      {loadError ? (
        <div className="mt-6 rounded-xl bg-red-50 p-4 text-sm text-red-700 dark:bg-red-900/30 dark:text-red-300" role="alert">
          <strong>Governance information is incomplete.</strong> {loadError}
        </div>
      ) : null}

      <section aria-label="Governance summary" className="mt-6 grid gap-4 sm:grid-cols-3">
        {[
          { label: 'Workspace members', value: members.length, icon: UsersRound },
          { label: 'Administrators', value: adminCount, icon: UserRoundCheck },
          { label: entity || action ? 'Matching changes' : 'Recorded changes', value: totalAuditRows, icon: History },
        ].map(item => (
          <Card key={item.label} className="p-5">
            <item.icon className="h-5 w-5 text-[var(--brand-ink)]" aria-hidden="true" />
            <p className="mt-4 text-xs font-semibold uppercase tracking-wider text-[var(--text-3)]">{item.label}</p>
            <p className="mt-1 text-2xl font-bold text-[var(--text)]">{item.value.toLocaleString('en-US')}</p>
          </Card>
        ))}
      </section>

      <div className="mt-6 grid gap-6 xl:grid-cols-[360px_minmax(0,1fr)]">
        <section aria-labelledby="members-heading">
          <Card className="overflow-hidden">
            <div className="border-b border-[var(--border)] px-5 py-4">
              <h2 id="members-heading" className="text-sm font-semibold text-[var(--text)]">Workspace members</h2>
              <p className="mt-1 text-xs text-[var(--text-3)]">People with access to {organizationResult.data?.name || 'this workspace'}.</p>
            </div>
            {members.length ? (
              <ul className="divide-y divide-[var(--border)]">
                {members.map(member => {
                  const role = member.role && roleLabels[member.role as WorkspaceRole]
                    ? roleLabels[member.role as WorkspaceRole]
                    : 'Viewer'
                  return (
                    <li key={member.id} className="px-5 py-4">
                      <div className="flex items-start justify-between gap-3">
                        <div className="min-w-0">
                          <p className="truncate text-sm font-semibold text-[var(--text)]">{member.full_name || 'Workspace member'}</p>
                          <p className="mt-0.5 truncate text-xs text-[var(--text-3)]">{member.email || 'No email available'}</p>
                        </div>
                        <Badge tone={roleTone(member.role)} className="shrink-0">{role}</Badge>
                      </div>
                    </li>
                  )
                })}
              </ul>
            ) : <p className="p-5 text-sm text-[var(--text-2)]">No workspace members could be loaded.</p>}
          </Card>
        </section>

        <section aria-labelledby="history-heading">
          <Card className="overflow-hidden">
            <div className="border-b border-[var(--border)] px-5 py-4">
              <div className="flex flex-col gap-4 lg:flex-row lg:items-end lg:justify-between">
                <div>
                  <h2 id="history-heading" className="text-sm font-semibold text-[var(--text)]">Audit history</h2>
                  <p className="mt-1 text-xs text-[var(--text-3)]">Who changed what and when, shown in {timezone}.</p>
                </div>
                <form method="get" className="grid gap-2 sm:grid-cols-[minmax(150px,1fr)_minmax(120px,1fr)_auto]" aria-label="Filter audit history">
                  <label className="sr-only" htmlFor="entity">Record type</label>
                  <select id="entity" name="entity" defaultValue={entity || ''} className="rounded-lg border border-[var(--border)] bg-[var(--surface)] px-3 py-2 text-xs text-[var(--text)]">
                    <option value="">All record types</option>
                    {AUDIT_ENTITY_FILTERS.map(value => <option key={value} value={value}>{auditEntityLabel(value)}</option>)}
                  </select>
                  <label className="sr-only" htmlFor="action">Action</label>
                  <select id="action" name="action" defaultValue={action || ''} className="rounded-lg border border-[var(--border)] bg-[var(--surface)] px-3 py-2 text-xs text-[var(--text)]">
                    <option value="">All actions</option>
                    {AUDIT_ACTION_FILTERS.map(value => <option key={value} value={value}>{auditActionLabel(value)}</option>)}
                  </select>
                  <button type="submit" className="rounded-lg bg-[var(--brand)] px-3 py-2 text-xs font-semibold text-[var(--on-brand)] hover:bg-[var(--brand-hover)]">Apply</button>
                </form>
              </div>
              {(entity || action) ? <Link href="/governance" className="mt-3 inline-block text-xs font-medium text-[var(--brand-ink)] hover:underline">Clear filters</Link> : null}
            </div>

            {auditRows.length ? (
              <ol className="divide-y divide-[var(--border)]">
                {auditRows.map(row => {
                  const actor = row.actor_id ? memberById.get(row.actor_id) : null
                  const actorName = actor?.full_name || actor?.email || (row.actor_id ? 'Former workspace member' : 'System migration')
                  const subject = auditSubject(row.before_data, row.after_data)
                  const changes = auditChanges(row.before_data, row.after_data)
                  return (
                    <li key={row.id} className="px-5 py-4">
                      <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
                        <div className="min-w-0">
                          <div className="flex flex-wrap items-center gap-2">
                            <Badge tone={actionTone(row.action)}>{auditActionLabel(row.action, row.entity_type)}</Badge>
                            <span className="text-sm font-semibold text-[var(--text)]">{auditEntityLabel(row.entity_type)}</span>
                            {subject ? <span className="truncate text-sm text-[var(--text-2)]">· {subject}</span> : null}
                          </div>
                          <p className="mt-1 text-xs text-[var(--text-3)]">by {actorName}</p>
                          {changes.length ? (
                            <dl className="mt-3 grid gap-2 lg:grid-cols-2">
                              {changes.map(change => (
                                <div key={change.field} className="rounded-lg bg-[var(--surface-2)] px-3 py-2 text-xs">
                                  <dt className="font-semibold text-[var(--text-2)]">{change.label}</dt>
                                  <dd className="mt-1 text-[var(--text-3)]"><span className="line-through">{change.before}</span> <span aria-hidden="true">→</span> <span className="font-medium text-[var(--text)]">{change.after}</span></dd>
                                </div>
                              ))}
                            </dl>
                          ) : (
                            <p className="mt-2 text-xs text-[var(--text-3)]">{row.action === 'insert' ? 'Record created.' : row.action === 'delete' ? 'Record removed.' : 'Recorded administrative change.'}</p>
                          )}
                        </div>
                        <time dateTime={row.created_at} className="shrink-0 text-xs text-[var(--text-3)]">{formatAuditTimestamp(row.created_at, timezone)}</time>
                      </div>
                    </li>
                  )
                })}
              </ol>
            ) : <p className="p-6 text-sm text-[var(--text-2)]">No recorded changes match these filters.</p>}

            {totalPages > 1 ? (
              <nav aria-label="Audit history pages" className="flex items-center justify-between border-t border-[var(--border)] px-5 py-4">
                {page > 1 ? <Link href={pageUrl(page - 1, entity, action)} className="rounded-lg border border-[var(--border)] px-3 py-2 text-xs font-semibold text-[var(--text-2)] hover:bg-[var(--surface-2)]">Previous</Link> : <span />}
                <span className="text-xs text-[var(--text-3)]">Page {page} of {totalPages}</span>
                {page < totalPages ? <Link href={pageUrl(page + 1, entity, action)} className="rounded-lg border border-[var(--border)] px-3 py-2 text-xs font-semibold text-[var(--text-2)] hover:bg-[var(--surface-2)]">Next</Link> : <span />}
              </nav>
            ) : null}
          </Card>
        </section>
      </div>
    </div>
  )
}
