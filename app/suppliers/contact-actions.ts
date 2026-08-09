'use server'

import { revalidatePath } from 'next/cache'
import { z } from 'zod'
import { requireWorkspace } from '@/lib/authz'

export type ContactActionState = { status: 'idle' | 'success' | 'error'; message: string }

const contactSchema = z.object({
  contactName: z.string().trim().min(2, 'Contact name is required.').max(160),
  jobTitle: z.string().trim().max(160),
  email: z.string().trim().max(320).refine(value => !value || z.email().safeParse(value).success, 'Enter a valid email address.'),
  phone: z.string().trim().max(50).refine(value => !value || value.length >= 3, 'Enter a valid phone number.'),
  isPrimary: z.boolean(),
})

function parseContact(formData: FormData) {
  return contactSchema.safeParse({
    contactName: formData.get('contactName'),
    jobTitle: formData.get('jobTitle') || '',
    email: formData.get('email') || '',
    phone: formData.get('phone') || '',
    isPrimary: formData.get('isPrimary') === 'on',
  })
}

export async function saveSupplierContact(
  supplierId: string,
  contactId: string | null,
  _previous: ContactActionState,
  formData: FormData,
): Promise<ContactActionState> {
  try {
    const supplier = z.string().uuid().parse(supplierId)
    const contact = contactId ? z.string().uuid().parse(contactId) : null
    const { supabase, profile } = await requireWorkspace(['admin', 'procurement_user'])
    const parsed = parseContact(formData)
    if (!parsed.success) {
      return { status: 'error', message: parsed.error.issues[0]?.message || 'Check the contact details.' }
    }

    const { data: supplierRow, error: supplierError } = await supabase
      .from('suppliers')
      .select('id')
      .eq('id', supplier)
      .eq('organization_id', profile.organization_id)
      .maybeSingle()
    if (supplierError || !supplierRow) {
      return { status: 'error', message: 'Supplier not found or you do not have access.' }
    }

    const values = parsed.data
    const payload = {
      organization_id: profile.organization_id,
      supplier_id: supplier,
      contact_name: values.contactName,
      job_title: values.jobTitle || null,
      email: values.email.toLowerCase() || null,
      phone: values.phone || null,
      is_primary: values.isPrimary,
      updated_by: profile.id,
    }

    const result = contact
      ? await supabase
        .from('supplier_contacts')
        .update(payload)
        .eq('id', contact)
        .eq('supplier_id', supplier)
        .eq('organization_id', profile.organization_id)
        .select('id')
        .maybeSingle()
      : await supabase
        .from('supplier_contacts')
        .insert({ ...payload, created_by: profile.id })
        .select('id')
        .maybeSingle()

    if (result.error) return { status: 'error', message: result.error.message }
    if (!result.data) return { status: 'error', message: 'Contact not found or you do not have access.' }

    revalidatePath(`/suppliers/${supplier}`)
    return { status: 'success', message: contact ? 'Contact saved.' : 'Contact added.' }
  } catch (error) {
    return { status: 'error', message: error instanceof Error ? error.message : 'Contact could not be saved.' }
  }
}

export async function deleteSupplierContact(
  supplierId: string,
  contactId: string,
): Promise<ContactActionState> {
  try {
    const supplier = z.string().uuid().parse(supplierId)
    const contact = z.string().uuid().parse(contactId)
    const { supabase, profile } = await requireWorkspace(['admin', 'procurement_user'])
    const { data, error } = await supabase
      .from('supplier_contacts')
      .delete()
      .eq('id', contact)
      .eq('supplier_id', supplier)
      .eq('organization_id', profile.organization_id)
      .select('id')
      .maybeSingle()

    if (error) return { status: 'error', message: error.message }
    if (!data) return { status: 'error', message: 'Contact not found or you do not have access.' }

    revalidatePath(`/suppliers/${supplier}`)
    return { status: 'success', message: 'Contact deleted.' }
  } catch (error) {
    return { status: 'error', message: error instanceof Error ? error.message : 'Contact could not be deleted.' }
  }
}
