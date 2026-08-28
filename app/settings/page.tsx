import { CircleUserRound, Database, KeyRound, ShieldCheck } from 'lucide-react'
import { createClient } from '@/lib/supabase/server'
import { SettingsForm } from '@/components/settings-form'
import { ClassificationManager, type ManagedClassificationOption } from '@/components/classification-manager'
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

  const [organizationResult, settingsResult, choicesResult, categoriesResult, businessUnitsResult, costCentersResult] = profile?.organization_id
    ? await Promise.all([
      supabase.from('organizations').select('id, name').eq('id', profile.organization_id).maybeSingle(),
      supabase.from('organization_settings').select('*').eq('organization_id', profile.organization_id).maybeSingle(),
      supabase.from('project_choice_options').select('id, choice_type, project_type, label, active_flag, is_terminal, requires_savings_disposition, sort_order').eq('organization_id', profile.organization_id).order('sort_order').order('label'),
      supabase.from('categories').select('id, category_name, active_flag').eq('organization_id', profile.organization_id).order('category_name'),
      supabase.from('business_units').select('id, business_unit_name, active_flag').eq('organization_id', profile.organization_id).order('business_unit_name'),
      supabase.from('cost_centers').select('id, cost_center_name, active_flag').eq('organization_id', profile.organization_id).order('cost_center_name'),
    ])
    : [
      { data: null, error: null }, { data: null, error: null }, { data: [], error: null },
      { data: [], error: null }, { data: [], error: null }, { data: [], error: null },
    ]

  const organization = organizationResult.data
  const settings = settingsResult.data
  const loadError = authError?.message || profileResult.error?.message || organizationResult.error?.message
    || settingsResult.error?.message || choicesResult.error?.message || categoriesResult.error?.message
    || businessUnitsResult.error?.message || costCentersResult.error?.message || null
  const canEdit = profile?.role === 'admin'

  const classificationOptions: ManagedClassificationOption[] = [
    ...(choicesResult.data || []).map(choice => ({
      id: choice.id,
      kind: choice.choice_type as ManagedClassificationOption['kind'],
      label: choice.label,
      active: choice.active_flag,
      isTerminal: choice.is_terminal,
      requiresSavingsDisposition: choice.requires_savings_disposition,
      projectType: choice.project_type as ManagedClassificationOption['projectType'],
      sortOrder: choice.sort_order,
    })),
    ...(categoriesResult.data || []).map(category => ({
      id: category.id, kind: 'category' as const, label: category.category_name, active: category.active_flag,
    })),
    ...(businessUnitsResult.data || []).map(unit => ({
      id: unit.id, kind: 'business_unit' as const, label: unit.business_unit_name, active: unit.active_flag,
    })),
    ...(costCentersResult.data || []).map(center => ({
      id: center.id, kind: 'cost_center' as const, label: center.cost_center_name, active: center.active_flag,
    })),
  ]

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
    projectCostCentersEnabled: settings?.project_cost_centers_enabled ?? true,
    projectCategoriesEnabled: settings?.project_categories_enabled ?? true,
    projectBusinessUnitsEnabled: settings?.project_business_units_enabled ?? true,
    projectUpdatesEnabled: settings?.project_updates_enabled ?? true,
    projectIncumbentSuppliersEnabled: settings?.project_incumbent_suppliers_enabled ?? true,
    savingsRealizationEnabled: settings?.savings_realization_enabled ?? false,
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
        <div className="space-y-6">
          <Card className="p-5 sm:p-6"><SettingsForm values={values} canEdit={canEdit} /></Card>
          <Card className="p-5 sm:p-6"><ClassificationManager options={classificationOptions} canEdit={canEdit} /></Card>
        </div>

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
