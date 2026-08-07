import { createClient } from '@/lib/supabase/server'
import { EventForm } from '@/components/event-form'
import Link from 'next/link'
import { ArrowLeft } from 'lucide-react'

export default async function NewEventPage() {
  const supabase = await createClient()

  const [
    { data: categories, error: categoriesError },
    { data: businessUnits, error: businessUnitsError },
    { data: costCenters, error: costCentersError },
    { data: suppliers, error: suppliersError },
    { data: settings, error: settingsError },
  ] = await Promise.all([
    supabase.from('categories').select('id, category_name').order('category_name'),
    supabase.from('business_units').select('id, business_unit_name').order('business_unit_name'),
    supabase.from('cost_centers').select('id, cost_center_name, business_unit_id').order('cost_center_name'),
    supabase.from('suppliers').select('id, supplier_name').order('supplier_name'),
    supabase.from('organization_settings').select('currency_code, support_projects_enabled, project_descriptions_enabled, project_owners_enabled, project_cost_centers_enabled, project_categories_enabled, project_business_units_enabled').maybeSingle(),
  ])

  // A failed query here would render as an empty dropdown, which is indistinguishable
  // from a genuinely empty list. Say which one it is.
  const loadError = categoriesError?.message || businessUnitsError?.message
    || costCentersError?.message || suppliersError?.message || settingsError?.message || null

  return (
    <div className="p-8">
      <Link href="/events" className="mb-4 flex items-center gap-2 text-sm text-gray-600 hover:text-gray-900 dark:text-gray-400 dark:hover:text-gray-200">
        <ArrowLeft className="h-4 w-4" />
        Back to Projects
      </Link>
      <h1 className="text-2xl font-bold text-gray-900 dark:text-gray-100">New Project</h1>
      <p className="mt-1 text-sm text-gray-600 dark:text-gray-400">
        {settings?.support_projects_enabled ?? true
          ? 'Create a new sourcing event or support project'
          : 'Create a new sourcing project'}
      </p>

      {loadError && (
        <div className="mt-6 rounded-lg bg-red-50 p-4 text-sm text-red-700 dark:bg-red-900/30 dark:text-red-300" role="alert">
          <strong>These figures are incomplete.</strong> A query failed: {loadError}. Do not report
          from this page until it loads cleanly.
        </div>
      )}

      <EventForm
        categories={categories || []}
        businessUnits={businessUnits || []}
        costCenters={costCenters || []}
        suppliers={suppliers || []}
        defaultCurrency={settings?.currency_code || 'USD'}
        supportProjectsEnabled={settings?.support_projects_enabled ?? true}
        projectDescriptionsEnabled={settings?.project_descriptions_enabled ?? true}
        projectOwnersEnabled={settings?.project_owners_enabled ?? true}
        projectCostCentersEnabled={settings?.project_cost_centers_enabled ?? true}
        projectCategoriesEnabled={settings?.project_categories_enabled ?? true}
        projectBusinessUnitsEnabled={settings?.project_business_units_enabled ?? true}
      />
    </div>
  )
}
