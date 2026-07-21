'use client'

import { formatCurrency } from '@/lib/utils'
import { DollarSign, Briefcase, ArrowDownRight, ArrowUpRight } from 'lucide-react'
import { clsx } from 'clsx'

type Stats = {
  totalSavings: number
  activeEvents: number
  totalCostReduction: number
  totalCostAvoidance: number
}

export function DashboardStats({ stats }: { stats: Stats }) {
  const savingsCards = [
    { label: 'Total Savings', value: formatCurrency(stats.totalSavings), icon: DollarSign, color: 'text-green-600 dark:text-green-400', bg: 'bg-green-50 dark:bg-green-900/30', sub: 'Cost reduction + cost avoidance' },
    { label: 'Cost Reduction', value: formatCurrency(stats.totalCostReduction), icon: ArrowDownRight, color: 'text-red-600 dark:text-red-400', bg: 'bg-red-50 dark:bg-red-900/30', sub: 'Actual bottom-line reduction — price went down' },
    { label: 'Cost Avoidance', value: formatCurrency(stats.totalCostAvoidance), icon: ArrowUpRight, color: 'text-amber-600 dark:text-amber-400', bg: 'bg-amber-50 dark:bg-amber-900/30', sub: 'Value not paid — negotiated below supplier proposal' },
  ]

  const projectCards = [
    { label: 'Active Projects', value: stats.activeEvents.toString(), icon: Briefcase, color: 'text-indigo-600 dark:text-indigo-400', bg: 'bg-indigo-50 dark:bg-indigo-900/30', sub: 'Sourcing + support projects in progress' },
  ]

  return (
    <div className="space-y-4">
      {/* Savings cards — grouped together */}
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-3">
        {savingsCards.map((card) => {
          const Icon = card.icon
          return (
            <div key={card.label} className="rounded-lg border border-gray-200 bg-white p-6 shadow-sm dark:border-gray-700 dark:bg-gray-800">
              <div className="flex items-center justify-between">
                <div className="min-w-0">
                  <p className="text-sm font-medium text-gray-500 dark:text-gray-400">{card.label}</p>
                  <p className="mt-2 text-2xl font-bold text-gray-900 dark:text-gray-100">{card.value}</p>
                  {card.sub && (
                    <p className="mt-1 text-xs text-gray-400 dark:text-gray-500">{card.sub}</p>
                  )}
                </div>
                <div className={clsx('flex h-12 w-12 shrink-0 items-center justify-center rounded-lg', card.bg)}>
                  <Icon className={clsx('h-6 w-6', card.color)} />
                </div>
              </div>
            </div>
          )
        })}
      </div>

      {/* Project cards — separate row */}
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-3">
        {projectCards.map((card) => {
          const Icon = card.icon
          return (
            <div key={card.label} className="rounded-lg border border-gray-200 bg-white p-6 shadow-sm dark:border-gray-700 dark:bg-gray-800">
              <div className="flex items-center justify-between">
                <div className="min-w-0">
                  <p className="text-sm font-medium text-gray-500 dark:text-gray-400">{card.label}</p>
                  <p className="mt-2 text-2xl font-bold text-gray-900 dark:text-gray-100">{card.value}</p>
                  {card.sub && (
                    <p className="mt-1 text-xs text-gray-400 dark:text-gray-500">{card.sub}</p>
                  )}
                </div>
                <div className={clsx('flex h-12 w-12 shrink-0 items-center justify-center rounded-lg', card.bg)}>
                  <Icon className={clsx('h-6 w-6', card.color)} />
                </div>
              </div>
            </div>
          )
        })}
      </div>
    </div>
  )
}