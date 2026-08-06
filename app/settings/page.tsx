import { CircleUserRound, Database, KeyRound, ShieldCheck } from 'lucide-react'
import { createClient } from '@/lib/supabase/server'
import { SettingsForm } from '@/components/settings-form'
import { Badge } from '@/components/ui/badge'
import { Card } from '@/components/ui/card'
import { PageHeader } from '@/components/ui/page-header'

export default async function SettingsPage() {
  const supabase = await createClient()
  const { data: authData, error: authError } = await supabase.auth.getUser()
  const user = authData.user

  const profileResult = user
    ? await supabase.from('profiles').select('id, organization_id, email, full_name, role').eq('id', user.id).maybeSingle()
    : { data: null, error: null }
  const profile = profileResult.data

  const [organizationResult, settingsResult] = profile?.organization_id
    ? await Promise.all([
      supabase.from('organizations').select('id, name').eq('id', profile.organization_id).maybeSingle(),
      supabase.from('organization_settings').select('*').eq('organization_id', profile.organization_id).maybeSingle(),
    ])
    : [{ data: null, error: null }, { data: null, error: null }]

  const organization = organizationResult.data
  const settings = settingsResult.data
  const loadError = authError?.message || profileResult.error?.message || organizationResult.error?.message || settingsResult.error?.message || null
  const canEdit = profile?.role === 'admin'

  const values = {
    organizationName: organization?.name || '',
    fullName: profile?.full_name || user?.user_metadata?.full_name || '',
    currencyCode: settings?.currency_code || 'USD',
    locale: settings?.locale || 'en-US',
    timezone: settings?.timezone || 'America/Chicago',
    fiscalYearStartMonth: settings?.fiscal_year_start_month || 1,
    dateFormat: settings?.date_format || 'MMM D, YYYY',
    defaultRecognitionMethod: settings?.default_recognition_method || 'monthly',
    supportProjectsEnabled: settings?.support_projects_enabled ?? true,
    projectDescriptionsEnabled: settings?.project_descriptions_enabled ?? true,
    projectOwnersEnabled: settings?.project_owners_enabled ?? true,
    requireBaseline: settings?.require_baseline_for_hard_reduction ?? true,
    hardReductionApprovalThreshold: settings?.hard_reduction_approval_threshold ?? null,
  }

  return (
    <div className="mx-auto w-full max-w-[1400px] p-4 sm:p-6 lg:p-8">
      <PageHeader
        eyebrow="Workspace administration"
        title="Settings"
        description="Set the reporting defaults and methodology controls that govern this workspace."
        actions={<Badge tone={canEdit ? 'success' : 'neutral'} className="px-3 py-1.5">{canEdit ? 'Administrator' : 'Read only'}</Badge>}
      />

      {loadError ? <div className="mt-6 rounded-xl bg-red-50 p-4 text-sm text-red-700 dark:bg-red-900/30 dark:text-red-300" role="alert"><strong>Settings are incomplete.</strong> {loadError}</div> : null}

      <div className="mt-6 grid gap-6 xl:grid-cols-[minmax(0,1fr)_320px]">
        <Card className="p-5 sm:p-6"><SettingsForm values={values} canEdit={canEdit} /></Card>

        <aside className="space-y-4">
          <Card className="p-5">
            <div className="flex items-center gap-3"><CircleUserRound className="h-5 w-5 text-[var(--brand-ink)]" aria-hidden="true" /><div><p className="text-xs text-[var(--text-3)]">Signed in as</p><p className="text-sm font-semibold text-[var(--text)]">{user?.email || profile?.email || '—'}</p></div></div>
            <dl className="mt-4 space-y-3 border-t border-[var(--border)] pt-4 text-sm">
              <div className="flex justify-between gap-3"><dt className="text-[var(--text-3)]">Role</dt><dd className="font-medium text-[var(--text)]">{profile?.role || 'viewer'}</dd></div>
              <div className="flex justify-between gap-3"><dt className="text-[var(--text-3)]">Workspace</dt><dd className="max-w-[170px] truncate font-medium text-[var(--text)]">{organization?.name || '—'}</dd></div>
            </dl>
          </Card>

          <Card className="p-5">
            <h2 className="flex items-center gap-2 text-sm font-semibold text-[var(--text)]"><ShieldCheck className="h-4 w-4 text-[var(--success)]" aria-hidden="true" />Trust controls</h2>
            <ul className="mt-3 space-y-3 text-xs leading-5 text-[var(--text-2)]">
              <li>Workspace records are isolated with database-level security.</li>
              <li>Every settings and supplier change records who changed what and when.</li>
              <li>Cost increases stay negative; missing baselines remain not applicable.</li>
            </ul>
          </Card>

          <Card className="p-5">
            <h2 className="text-sm font-semibold text-[var(--text)]">Platform connections</h2>
            <div className="mt-4 space-y-3">
              <div className="flex items-center gap-3 text-sm"><KeyRound className="h-4 w-4 text-[var(--text-3)]" aria-hidden="true" /><span className="text-[var(--text-2)]">Google identity</span><Badge tone="success" className="ml-auto">Connected</Badge></div>
              <div className="flex items-center gap-3 text-sm"><Database className="h-4 w-4 text-[var(--text-3)]" aria-hidden="true" /><span className="text-[var(--text-2)]">Supabase data</span><Badge tone="success" className="ml-auto">Protected</Badge></div>
            </div>
          </Card>
        </aside>
      </div>
    </div>
  )
}
