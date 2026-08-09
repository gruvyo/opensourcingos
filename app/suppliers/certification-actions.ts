'use server'

import { revalidatePath } from 'next/cache'
import { z } from 'zod'
import { requireWorkspace } from '@/lib/authz'

export type CertificationActionState = { status: 'idle' | 'success' | 'error'; message: string }

const optionalDate = z.union([z.literal(''), z.iso.date('Enter a valid date.')])
const optionalUrl = z.union([z.literal(''), z.url('Enter a valid evidence link.').refine(value => /^https?:\/\//.test(value), 'Evidence links must use http or https.')])
const certificationSchema = z.object({
  certificationName: z.string().trim().min(2, 'Certification name is required.').max(200),
  issuer: z.string().trim().max(200),
  certificateNumber: z.string().trim().max(200),
  issuedOn: optionalDate,
  expiresOn: optionalDate,
  evidenceUrl: optionalUrl,
}).refine(value => !value.issuedOn || !value.expiresOn || value.expiresOn >= value.issuedOn, {
  message: 'Expiration date cannot be before the issue date.',
  path: ['expiresOn'],
})

function parseCertification(formData: FormData) {
  return certificationSchema.safeParse({
    certificationName: formData.get('certificationName'),
    issuer: formData.get('issuer') || '',
    certificateNumber: formData.get('certificateNumber') || '',
    issuedOn: formData.get('issuedOn') || '',
    expiresOn: formData.get('expiresOn') || '',
    evidenceUrl: formData.get('evidenceUrl') || '',
  })
}

export async function saveSupplierCertification(supplierId: string, certificationId: string | null, _previous: CertificationActionState, formData: FormData): Promise<CertificationActionState> {
  try {
    const supplier = z.string().uuid().parse(supplierId)
    const certification = certificationId ? z.string().uuid().parse(certificationId) : null
    const parsed = parseCertification(formData)
    if (!parsed.success) return { status: 'error', message: parsed.error.issues[0]?.message || 'Check the certification details.' }
    const { supabase, profile } = await requireWorkspace(['admin', 'procurement_user'])
    const { data: supplierRow, error: supplierError } = await supabase.from('suppliers').select('id').eq('id', supplier).eq('organization_id', profile.organization_id).maybeSingle()
    if (supplierError || !supplierRow) return { status: 'error', message: 'Supplier not found or you do not have access.' }

    const value = parsed.data
    const payload = {
      organization_id: profile.organization_id,
      supplier_id: supplier,
      certification_name: value.certificationName,
      issuer: value.issuer || null,
      certificate_number: value.certificateNumber || null,
      issued_on: value.issuedOn || null,
      expires_on: value.expiresOn || null,
      evidence_url: value.evidenceUrl || null,
      updated_by: profile.id,
    }
    const result = certification
      ? await supabase.from('supplier_certifications').update(payload).eq('id', certification).eq('supplier_id', supplier).eq('organization_id', profile.organization_id).select('id').maybeSingle()
      : await supabase.from('supplier_certifications').insert({ ...payload, created_by: profile.id }).select('id').maybeSingle()
    if (result.error) return { status: 'error', message: result.error.message }
    if (!result.data) return { status: 'error', message: 'Certification not found or you do not have access.' }
    revalidatePath(`/suppliers/${supplier}`)
    return { status: 'success', message: certification ? 'Certification saved.' : 'Certification added.' }
  } catch (error) {
    return { status: 'error', message: error instanceof Error ? error.message : 'Certification could not be saved.' }
  }
}

export async function deleteSupplierCertification(supplierId: string, certificationId: string): Promise<CertificationActionState> {
  try {
    const supplier = z.string().uuid().parse(supplierId)
    const certification = z.string().uuid().parse(certificationId)
    const { supabase, profile } = await requireWorkspace(['admin', 'procurement_user'])
    const { data, error } = await supabase.from('supplier_certifications').delete().eq('id', certification).eq('supplier_id', supplier).eq('organization_id', profile.organization_id).select('id').maybeSingle()
    if (error) return { status: 'error', message: error.message }
    if (!data) return { status: 'error', message: 'Certification not found or you do not have access.' }
    revalidatePath(`/suppliers/${supplier}`)
    return { status: 'success', message: 'Certification deleted.' }
  } catch (error) {
    return { status: 'error', message: error instanceof Error ? error.message : 'Certification could not be deleted.' }
  }
}
