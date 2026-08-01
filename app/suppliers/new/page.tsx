import Link from 'next/link'
import { ArrowLeft } from 'lucide-react'
import { createClient } from '@/lib/supabase/server'
import { SupplierForm, type SupplierFormValues } from '@/components/supplier-form'
import { Card } from '@/components/ui/card'
import { PageHeader } from '@/components/ui/page-header'

const emptySupplier: SupplierFormValues = {
  supplierName: '', supplierStatus: 'Prospective', riskRating: '', website: '', countryCode: '',
  relationshipOwnerId: '', nextReviewDate: '', notes: '', preferred: false, diverse: false,
}

export default async function NewSupplierPage() {
  const supabase = await createClient()
  const { data: authData } = await supabase.auth.getUser()
  const { data: profile } = authData.user
    ? await supabase.from('profiles').select('organization_id, role').eq('id', authData.user.id).maybeSingle()
    : { data: null }
  const { data: owners } = profile?.organization_id
    ? await supabase.from('profiles').select('id, full_name, email').eq('organization_id', profile.organization_id).order('full_name')
    : { data: [] }
  const canEdit = profile?.role === 'admin' || profile?.role === 'procurement_user'

  return (
    <div className="mx-auto w-full max-w-4xl p-4 sm:p-6 lg:p-8">
      <Link href="/suppliers" className="mb-4 inline-flex items-center gap-2 text-sm font-medium text-[var(--text-2)] hover:text-[var(--text)]"><ArrowLeft className="h-4 w-4" aria-hidden="true" />Back to suppliers</Link>
      <PageHeader eyebrow="Supplier intelligence" title="New supplier" description="Create a reusable supplier relationship record without starting a sourcing project." />
      <Card className="mt-6 p-5 sm:p-6">
        {canEdit ? <SupplierForm values={emptySupplier} owners={(owners || []).map(owner => ({ id: owner.id, label: owner.full_name || owner.email || 'Workspace member' }))} /> : <p className="text-sm text-[var(--text-2)]">Your workspace role is read only. Ask an administrator or procurement user to create this supplier.</p>}
      </Card>
    </div>
  )
}
