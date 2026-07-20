'use client'

import { formatCurrency } from '@/lib/utils'
import { DollarSign, Briefcase, TrendingUp, Clock, CheckCircle, ArrowDownRight, ArrowUpRight } from 'lucide-react'
import { clsx } from 'clsx'

type Stats = {
  totalSavings: number
  activeEvents: number
  realizedSavings: number
  accruedSavings: number
  financeValidated: number
  totalCostReduction: number
  totalCostAvoidance: number
}

export function DashboardStats({ stats }: { stats: Stats }) {
  const cards = [
    { label: 'Total Savings', value: formatCurrency(stats.totalSavings), icon: DollarSign, color: 'text-green-600 dark:text-green-400', bg: 'bg-green-50 dark:bg-green-900/30' },
    { label: 'Active Projects', value: stats.activeEvents.toString(), icon: Briefcase, color: 'text-indigo-600 dark:text-indigo-400', bg: 'bg-indigo-50 dark:bg-indigo-900/30' },
    { label: 'Realized Savings', value: formatCurrency(stats.realizedSavings), icon: CheckCircle, color: 'text-emerald-600 dark:text-emerald-400', bg: 'bg-emerald-50 dark:bg-emerald-900/30', sub: 'Contract start ≤ today' },
    { label: 'Accrued Savings', value: formatCurrency(stats.accruedSavings), icon: Clock, color: 'text-blue-600 dark:text-blue-400', bg: 'bg-blue-50 dark:bg-blue-900/30', sub: 'Contract start > today' },
    { label: 'Finance Validated', value: formatCurrency(stats.financeValidated), icon: TrendingUp, color: 'text-purple-600 dark:text-purple-400', bg: 'bg-purple-50 dark:bg-purple-900/30' },
    { label: 'Cost Reduction', value: formatCurrency(stats.totalCostReduction), icon: ArrowDownRight, color: 'text-red-600 dark:text-red-400', bg: 'bg-red-50 dark:bg-red-900/30', sub: 'Actual bottom-line reduction' },
    { label: 'Cost Avoidance', value: formatCurrency(stats.totalCostAvoidance), icon: ArrowUpRight, color: 'text-amber-600 dark:text-amber-400', bg: 'bg-amber-50 dark:bg-amber-900/30', sub: 'Value not paid' },
  ]

  return (
    <div className="grid grid-cols-2 gap-4 lg:grid-cols-4">
      {cards.map((card) => {
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
  )
}