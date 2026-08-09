'use server'

import { revalidatePath } from 'next/cache'
import { z } from 'zod'
import { requireWorkspace } from '@/lib/authz'

export type ReviewActionState = { status: 'idle' | 'success' | 'error'; message: string }

const score = z.number().int().min(1).max(5)
const optionalScore = score.nullable()
const optionalDate = z.union([z.literal(''), z.iso.date('Enter a valid date.')])
const reviewSchema = z.object({
  reviewTitle: z.string().trim().min(2, 'Review title is required.').max(200),
  reviewDate: z.iso.date('Enter a valid review date.'),
  overallScore: score,
  deliveryScore: optionalScore,
  qualityScore: optionalScore,
  commercialScore: optionalScore,
  complianceScore: optionalScore,
  summary: z.string().trim().min(1, 'Add a review summary.').max(10000),
  nextReviewDate: optionalDate,
}).refine(value => !value.nextReviewDate || value.nextReviewDate >= value.reviewDate, {
  message: 'Next review date cannot be before the review date.',
  path: ['nextReviewDate'],
})

function readScore(formData: FormData, name: string) {
  const value = String(formData.get(name) || '')
  return value ? Number(value) : null
}

function parseReview(formData: FormData) {
  return reviewSchema.safeParse({
    reviewTitle: formData.get('reviewTitle'),
    reviewDate: formData.get('reviewDate'),
    overallScore: readScore(formData, 'overallScore'),
    deliveryScore: readScore(formData, 'deliveryScore'),
    qualityScore: readScore(formData, 'qualityScore'),
    commercialScore: readScore(formData, 'commercialScore'),
    complianceScore: readScore(formData, 'complianceScore'),
    summary: formData.get('summary'),
    nextReviewDate: formData.get('nextReviewDate') || '',
  })
}

export async function saveSupplierReview(supplierId: string, reviewId: string | null, _previous: ReviewActionState, formData: FormData): Promise<ReviewActionState> {
  try {
    const supplier = z.string().uuid().parse(supplierId)
    const review = reviewId ? z.string().uuid().parse(reviewId) : null
    const parsed = parseReview(formData)
    if (!parsed.success) return { status: 'error', message: parsed.error.issues[0]?.message || 'Check the review.' }
    const { supabase, profile } = await requireWorkspace(['admin', 'procurement_user'])
    const { data: supplierRow, error: supplierError } = await supabase.from('suppliers').select('id').eq('id', supplier).eq('organization_id', profile.organization_id).maybeSingle()
    if (supplierError || !supplierRow) return { status: 'error', message: 'Supplier not found or you do not have access.' }

    const value = parsed.data
    const payload = {
      organization_id: profile.organization_id,
      supplier_id: supplier,
      review_title: value.reviewTitle,
      review_date: value.reviewDate,
      overall_score: value.overallScore,
      delivery_score: value.deliveryScore,
      quality_score: value.qualityScore,
      commercial_score: value.commercialScore,
      compliance_score: value.complianceScore,
      summary: value.summary,
      next_review_date: value.nextReviewDate || null,
      updated_by: profile.id,
    }
    const result = review
      ? await supabase.from('supplier_performance_reviews').update(payload).eq('id', review).eq('supplier_id', supplier).eq('organization_id', profile.organization_id).select('id').maybeSingle()
      : await supabase.from('supplier_performance_reviews').insert({ ...payload, created_by: profile.id }).select('id').maybeSingle()
    if (result.error) return { status: 'error', message: result.error.message }
    if (!result.data) return { status: 'error', message: 'Review not found or you do not have access.' }
    revalidatePath(`/suppliers/${supplier}`)
    return { status: 'success', message: review ? 'Review saved.' : 'Review added.' }
  } catch (error) {
    return { status: 'error', message: error instanceof Error ? error.message : 'Review could not be saved.' }
  }
}

export async function deleteSupplierReview(supplierId: string, reviewId: string): Promise<ReviewActionState> {
  try {
    const supplier = z.string().uuid().parse(supplierId)
    const review = z.string().uuid().parse(reviewId)
    const { supabase, profile } = await requireWorkspace(['admin', 'procurement_user'])
    const { data, error } = await supabase.from('supplier_performance_reviews').delete().eq('id', review).eq('supplier_id', supplier).eq('organization_id', profile.organization_id).select('id').maybeSingle()
    if (error) return { status: 'error', message: error.message }
    if (!data) return { status: 'error', message: 'Review not found or you do not have access.' }
    revalidatePath(`/suppliers/${supplier}`)
    return { status: 'success', message: 'Review deleted.' }
  } catch (error) {
    return { status: 'error', message: error instanceof Error ? error.message : 'Review could not be deleted.' }
  }
}
