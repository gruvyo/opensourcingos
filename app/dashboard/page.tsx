import { createClient } from '@/lib/supabase/server'
import { DashboardStats } from '@/components/dashboard-stats'
import { SavingsByCategoryChart, EventsByStatusChart, SavingsByTypeChart } from '@/components/dashboard-charts'
import Link from 'next/link'

function getFirst(obj: any): any {
  if (!obj) return null
  if (Array.isArray(obj)) return obj[0] || null
  return obj
}

export default async function DashboardPage() {
  const supabase = await createClient()

  const [
    { data: events },
    { data: savingsCalcs },
  ] = await Promise.all([
    supabase.from('sourcing_events').select(`
      id, event_name, event_status, project_type, contract_start_date,
      category:categories!sourcing_events_category_id_fkey(category_name),
      business_unit:business_units(business_unit_name)
    `),
    supabase.from('savings_calculations').select(`
      id, savings_type, gross_savings_amount,
      cost_reduction_amount, cost_avoidance_amount,
      savings_start_date, savings_end_date, event_id
    `),
  ])

  // Helper to get category name from Supabase join (returns array)
  const getCategoryName = (event: any): string => {
    if (!event?.category) return 'Uncategorized'
    if (Array.isArray(event.category)) {
      return event.category[0]?.category_name || 'Uncategorized'
    }
    return event.category.category_name || 'Uncategorized'
  }

  // Savings totals
  const totalSavings = (savingsCalcs || []).reduce((sum, c) => sum + (c.gross_savings_amount || 0), 0)
  const totalCostReduction = (savingsCalcs || []).reduce((sum, c) => sum + (c.cost_reduction_amount || 0), 0)
  const totalCostAvoidance = (savingsCalcs || []).reduce((sum, c) => sum + (c.cost_avoidance_amount || 0), 0)

  // Active events (not closed/cancelled/rejected/complete)
  const activeEvents = (events || []).filter((e: any) => !['Closed', 'Cancelled', 'Rejected', 'Complete'].includes(e.event_status)).length

  // Realized vs Accrued (date-based, from savings_start_date on the calculation, fallback to contract_start_date)
  const now = new Date()
  let realizedSavings = 0
  let accruedSavings = 0
  for (const calc of savingsCalcs || []) {
    const startDate = calc.savings_start_date
    if (!startDate) {
      // Fallback to event contract_start_date
      const event = events?.find((e: any) => e.id === calc.event_id)
      const contractStart = event?.contract_start_date
      if (contractStart && new Date(contractStart) <= now) {
        realizedSavings += (calc.gross_savings_amount || 0)
      } else {
        accruedSavings += (calc.gross_savings_amount || 0)
      }
    } else if (new Date(startDate) <= now) {
      realizedSavings += (calc.gross_savings_amount || 0)
    } else {
      accruedSavings += (calc.gross_savings_amount || 0)
    }
  }

  // Savings by Category
  const savingsByCategoryMap = new Map<string, number>()
  for (const calc of savingsCalcs || []) {
    const event = events?.find((e: any) => e.id === calc.event_id)
    const catName = getCategoryName(event)
    savingsByCategoryMap.set(catName, (savingsByCategoryMap.get(catName) || 0) + (calc.gross_savings_amount || 0))
  }
  const savingsByCategory = Array.from(savingsByCategoryMap.entries())
    .map(([name, value]) => ({ name, value }))
    .sort((a, b) => b.value - a.value)
    .slice(0, 8)

  // Events by Status
  const statusMap = new Map<string, number>()
  for (const event of events || []) {
    statusMap.set(event.event_status, (statusMap.get(event.event_status) || 0) + 1)
  }
  const eventsByStatus = Array.from(statusMap.entries()).map(([name, value]) => ({ name, value }))

  // Savings by Type
  const typeMap = new Map<string, number>()
  for (const calc of savingsCalcs || []) {
    typeMap.set(calc.savings_type, (typeMap.get(calc.savings_type) || 0) + (calc.gross_savings_amount || 0))
  }
  const savingsByType = Array.from(typeMap.entries()).map(([name, value]) => ({ name, value }))

  return (
    <div className="p-8">
      <div className="mb-6">
        <h1 className="text-2xl font-bold text-gray-900 dark:text-gray-100">Dashboard</h1>
        <p className="mt-1 text-sm text-gray-600 dark:text-gray-400">
          Procurement value overview — savings, pipeline, and project activity
        </p>
      </div>

      <DashboardStats stats={{
        totalSavings,
        activeEvents,
        realizedSavings,
        accruedSavings,
        totalCostReduction,
        totalCostAvoidance,
      }} />

      <div className="mt-6 grid grid-cols-1 gap-6 lg:grid-cols-2">
        <SavingsByCategoryChart data={savingsByCategory} />
        <EventsByStatusChart data={eventsByStatus} />
        <SavingsByTypeChart data={savingsByType} />
      </div>

      <div className="mt-6 rounded-lg border border-gray-200 bg-white p-6 shadow-sm dark:border-gray-700 dark:bg-gray-800">
        <div className="mb-4 flex items-center justify-between">
          <h3 className="text-sm font-semibold uppercase tracking-wider text-gray-500 dark:text-gray-400">Recent Projects</h3>
          <Link href="/events" className="text-sm font-medium text-indigo-600 hover:text-indigo-800 dark:text-indigo-400">
            View all →
          </Link>
        </div>
        <div className="space-y-2">
          {(events || []).slice(0, 5).map((event: any) => (
            <Link key={event.id} href={`/events/${event.id}`}
              className="flex items-center justify-between rounded-lg border border-gray-100 px-4 py-3 hover:bg-gray-50 dark:border-gray-700 dark:hover:bg-gray-700/50">
              <div>
                <p className="text-sm font-medium text-gray-900 dark:text-gray-100">{event.event_name}</p>
                <p className="text-xs text-gray-500 dark:text-gray-400">{getCategoryName(event)}</p>
              </div>
              <span className="text-xs text-gray-500 dark:text-gray-400">{event.event_status}</span>
            </Link>
          ))}
        </div>
      </div>
    </div>
  )
}