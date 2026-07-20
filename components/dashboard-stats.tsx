'use client'

import { formatCurrency } from '@/lib/utils'
import { DollarSign, Briefcase, TrendingUp, TrendingDown, AlertTriangle } from 'lucide-react'
import { clsx } from 'clsx'

type Stats = {
  totalSavings: number
  activeEvents: number
  realizedSavings: number
  pipelineSavings: number
  leakage: number
  financeValidated: number
}

export function DashboardStats({ stats }: { stats: Stats }) {
  const cards = [
    { label: 'Total Gross Savings', value: formatCurrency(stats.totalSavings), icon: DollarSign, color: 'text-green-600', bg: 'bg-green-50' },
    { label: 'Active Events', value: stats.activeEvents.toString(), icon: Briefcase, color: 'text-indigo-600', bg: 'bg-indigo-50' },
    { label: 'Realized Savings', value: formatCurrency(stats.realizedSavings), icon: TrendingUp, color: 'text-blue-600', bg: 'bg-blue-50' },
    { label: 'Pipeline Value', value: formatCurrency(stats.pipelineSavings), icon: DollarSign, color: 'text-purple-600', bg: 'bg-purple-50' },
    { label: 'Finance Validated', value: formatCurrency(stats.financeValidated), icon: TrendingUp, color: 'text-emerald-600', bg: 'bg-emerald-50' },
    { label: 'Leakage', value: formatCurrency(stats.leakage), icon: AlertTriangle, color: 'text-red-600', bg: 'bg-red-50' },
  ]

  return (
    <div className="grid grid-cols-2 gap-4 lg:grid-cols-3">
      {cards.map((card) => {
        const Icon = card.icon
        return (
          <div key={card.label} className="rounded-lg border border-gray-200 bg-white p-6 shadow-sm">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm font-medium text-gray-500">{card.label}</p>
                <p className="mt-2 text-2xl font-bold text-gray-900">{card.value}</p>
              </div>
              <div className={clsx('flex h-12 w-12 items-center justify-center rounded-lg', card.bg)}>
                <Icon className={clsx('h-6 w-6', card.color)} />
              </div>
            </div>
          </div>
        )
      })}
    </div>
  )
}
