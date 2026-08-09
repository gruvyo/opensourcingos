'use server'

import { revalidatePath } from 'next/cache'
import { z } from 'zod'
import { requireWorkspace } from '@/lib/authz'

export type SupplierNoteActionState = { status: 'idle' | 'success' | 'error'; message: string }

const noteSchema = z.object({
  occurredOn: z.iso.date('Enter a valid activity date.'),
  body: z.string().trim().min(1, 'Add a relationship note.').max(10000, 'Keep the note under 10,000 characters.'),
})

export async function addSupplierNote(
  supplierId: string,
  _previous: SupplierNoteActionState,
  formData: FormData,
): Promise<SupplierNoteActionState> {
  try {
    const supplier = z.string().uuid().parse(supplierId)
    const parsed = noteSchema.safeParse({
      occurredOn: formData.get('occurredOn'),
      body: formData.get('body'),
    })
    if (!parsed.success) {
      return { status: 'error', message: parsed.error.issues[0]?.message || 'Check the note.' }
    }

    const { supabase, profile } = await requireWorkspace(['admin', 'procurement_user'])
    const { data: supplierRow, error: supplierError } = await supabase
      .from('suppliers')
      .select('id')
      .eq('id', supplier)
      .eq('organization_id', profile.organization_id)
      .maybeSingle()
    if (supplierError || !supplierRow) {
      return { status: 'error', message: 'Supplier not found or you do not have access.' }
    }

    const { error } = await supabase.from('supplier_notes').insert({
      organization_id: profile.organization_id,
      supplier_id: supplier,
      occurred_on: parsed.data.occurredOn,
      body: parsed.data.body,
      created_by: profile.id,
    })
    if (error) return { status: 'error', message: error.message }

    revalidatePath(`/suppliers/${supplier}`)
    return { status: 'success', message: 'Relationship note added.' }
  } catch (error) {
    return { status: 'error', message: error instanceof Error ? error.message : 'The note could not be added.' }
  }
}
