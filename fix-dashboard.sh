#!/bin/bash

cat > app/dashboard/page.tsx << 'EOF'
import { createClient } from '@/lib/supabase/server'
import { DashboardStats } from '@/components/dashboard-stats'
import { SavingsByCategoryChart, EventsByStatusChart, SavingsByTypeChart, SavingsTrendChart } from '@/components/dashboard-charts'
import Link from 'next/link'

export default async function DashboardPage() {
  const supabase = await createClient()

  const [
    { data: events },
    { data: savingsCalcs },
    { data: realizationPeriods },
  ] = await Promise.all([
    supabase.from('sourcing_events').select(`
      id, event_name, event_status,
      category:categories!sourcing_events_category_id_fkey(category_name)
    `),
    supabase.from('savings_calculations').select('id, savings_type, gross_savings_amount, finance_validated, current_year_recognized_amount, event_id'),
    supabase.from('realization_periods').select('id, projected_savings, realized_savings, leakage_amount, period_name'),
  ])

  const totalSavings = (savingsCalcs || []).reduce((sum, c) => sum + (c.gross_savings_amount || 0), 0)
  const activeEvents = (events || []).filter((e: any) => !['Closed', 'Cancelled', 'Rejected'].includes(e.event_status)).length
  const realizedSavings = (realizationPeriods || []).reduce((sum, p) => sum + (p.realized_savings || 0), 0)
  const leakage = (realizationPeriods || []).reduce((sum, p) => sum + (p.leakage_amount || 0), 0)
  const financeValidated = (savingsCalcs || []).filter((c: any) => c.finance_validated).reduce((sum: number, c: any) => sum + (c.gross_savings_amount || 0), 0)
  const pipelineSavings = (savingsCalcs || []).reduce((sum: number, c: any) => sum + ((c.gross_savings_amount || 0) - (c.current_year_recognized_amount || 0)), 0)

  // Helper to get category name from Supabase join (returns array)
  const getCategoryName = (event: any): string => {
    if (!event?.category) return 'Uncategorized'
    if (Array.isArray(event.category)) {
      return event.category[0]?.category_name || 'Uncategorized'
    }
    return event.category.category_name || 'Uncategorized'
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

  // Savings Trend by Quarter
  const trendMap = new Map<string, { projected: number; realized: number }>()
  for (const period of realizationPeriods || []) {
    const existing = trendMap.get(period.period_name) || { projected: 0, realized: 0 }
    trendMap.set(period.period_name, {
      projected: existing.projected + (period.projected_savings || 0),
      realized: existing.realized + (period.realized_savings || 0),
    })
  }
  const savingsTrend = Array.from(trendMap.entries()).map(([name, values]) => ({ name, ...values }))

  return (
    <div className="p-8">
      <div className="mb-6">
        <h1 className="text-2xl font-bold text-gray-900">Dashboard</h1>
        <p className="mt-1 text-sm text-gray-600">
          Procurement value overview — savings, pipeline, and realization
        </p>
      </div>

      <DashboardStats stats={{
        totalSavings,
        activeEvents,
        realizedSavings,
        pipelineSavings,
        leakage,
        financeValidated,
      }} />

      <div className="mt-6 grid grid-cols-1 gap-6 lg:grid-cols-2">
        <SavingsByCategoryChart data={savingsByCategory} />
        <EventsByStatusChart data={eventsByStatus} />
        <SavingsByTypeChart data={savingsByType} />
        <SavingsTrendChart data={savingsTrend} />
      </div>

      <div className="mt-6 rounded-lg border border-gray-200 bg-white p-6 shadow-sm">
        <div className="mb-4 flex items-center justify-between">
          <h3 className="text-sm font-semibold uppercase tracking-wider text-gray-500">Recent Events</h3>
          <Link href="/events" className="text-sm font-medium text-indigo-600 hover:text-indigo-800">
            View all →
          </Link>
        </div>
        <div className="space-y-2">
          {(events || []).slice(0, 5).map((event: any) => (
            <Link key={event.id} href={`/events/${event.id}`}
              className="flex items-center justify-between rounded-lg border border-gray-100 px-4 py-3 hover:bg-gray-50">
              <div>
                <p className="text-sm font-medium text-gray-900">{event.event_name}</p>
                <p className="text-xs text-gray-500">{getCategoryName(event)}</p>
              </div>
              <span className="text-xs text-gray-500">{event.event_status}</span>
            </Link>
          ))}
        </div>
      </div>
    </div>
  )
}
EOF

echo "DONE"
