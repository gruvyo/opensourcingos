'use server'

import { revalidatePath } from 'next/cache'
import { z } from 'zod'
import { requireWorkspace } from '@/lib/authz'

export type SettingsActionState = { status: 'idle' | 'success' | 'error'; message: string }

const settingsSchema = z.object({
  organizationName: z.string().trim().min(2, 'Organization name is required.').max(120),
  fullName: z.string().trim().min(2, 'Your name is required.').max(120),
  currencyCode: z.enum(['USD', 'CAD', 'EUR', 'GBP', 'AUD']),
  locale: z.enum(['en-US', 'en-CA', 'en-GB']),
  timezone: z.enum(['America/Chicago', 'America/New_York', 'America/Denver', 'America/Los_Angeles', 'UTC']),
  fiscalYearStartMonth: z.coerce.number().int().min(1).max(12),
  dateFormat: z.enum(['MMM D, YYYY', 'MM/DD/YYYY', 'DD/MM/YYYY', 'YYYY-MM-DD']),
  defaultRecognitionMethod: z.enum(['monthly', 'annual', 'one_time']),
  supportProjectsEnabled: z.boolean(),
  projectDescriptionsEnabled: z.boolean(),
  projectOwnersEnabled: z.boolean(),
  projectCostCentersEnabled: z.boolean(),
  projectCategoriesEnabled: z.boolean(),
  projectBusinessUnitsEnabled: z.boolean(),
  projectUpdatesEnabled: z.boolean(),
  requireBaseline: z.boolean(),
  hardReductionApprovalThreshold: z.union([z.literal(''), z.coerce.number().min(0)]),
})

export async function updateSettings(
  _previous: SettingsActionState,
  formData: FormData,
): Promise<SettingsActionState> {
  try {
    const { supabase } = await requireWorkspace(['admin'])
    const parsed = settingsSchema.safeParse({
      organizationName: formData.get('organizationName'),
      fullName: formData.get('fullName'),
      currencyCode: formData.get('currencyCode'),
      locale: formData.get('locale'),
      timezone: formData.get('timezone'),
      fiscalYearStartMonth: formData.get('fiscalYearStartMonth'),
      dateFormat: formData.get('dateFormat'),
      defaultRecognitionMethod: formData.get('defaultRecognitionMethod'),
      supportProjectsEnabled: formData.get('supportProjectsEnabled') === 'on',
      projectDescriptionsEnabled: formData.get('projectDescriptionsEnabled') === 'on',
      projectOwnersEnabled: formData.get('projectOwnersEnabled') === 'on',
      projectCostCentersEnabled: formData.get('projectCostCentersEnabled') === 'on',
      projectCategoriesEnabled: formData.get('projectCategoriesEnabled') === 'on',
      projectBusinessUnitsEnabled: formData.get('projectBusinessUnitsEnabled') === 'on',
      projectUpdatesEnabled: formData.get('projectUpdatesEnabled') === 'on',
      requireBaseline: formData.get('requireBaseline') === 'on',
      hardReductionApprovalThreshold: formData.get('hardReductionApprovalThreshold') || '',
    })

    if (!parsed.success) {
      return { status: 'error', message: parsed.error.issues[0]?.message || 'Check the highlighted settings.' }
    }

    const values = parsed.data
    const { error } = await supabase.rpc('update_workspace_settings_v7', {
      p_organization_name: values.organizationName,
      p_full_name: values.fullName,
      p_currency_code: values.currencyCode,
      p_locale: values.locale,
      p_timezone: values.timezone,
      p_fiscal_year_start_month: values.fiscalYearStartMonth,
      p_date_format: values.dateFormat,
      p_default_recognition_method: values.defaultRecognitionMethod,
      p_support_projects_enabled: values.supportProjectsEnabled,
      p_project_descriptions_enabled: values.projectDescriptionsEnabled,
      p_project_owners_enabled: values.projectOwnersEnabled,
      p_project_cost_centers_enabled: values.projectCostCentersEnabled,
      p_project_categories_enabled: values.projectCategoriesEnabled,
      p_project_business_units_enabled: values.projectBusinessUnitsEnabled,
      p_project_updates_enabled: values.projectUpdatesEnabled,
      p_require_baseline: values.requireBaseline,
      p_hard_reduction_approval_threshold: values.hardReductionApprovalThreshold === ''
        ? null
        : values.hardReductionApprovalThreshold,
    })

    if (error) return { status: 'error', message: error.message }

    revalidatePath('/settings')
    return { status: 'success', message: 'Workspace settings saved.' }
  } catch (error) {
    return { status: 'error', message: error instanceof Error ? error.message : 'Settings could not be saved.' }
  }
}
