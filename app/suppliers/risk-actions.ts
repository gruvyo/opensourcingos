'use server'

import { revalidatePath } from 'next/cache'
import { z } from 'zod'
import { requireWorkspace } from '@/lib/authz'

export type RiskActionState = { status: 'idle' | 'success' | 'error'; message: string }

const optionalDate = z.union([z.literal(''), z.iso.date('Enter a valid target date.')])
const optionalUrl = z.union([z.literal(''), z.url('Enter a valid evidence link.').refine(value => /^https?:\/\//.test(value), 'Evidence links must use http or https.')])
const riskSchema = z.object({
  riskTitle: z.string().trim().min(2, 'Risk title is required.').max(200),
  identifiedOn: z.iso.date('Enter a valid identification date.'),
  severity: z.enum(['Low', 'Medium', 'High', 'Critical']),
  riskStatus: z.enum(['Open', 'Monitoring', 'Resolved']),
  description: z.string().trim().min(1, 'Add a risk description.').max(10000),
  targetResolutionDate: optionalDate,
  evidenceUrl: optionalUrl,
}).refine(value => !value.targetResolutionDate || value.targetResolutionDate >= value.identifiedOn, {
  message: 'Target resolution date cannot be before the identification date.',
  path: ['targetResolutionDate'],
})

function parseRisk(formData: FormData) {
  return riskSchema.safeParse({
    riskTitle: formData.get('riskTitle'),
    identifiedOn: formData.get('identifiedOn'),
    severity: formData.get('severity'),
    riskStatus: formData.get('riskStatus'),
    description: formData.get('description'),
    targetResolutionDate: formData.get('targetResolutionDate') || '',
    evidenceUrl: formData.get('evidenceUrl') || '',
  })
}

export async function saveSupplierRisk(supplierId: string, riskId: string | null, _previous: RiskActionState, formData: FormData): Promise<RiskActionState> {
  try {
    const supplier = z.string().uuid().parse(supplierId)
    const risk = riskId ? z.string().uuid().parse(riskId) : null
    const parsed = parseRisk(formData)
    if (!parsed.success) return { status: 'error', message: parsed.error.issues[0]?.message || 'Check the risk details.' }
    const { supabase, profile } = await requireWorkspace(['admin', 'procurement_user'])
    const { data: supplierRow, error: supplierError } = await supabase.from('suppliers').select('id').eq('id', supplier).eq('organization_id', profile.organization_id).maybeSingle()
    if (supplierError || !supplierRow) return { status: 'error', message: 'Supplier not found or you do not have access.' }

    const value = parsed.data
    const payload = {
      organization_id: profile.organization_id,
      supplier_id: supplier,
      risk_title: value.riskTitle,
      identified_on: value.identifiedOn,
      severity: value.severity,
      risk_status: value.riskStatus,
      description: value.description,
      target_resolution_date: value.targetResolutionDate || null,
      evidence_url: value.evidenceUrl || null,
      updated_by: profile.id,
    }
    const result = risk
      ? await supabase.from('supplier_risks').update(payload).eq('id', risk).eq('supplier_id', supplier).eq('organization_id', profile.organization_id).select('id').maybeSingle()
      : await supabase.from('supplier_risks').insert({ ...payload, created_by: profile.id }).select('id').maybeSingle()
    if (result.error) return { status: 'error', message: result.error.message }
    if (!result.data) return { status: 'error', message: 'Risk not found or you do not have access.' }
    revalidatePath(`/suppliers/${supplier}`)
    return { status: 'success', message: risk ? 'Risk saved.' : 'Risk added.' }
  } catch (error) {
    return { status: 'error', message: error instanceof Error ? error.message : 'Risk could not be saved.' }
  }
}

export async function deleteSupplierRisk(supplierId: string, riskId: string): Promise<RiskActionState> {
  try {
    const supplier = z.string().uuid().parse(supplierId)
    const risk = z.string().uuid().parse(riskId)
    const { supabase, profile } = await requireWorkspace(['admin', 'procurement_user'])
    const { data, error } = await supabase.from('supplier_risks').delete().eq('id', risk).eq('supplier_id', supplier).eq('organization_id', profile.organization_id).select('id').maybeSingle()
    if (error) return { status: 'error', message: error.message }
    if (!data) return { status: 'error', message: 'Risk not found or you do not have access.' }
    revalidatePath(`/suppliers/${supplier}`)
    return { status: 'success', message: 'Risk deleted.' }
  } catch (error) {
    return { status: 'error', message: error instanceof Error ? error.message : 'Risk could not be deleted.' }
  }
}
