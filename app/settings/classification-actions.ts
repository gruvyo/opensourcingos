'use server'

import { revalidatePath } from 'next/cache'
import { z } from 'zod'
import { requireWorkspace } from '@/lib/authz'

export type ClassificationKind =
  | 'event_type'
  | 'event_status'
  | 'owner'
  | 'category'
  | 'business_unit'
  | 'cost_center'

export type ClassificationActionState = {
  status: 'idle' | 'success' | 'error'
  message: string
}

type MutationResult = {
  data: { id: string } | null
  error: { code?: string; message: string } | null
}

const kindSchema = z.enum([
  'event_type',
  'event_status',
  'owner',
  'category',
  'business_unit',
  'cost_center',
])

const optionSchema = z.object({
  id: z.string().uuid().or(z.literal('')),
  kind: kindSchema,
  projectType: z.enum(['Sourcing', 'Support', '']).default(''),
  label: z.string().trim().min(1, 'Enter a choice name.').max(120),
})

const toggleSchema = z.object({
  id: z.string().uuid(),
  kind: kindSchema,
  active: z.enum(['true', 'false']),
})

function friendlyDatabaseError(error: { code?: string; message: string }) {
  if (error.code === '23505') return 'That choice already exists in this workspace.'
  return error.message
}

export async function saveClassificationOption(
  _previous: ClassificationActionState,
  formData: FormData,
): Promise<ClassificationActionState> {
  try {
    const { supabase, profile, user } = await requireWorkspace(['admin'])
    const parsed = optionSchema.safeParse({
      id: formData.get('id') || '',
      kind: formData.get('kind'),
      projectType: formData.get('projectType') || '',
      label: formData.get('label'),
    })
    if (!parsed.success) {
      return { status: 'error', message: parsed.error.issues[0]?.message || 'Check this choice.' }
    }

    const { id, kind, projectType, label } = parsed.data
    let result: MutationResult

    if (kind === 'event_type' || kind === 'event_status' || kind === 'owner') {
      if (kind !== 'owner' && !projectType) {
        return { status: 'error', message: 'Choose whether this applies to Sourcing or Support projects.' }
      }
      const payload = {
        organization_id: profile.organization_id,
        choice_type: kind,
        project_type: kind === 'owner' ? null : projectType || null,
        label,
        updated_by: user.id,
      }
      result = id
        ? await supabase.from('project_choice_options').update(payload).eq('id', id).eq('organization_id', profile.organization_id).select('id').maybeSingle()
        : await supabase.from('project_choice_options').insert({ ...payload, sort_order: 1000, created_by: user.id }).select('id').single()
    } else if (kind === 'category') {
      result = id
        ? await supabase.from('categories').update({ category_name: label }).eq('id', id).eq('organization_id', profile.organization_id).select('id').maybeSingle()
        : await supabase.from('categories').insert({ organization_id: profile.organization_id, category_name: label }).select('id').single()
    } else if (kind === 'business_unit') {
      result = id
        ? await supabase.from('business_units').update({ business_unit_name: label }).eq('id', id).eq('organization_id', profile.organization_id).select('id').maybeSingle()
        : await supabase.from('business_units').insert({ organization_id: profile.organization_id, business_unit_name: label }).select('id').single()
    } else {
      result = id
        ? await supabase.from('cost_centers').update({ cost_center_name: label }).eq('id', id).eq('organization_id', profile.organization_id).select('id').maybeSingle()
        : await supabase.from('cost_centers').insert({ organization_id: profile.organization_id, cost_center_name: label }).select('id').single()
    }

    if (result.error) return { status: 'error', message: friendlyDatabaseError(result.error) }
    if (!result.data) return { status: 'error', message: 'Choice not found or you do not have access.' }

    revalidatePath('/settings')
    revalidatePath('/events')
    return { status: 'success', message: id ? 'Choice renamed.' : 'Choice added.' }
  } catch (error) {
    return { status: 'error', message: error instanceof Error ? error.message : 'Choice could not be saved.' }
  }
}

export async function toggleClassificationOption(
  _previous: ClassificationActionState,
  formData: FormData,
): Promise<ClassificationActionState> {
  try {
    const { supabase, profile } = await requireWorkspace(['admin'])
    const parsed = toggleSchema.safeParse({
      id: formData.get('id'),
      kind: formData.get('kind'),
      active: formData.get('active'),
    })
    if (!parsed.success) return { status: 'error', message: 'This choice could not be identified.' }

    const { id, kind } = parsed.data
    const active = parsed.data.active === 'true'
    let result: MutationResult

    if (kind === 'event_type' || kind === 'event_status' || kind === 'owner') {
      result = await supabase.from('project_choice_options').update({ active_flag: active }).eq('id', id).eq('organization_id', profile.organization_id).select('id').maybeSingle()
    } else if (kind === 'category') {
      result = await supabase.from('categories').update({ active_flag: active }).eq('id', id).eq('organization_id', profile.organization_id).select('id').maybeSingle()
    } else if (kind === 'business_unit') {
      result = await supabase.from('business_units').update({ active_flag: active }).eq('id', id).eq('organization_id', profile.organization_id).select('id').maybeSingle()
    } else {
      result = await supabase.from('cost_centers').update({ active_flag: active }).eq('id', id).eq('organization_id', profile.organization_id).select('id').maybeSingle()
    }

    if (result.error) return { status: 'error', message: friendlyDatabaseError(result.error) }
    if (!result.data) return { status: 'error', message: 'Choice not found or you do not have access.' }

    revalidatePath('/settings')
    revalidatePath('/events')
    return { status: 'success', message: active ? 'Choice restored.' : 'Choice archived. Historical projects are unchanged.' }
  } catch (error) {
    return { status: 'error', message: error instanceof Error ? error.message : 'Choice could not be updated.' }
  }
}
