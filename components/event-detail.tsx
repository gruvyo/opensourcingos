'use client'

import { useState } from 'react'
import {
  FileText, BarChart2, Users, FileCheck,
  Calculator, CalendarRange, Clock, Pencil,
  Briefcase, LifeBuoy, MessageSquareText, Send,
} from 'lucide-react'
import { clsx } from 'clsx'
import { formatDate, statusColor } from '@/lib/utils'
import type { Tables } from '@/lib/database.types'
import { createClient } from '@/lib/supabase/client'
import { Card } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { ScopeLinesTab } from './scope-lines-tab'
import { BaselinesTab } from './baselines-tab'
import { OffersTab } from './offers-tab'
import { CalculationsTab } from './calculations-tab'
import { ScheduleTab } from './schedule-tab'
import { RealizationTab } from './realization-tab'
import { EditProjectModal } from './edit-project-modal'

type ToOneRelation<T> = T | T[] | null
type CategoryRelation = Pick<Tables<'categories'>, 'category_name'>
type BusinessUnitRelation = Pick<Tables<'business_units'>, 'business_unit_name'>
type CostCenterRelation = Pick<Tables<'cost_centers'>, 'cost_center_name'>
type SupplierRelation = Pick<Tables<'suppliers'>, 'supplier_name'>

function getFirst<T>(obj: ToOneRelation<T>): T | null {
  if (!obj) return null
  if (Array.isArray(obj)) return obj[0] || null
  return obj
}

type Event = {
  id: string
  organization_id: string
  event_name: string
  event_description: string | null
  event_type: string
  sourcing_method: string | null
  event_status: string
  event_start_date: string | null
  project_due_date: string | null
  event_close_date: string | null
  contract_start_date: string | null
  contract_end_date: string | null
  recognition_start_date: string | null
  recognition_end_date: string | null
  official_reporting_basis: string | null
  currency_code: string
  project_type: string | null
  buyer_name: string | null
  notes: string | null
  category: ToOneRelation<CategoryRelation>
  business_unit: ToOneRelation<BusinessUnitRelation>
  cost_center: ToOneRelation<CostCenterRelation>
  incumbent_supplier: ToOneRelation<SupplierRelation>
  awarded_supplier: ToOneRelation<SupplierRelation>
}

type ProjectUpdate = {
  id: string
  body: string
  created_at: string
  created_by: string | null
  author: { full_name: string | null; email: string | null } | { full_name: string | null; email: string | null }[] | null
}

type CurrentProfile = {
  id: string
  full_name: string | null
  email: string | null
}

const SOURCING_TABS = [
  { id: 'overview', label: 'Overview', icon: FileText },
  // Scope Lines hidden (2026-07-26): no savings figure reads scope-line data — it
  // supplies labels only, and quantities get re-typed on the baseline and the offer
  // anyway. Code kept; restore this entry to bring the tab back.
  { id: 'baselines', label: 'Baselines', icon: BarChart2 },
  { id: 'offers', label: 'Supplier Offers', icon: Users },
  // Awards tab retired (2026-07-27): marking an offer as the Final offer on the
  // Supplier Offers tab IS the award decision. The separate award record and its
  // two-step ceremony added no information the chain needs. AwardsTab code kept.
  { id: 'calculations', label: 'Calculations', icon: Calculator },
  { id: 'schedule', label: 'Schedule', icon: CalendarRange },
  // Realization tab hidden per product decision (2026-07-26): realized savings are
  // assumed = projected, so realization tracking adds no signal. Code kept (import +
  // render below) so it can be re-enabled by restoring this entry.
  { id: 'updates', label: 'Updates', icon: MessageSquareText },
]

const SUPPORT_TABS = [
  { id: 'overview', label: 'Overview', icon: FileText },
  { id: 'updates', label: 'Updates', icon: MessageSquareText },
]

export function EventDetail({
  event,
  scopeLines,
  suppliers,
  categories,
  businessUnits,
  costCenters,
  updates,
  currentProfile,
}: {
  event: Event
  scopeLines: any[]
  suppliers: any[]
  categories: any[]
  businessUnits: any[]
  costCenters: any[]
  updates: ProjectUpdate[]
  currentProfile: CurrentProfile
}) {
  const [activeTab, setActiveTab] = useState('overview')
  const [showEditModal, setShowEditModal] = useState(false)

  const isSupport = event.project_type === 'Support'
  const TABS = isSupport ? SUPPORT_TABS : SOURCING_TABS

  return (
    <div>
      <div className="mb-6">
        <div className="flex items-start justify-between gap-4">
          <div>
            <div className="flex items-center gap-3">
              <h1 className="text-2xl font-bold text-[var(--text)]">{event.event_name}</h1>
              <span className={clsx(
                'inline-flex items-center gap-1 rounded-full px-2.5 py-0.5 text-xs font-medium',
                isSupport
                  ? 'bg-orange-100 text-orange-700 dark:bg-orange-500/15 dark:text-orange-300'
                  : 'bg-indigo-100 text-indigo-700 dark:bg-indigo-500/15 dark:text-indigo-300'
              )}>
                {isSupport ? <LifeBuoy className="h-3 w-3" /> : <Briefcase className="h-3 w-3" />}
                {isSupport ? 'Support' : 'Sourcing'}
              </span>
            </div>
            <p className="mt-1 text-sm text-[var(--text-2)]">
              {event.event_type || '—'}
            </p>
          </div>
          <span className={clsx('inline-flex shrink-0 rounded-full px-3 py-1 text-sm font-medium', statusColor(event.event_status))}>
            {event.event_status}
          </span>
          <Button variant="secondary" size="sm" onClick={() => setShowEditModal(true)}>
            <Pencil className="h-3.5 w-3.5" />
            Edit
          </Button>
        </div>
        {event.event_description && (
          <p className="mt-3 text-sm text-[var(--text-2)]">{event.event_description}</p>
        )}
      </div>

      <div className="border-b border-[var(--border)]">
        <nav className="flex gap-1 overflow-x-auto">
          {TABS.map((tab) => {
            const Icon = tab.icon
            return (
              <button key={tab.id} onClick={() => setActiveTab(tab.id)}
                className={clsx(
                  'flex items-center gap-2 border-b-2 px-4 py-3 text-sm font-medium transition-colors whitespace-nowrap',
                  activeTab === tab.id
                    ? 'border-[var(--brand)] text-[var(--brand-ink)]'
                    : 'border-transparent text-[var(--text-3)] hover:text-[var(--text)]'
                )}>
                <Icon className="h-4 w-4" />
                {tab.label}
              </button>
            )
          })}
        </nav>
      </div>

      <div className="mt-6">
        {activeTab === 'overview' && <OverviewTab event={event} />}
        {activeTab === 'updates' && (
          <ProjectUpdatesTab
            eventId={event.id}
            organizationId={event.organization_id}
            initialUpdates={updates}
            currentProfile={currentProfile}
          />
        )}
        {!isSupport && activeTab === 'scope' && <ScopeLinesTab eventId={event.id} scopeLines={scopeLines} />}
        {!isSupport && activeTab === 'baselines' && <BaselinesTab eventId={event.id} scopeLines={scopeLines} />}
        {!isSupport && activeTab === 'offers' && <OffersTab eventId={event.id} scopeLines={scopeLines} suppliers={suppliers} />}
        {!isSupport && activeTab === 'awards' && <AwardsTab />}
        {!isSupport && activeTab === 'calculations' && <CalculationsTab eventId={event.id} />}
        {!isSupport && activeTab === 'schedule' && <ScheduleTab eventId={event.id} />}
        {!isSupport && activeTab === 'realization' && <RealizationTab eventId={event.id} />}

      </div>

      {showEditModal && (
        <EditProjectModal
          project={event}
          categories={categories}
          businessUnits={businessUnits}
          costCenters={costCenters}
          suppliers={suppliers}
          onClose={() => setShowEditModal(false)}
          onSaved={() => { setShowEditModal(false); window.location.reload(); }}
        />
      )}
    </div>
  )
}

function OverviewTab({ event }: { event: Event }) {
  const isSupport = event.project_type === 'Support'

  const details = [
    { label: 'Project Type', value: isSupport ? 'Support / Non-Commercial' : 'Sourcing' },
    { label: 'Owner / Buyer', value: event.buyer_name },
    { label: 'Category', value: getFirst(event.category)?.category_name },
    { label: 'Business Unit', value: getFirst(event.business_unit)?.business_unit_name },
    { label: 'Cost Center', value: getFirst(event.cost_center)?.cost_center_name },
    { label: 'Incumbent Supplier', value: getFirst(event.incumbent_supplier)?.supplier_name },
  ].filter(Boolean) as { label: string; value: any }[]

  const dates = [
    { label: isSupport ? 'Start Date' : 'Project Start', value: event.event_start_date },
    { label: 'Project Due', value: event.project_due_date },
    { label: 'Completion Date', value: event.event_close_date },
    // The contract start seeds "Savings start" on the Calculations tab, which
    // seeds the savings schedule. It drove three downstream defaults while
    // being invisible on this page.
    ...(isSupport ? [] : [
      { label: 'Contract Start', value: event.contract_start_date },
      { label: 'Contract End', value: event.contract_end_date },
    ]),
  ] as { label: string; value: string | null }[]

  return (
    <div className="grid grid-cols-1 gap-6 md:grid-cols-2">
      <Card className="p-6">
        <h3 className="mb-4 text-sm font-semibold uppercase tracking-wider text-[var(--text-3)]">Project Details</h3>
        <dl className="space-y-3">
          {details.map((d) => (
            <div key={d.label} className="flex justify-between">
              <dt className="text-sm text-[var(--text-2)]">{d.label}</dt>
              <dd className="text-sm font-medium text-[var(--text)]">{d.value || '—'}</dd>
            </div>
          ))}
        </dl>
      </Card>
      <Card className="p-6">
        <h3 className="mb-4 text-sm font-semibold uppercase tracking-wider text-[var(--text-3)]">Key Dates</h3>
        <dl className="space-y-3">
          {dates.map((d) => (
            <div key={d.label} className="flex justify-between">
              <dt className="flex items-center gap-2 text-sm text-[var(--text-2)]">
                <Clock className="h-3 w-3" />
                {d.label}
              </dt>
              <dd className="text-sm font-medium text-[var(--text)]">{formatDate(d.value)}</dd>
            </div>
          ))}
        </dl>
      </Card>
    </div>
  )
}

function ProjectUpdatesTab({
  eventId,
  organizationId,
  initialUpdates,
  currentProfile,
}: {
  eventId: string
  organizationId: string
  initialUpdates: ProjectUpdate[]
  currentProfile: CurrentProfile
}) {
  const supabase = createClient()
  const [updates, setUpdates] = useState(initialUpdates)
  const [body, setBody] = useState('')
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const addUpdate = async (event: React.FormEvent) => {
    event.preventDefault()
    const trimmedBody = body.trim()
    if (!trimmedBody || saving) return

    setSaving(true)
    setError(null)

    const { data, error: insertError } = await supabase
      .from('project_updates')
      .insert({
        organization_id: organizationId,
        event_id: eventId,
        body: trimmedBody,
        created_by: currentProfile.id,
      })
      .select('id, body, created_at, created_by')
      .single()

    if (insertError) {
      setError(insertError.message)
      setSaving(false)
      return
    }

    setUpdates(current => [{
      ...data,
      author: {
        full_name: currentProfile.full_name,
        email: currentProfile.email,
      },
    }, ...current])
    setBody('')
    setSaving(false)
  }

  return (
    <div className="space-y-4">
      <Card className="p-6">
        <form onSubmit={addUpdate}>
          <label htmlFor="project-update" className="text-sm font-semibold text-[var(--text)]">
            Add a project update
          </label>
          <p className="mt-1 text-xs text-[var(--text-3)]">
            Build a dated record of decisions, milestones, and next steps.
          </p>
          <textarea
            id="project-update"
            value={body}
            onChange={(event) => setBody(event.target.value)}
            maxLength={10000}
            rows={4}
            placeholder="What changed? Include the outcome and next step..."
            className="mt-4 block w-full rounded-md border border-[var(--border-strong)] bg-[var(--surface)] px-3 py-2 text-sm text-[var(--text)] placeholder:text-[var(--text-3)] focus:border-[var(--brand)] focus:outline-none focus:ring-2 focus:ring-[var(--brand)]/30"
          />
          {error && (
            <p className="mt-2 text-sm text-red-600 dark:text-red-400" role="alert">{error}</p>
          )}
          <div className="mt-3 flex items-center justify-between gap-4">
            <span className="text-xs text-[var(--text-3)]">{body.length.toLocaleString()} / 10,000</span>
            <Button type="submit" size="sm" disabled={saving || !body.trim()}>
              <Send className="h-3.5 w-3.5" />
              {saving ? 'Adding...' : 'Add Update'}
            </Button>
          </div>
        </form>
      </Card>

      <div className="space-y-3">
        {updates.length === 0 ? (
          <Card className="p-8 text-center">
            <MessageSquareText className="mx-auto mb-3 h-8 w-8 text-[var(--text-3)]" />
            <p className="text-sm font-medium text-[var(--text)]">No updates yet</p>
            <p className="mt-1 text-sm text-[var(--text-3)]">Add the first update to start this project&apos;s history.</p>
          </Card>
        ) : updates.map(update => {
          const author = getFirst(update.author)
          const authorName = author?.full_name || author?.email || 'Workspace member'
          return (
            <Card key={update.id} className="p-5">
              <div className="flex items-start gap-3">
                <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-[var(--brand-soft)] text-sm font-semibold text-[var(--brand-ink)]">
                  {authorName.slice(0, 1).toUpperCase()}
                </div>
                <div className="min-w-0 flex-1">
                  <div className="flex flex-wrap items-baseline justify-between gap-x-4 gap-y-1">
                    <span className="text-sm font-semibold text-[var(--text)]">{authorName}</span>
                    <time className="text-xs text-[var(--text-3)]" dateTime={update.created_at}>
                      {new Intl.DateTimeFormat('en-US', {
                        month: 'short', day: 'numeric', year: 'numeric',
                        hour: 'numeric', minute: '2-digit',
                      }).format(new Date(update.created_at))}
                    </time>
                  </div>
                  <p className="mt-3 whitespace-pre-wrap break-words text-sm leading-6 text-[var(--text-2)]">{update.body}</p>
                </div>
              </div>
            </Card>
          )
        })}
      </div>
    </div>
  )
}

function AwardsTab() {
  return (
    <Card className="p-12 text-center">
      <FileCheck className="mx-auto mb-3 h-10 w-10 text-[var(--text-3)]" />
      <h3 className="text-lg font-medium text-[var(--text)]">Awards</h3>
      <p className="mt-1 text-sm text-[var(--text-3)]">
        Create awards from the Supplier Offers tab by expanding an offer and clicking &quot;Create Award from Offer.&quot;
      </p>
    </Card>
  )
}
