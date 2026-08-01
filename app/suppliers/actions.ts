'use server'

import { revalidatePath } from 'next/cache'
import { redirect } from 'next/navigation'
import { z } from 'zod'
import { requireWorkspace } from '@/lib/authz'

export type SupplierActionState = { status: 'idle' | 'success' | 'error'; message: string }

const optionalUrl = z.string().trim().refine(value => !value || /^https?:\/\//i.test(value), {
  message: 'Website must start with http:// or https://.',
})

const supplierSchema = z.object({
  supplierName: z.string().trim().min(2, 'Supplier name is required.').max(160),
  supplierStatus: z.enum(['Active', 'Inactive', 'Prospective', 'Blocked', 'Under Review']),
  riskRating: z.enum(['', 'Low', 'Medium', 'High']),
  website: optionalUrl,
  countryCode: z.string().trim().toUpperCase().refine(value => !value || /^[A-Z]{2}$/.test(value), {
    message: 'Country must be a two-letter code, such as US.',
  }),
  relationshipOwnerId: z.string().uuid().or(z.literal('')),
  nextReviewDate: z.string().refine(value => !value || /^\d{4}-\d{2}-\d{2}$/.test(value), 'Use a valid review date.'),
  notes: z.string().trim().max(4000),
  preferred: z.boolean(),
  diverse: z.boolean(),
})

function normalizeSupplierName(value: string) {
  return value.toLowerCase().replace(/[^a-z0-9]+/g, ' ').trim()
}

function parseSupplier(formData: FormData) {
  return supplierSchema.safeParse({
    supplierName: formData.get('supplierName'),
    supplierStatus: formData.get('supplierStatus'),
    riskRating: formData.get('riskRating') || '',
    website: formData.get('website') || '',
    countryCode: formData.get('countryCode') || '',
    relationshipOwnerId: formData.get('relationshipOwnerId') || '',
    nextReviewDate: formData.get('nextReviewDate') || '',
    notes: formData.get('notes') || '',
    preferred: formData.get('preferred') === 'on',
    diverse: formData.get('diverse') === 'on',
  })
}

function supplierPayload(values: z.infer<typeof supplierSchema>, organizationId: string) {
  return {
    organization_id: organizationId,
    supplier_name: values.supplierName,
    supplier_normalized_name: normalizeSupplierName(values.supplierName),
    supplier_status: values.supplierStatus,
    preferred_flag: values.preferred,
    diversity_flag: values.diverse,
    risk_rating: values.riskRating || null,
    website: values.website || null,
    country_code: values.countryCode || null,
    relationship_owner_id: values.relationshipOwnerId || null,
    next_review_date: values.nextReviewDate || null,
    notes: values.notes || null,
  }
}

export async function createSupplier(
  _previous: SupplierActionState,
  formData: FormData,
): Promise<SupplierActionState> {
  let supplierId: string | null = null
  try {
    const { supabase, profile } = await requireWorkspace(['admin', 'procurement_user'])
    const parsed = parseSupplier(formData)
    if (!parsed.success) return { status: 'error', message: parsed.error.issues[0]?.message || 'Check the supplier details.' }

    const { data, error } = await supabase
      .from('suppliers')
      .insert(supplierPayload(parsed.data, profile.organization_id))
      .select('id')
      .single()

    if (error) {
      const message = error.code === '23505' ? 'A supplier with this name already exists.' : error.message
      return { status: 'error', message }
    }
    supplierId = data.id
  } catch (error) {
    return { status: 'error', message: error instanceof Error ? error.message : 'Supplier could not be created.' }
  }

  revalidatePath('/suppliers')
  redirect(`/suppliers/${supplierId}`)
}

export async function updateSupplier(
  supplierId: string,
  _previous: SupplierActionState,
  formData: FormData,
): Promise<SupplierActionState> {
  try {
    const id = z.string().uuid().parse(supplierId)
    const { supabase, profile } = await requireWorkspace(['admin', 'procurement_user'])
    const parsed = parseSupplier(formData)
    if (!parsed.success) return { status: 'error', message: parsed.error.issues[0]?.message || 'Check the supplier details.' }

    const { data, error } = await supabase
      .from('suppliers')
      .update(supplierPayload(parsed.data, profile.organization_id))
      .eq('id', id)
      .eq('organization_id', profile.organization_id)
      .select('id')
      .maybeSingle()

    if (error) {
      const message = error.code === '23505' ? 'A supplier with this name already exists.' : error.message
      return { status: 'error', message }
    }
    if (!data) return { status: 'error', message: 'Supplier not found or you do not have access.' }

    revalidatePath('/suppliers')
    revalidatePath(`/suppliers/${id}`)
    return { status: 'success', message: 'Supplier profile saved.' }
  } catch (error) {
    return { status: 'error', message: error instanceof Error ? error.message : 'Supplier could not be saved.' }
  }
}
