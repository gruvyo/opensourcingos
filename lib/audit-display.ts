import type { Json } from '@/lib/database.types'

export const AUDIT_ENTITY_FILTERS = [
  'organization',
  'organization_settings',
  'supplier',
  'supplier_contact',
  'supplier_certification',
  'supplier_performance_review',
  'supplier_risk',
  'project_choice_option',
  'category',
  'business_unit',
  'cost_center',
  'project_classification_reset',
  'savings_calculation',
] as const

export const AUDIT_ACTION_FILTERS = ['insert', 'update', 'delete'] as const

export type AuditEntityType = (typeof AUDIT_ENTITY_FILTERS)[number]
export type AuditAction = (typeof AUDIT_ACTION_FILTERS)[number]

const entityLabels: Record<AuditEntityType, string> = {
  organization: 'Workspace',
  organization_settings: 'Workspace settings',
  supplier: 'Supplier',
  supplier_contact: 'Supplier contact',
  supplier_certification: 'Supplier certification',
  supplier_performance_review: 'Supplier performance review',
  supplier_risk: 'Supplier risk',
  project_choice_option: 'Workspace choice',
  category: 'Category',
  business_unit: 'Business unit',
  cost_center: 'Cost center',
  project_classification_reset: 'Classification reset',
  savings_calculation: 'Savings calculation',
}

const fieldLabels: Record<string, string> = {
  name: 'Name',
  supplier_name: 'Supplier name',
  contact_name: 'Contact name',
  certification_name: 'Certification name',
  issuer: 'Issuer',
  certificate_number: 'Certificate number',
  issued_on: 'Issue date',
  expires_on: 'Expiration date',
  evidence_url: 'Evidence link',
  review_title: 'Review title',
  review_date: 'Review date',
  overall_score: 'Overall score',
  delivery_score: 'Delivery score',
  quality_score: 'Quality score',
  commercial_score: 'Commercial score',
  compliance_score: 'Compliance score',
  risk_title: 'Risk title',
  identified_on: 'Identified on',
  severity: 'Severity',
  risk_status: 'Risk status',
  target_resolution_date: 'Target resolution',
  job_title: 'Role or title',
  email: 'Email',
  phone: 'Phone',
  is_primary: 'Primary contact',
  supplier_status: 'Status',
  risk_rating: 'Risk rating',
  preferred_flag: 'Preferred supplier',
  diversity_flag: 'Diverse supplier',
  next_review_date: 'Next review',
  website: 'Website',
  country_code: 'Country',
  label: 'Label',
  active_flag: 'Availability',
  sort_order: 'Display order',
  category_name: 'Category name',
  business_unit_name: 'Business unit name',
  cost_center_name: 'Cost center name',
  currency_code: 'Currency',
  locale: 'Locale',
  timezone: 'Timezone',
  fiscal_year_start_month: 'Fiscal year start',
  date_format: 'Date format',
  default_recognition_method: 'Recognition method',
  support_projects_enabled: 'Support projects',
  project_descriptions_enabled: 'Project descriptions',
  project_owners_enabled: 'Project owners',
  project_cost_centers_enabled: 'Project cost centers',
  project_categories_enabled: 'Project categories',
  project_business_units_enabled: 'Project business units',
  project_updates_enabled: 'Project updates',
  project_incumbent_suppliers_enabled: 'Incumbent suppliers',
  savings_realization_enabled: 'Savings realization',
  require_baseline_for_hard_reduction: 'Baseline requirement',
  hard_reduction_approval_threshold: 'Approval threshold',
  calculation_name: 'Calculation name',
  calculation_status: 'Savings status',
  schedule_start_date: 'Schedule start',
  schedule_end_date: 'Schedule end',
  recognition_method: 'Schedule frequency',
}

const excludedFields = new Set([
  'id',
  'organization_id',
  'relationship_owner_id',
  'created_at',
  'updated_at',
  'created_by',
  'updated_by',
  'normalized_name',
  'password',
  'token',
  'notes',
  'summary',
  'description',
  'tax_id',
])

export type AuditChange = {
  field: string
  label: string
  before: string
  after: string
}

function asRecord(value: Json | null): Record<string, Json | undefined> {
  if (!value || Array.isArray(value) || typeof value !== 'object') return {}
  return value
}

function formatValue(value: Json | undefined): string {
  if (value === null || value === undefined || value === '') return 'Not set'
  if (typeof value === 'boolean') return value ? 'On' : 'Off'
  if (typeof value === 'number') return new Intl.NumberFormat('en-US').format(value)
  if (typeof value === 'string') return value.length > 80 ? `${value.slice(0, 77)}…` : value
  return 'Updated'
}

export function auditEntityLabel(entityType: string): string {
  if (AUDIT_ENTITY_FILTERS.includes(entityType as AuditEntityType)) {
    return entityLabels[entityType as AuditEntityType]
  }
  return entityType
    .split('_')
    .map(part => part.charAt(0).toUpperCase() + part.slice(1))
    .join(' ')
}

export function auditActionLabel(action: string, entityType?: string): string {
  if (entityType === 'project_classification_reset') return 'Reset'
  if (action === 'insert') return 'Added'
  if (action === 'delete') return 'Deleted'
  if (action === 'update') return 'Updated'
  return action.charAt(0).toUpperCase() + action.slice(1)
}

export function auditSubject(beforeData: Json | null, afterData: Json | null): string | null {
  const record = { ...asRecord(beforeData), ...asRecord(afterData) }
  for (const key of ['supplier_name', 'contact_name', 'certification_name', 'review_title', 'risk_title', 'label', 'category_name', 'business_unit_name', 'cost_center_name', 'calculation_name', 'name']) {
    const value = record[key]
    if (typeof value === 'string' && value.trim()) return value
  }
  return null
}

export function auditChanges(beforeData: Json | null, afterData: Json | null, limit = 4): AuditChange[] {
  const before = asRecord(beforeData)
  const after = asRecord(afterData)
  const keys = new Set([...Object.keys(before), ...Object.keys(after)])

  return [...keys]
    .filter(key => !excludedFields.has(key) && fieldLabels[key] && JSON.stringify(before[key]) !== JSON.stringify(after[key]))
    .slice(0, limit)
    .map(field => ({
      field,
      label: fieldLabels[field],
      before: formatValue(before[field]),
      after: formatValue(after[field]),
    }))
}

export function formatAuditTimestamp(timestamp: string, timeZone = 'America/Chicago'): string {
  const date = new Date(timestamp)
  if (Number.isNaN(date.getTime())) return '—'
  try {
    return new Intl.DateTimeFormat('en-US', {
      month: 'short',
      day: 'numeric',
      year: 'numeric',
      hour: 'numeric',
      minute: '2-digit',
      timeZone,
      timeZoneName: 'short',
    }).format(date)
  } catch {
    return new Intl.DateTimeFormat('en-US', {
      month: 'short',
      day: 'numeric',
      year: 'numeric',
      hour: 'numeric',
      minute: '2-digit',
      timeZone: 'UTC',
      timeZoneName: 'short',
    }).format(date)
  }
}
