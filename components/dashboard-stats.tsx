'use client'

import { formatCurrency, formatReduction } from '@/lib/utils'
import { Card } from '@/components/ui/card'
import { DollarSign, Briefcase, ArrowDownRight, ArrowUpRight, TrendingUp } from 'lucide-react'
import { clsx } from 'clsx'
import type { ComponentType } from 'react'

type Stats = {
  totalSavings: number
  activeEvents: number
  totalCostReduction: number
  totalCostAvoidance: number
  booked: number
  forecast: number
  bookedCount: number
  forecastCount: number
}

type CardDef = {
  label: string
  value: string
  icon: ComponentType<{ className?: string }>
  color: string
  bg: string
  sub?: string
}

function StatCard({ card }: { card: CardDef }) {
  const Icon = card.icon
  return (
    <Card className="p-6">
      {/* Label and icon share the top row; the VALUE gets the full card width
          below them. Previously the value sat beside the icon and overflowed
          behind it on narrower viewports, clipping digits off a money figure. */}
      <div className="flex items-start justify-between gap-3">
        <p className="text-sm font-medium text-[var(--text-2)]">{card.label}</p>
        <div className={clsx('flex h-10 w-10 shrink-0 items-center justify-center rounded-lg', card.bg)}>
          <Icon className={clsx('h-5 w-5', card.color)} />
        </div>
      </div>
      <p className="mt-2 text-2xl font-bold tabular-nums tracking-tight text-[var(--text)]">
        {card.value}
      </p>
      {card.sub && <p className="mt-1 text-xs text-[var(--text-3)]">{card.sub}</p>}
    </Card>
  )
}

export function DashboardStats({ stats }: { stats: Stats }) {
  const savingsCards: CardDef[] = [
    { label: 'Total Savings', value: formatCurrency(stats.totalSavings), icon: DollarSign, color: 'text-green-600 dark:text-green-400', bg: 'bg-green-50 dark:bg-green-900/30', sub: 'Cost reduction + cost avoidance' },
    { label: 'Cost Reduction', value: formatReduction(stats.totalCostReduction), icon: ArrowDownRight, color: 'text-red-600 dark:text-red-400', bg: 'bg-red-50 dark:bg-red-900/30', sub: 'Actual bottom-line reduction — price went down' },
    { label: 'Cost Avoidance', value: formatCurrency(stats.totalCostAvoidance), icon: ArrowUpRight, color: 'text-amber-600 dark:text-amber-400', bg: 'bg-amber-50 dark:bg-amber-900/30', sub: 'Value not paid — negotiated below supplier proposal' },
  ]

  // Pipeline vs booked. Deals still at identified/negotiated are a FORECAST and
  // are reported separately so they never inflate the booked number.
  const pipelineCards: CardDef[] = [
    { label: 'Booked Savings', value: formatCurrency(stats.booked), icon: DollarSign, color: 'text-green-600 dark:text-green-400', bg: 'bg-green-50 dark:bg-green-900/30', sub: `Contracted or realized · ${stats.bookedCount} ${stats.bookedCount === 1 ? 'deal' : 'deals'}` },
    { label: 'Forecast (pipeline)', value: formatCurrency(stats.forecast), icon: TrendingUp, color: 'text-blue-600 dark:text-blue-400', bg: 'bg-blue-50 dark:bg-blue-900/30', sub: `Identified or negotiated, not yet closed · ${stats.forecastCount} ${stats.forecastCount === 1 ? 'deal' : 'deals'}` },
    { label: 'Active Projects', value: stats.activeEvents.toString(), icon: Briefcase, color: 'text-indigo-600 dark:text-indigo-400', bg: 'bg-indigo-50 dark:bg-indigo-900/30', sub: 'Sourcing + support projects in progress' },
  ]

  return (
    <div className="space-y-4">
      {/* Savings cards — grouped together */}
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-3">
        {savingsCards.map((card) => <StatCard key={card.label} card={card} />)}
      </div>

      {/* Project cards — separate row */}
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-3">
        {pipelineCards.map((card) => <StatCard key={card.label} card={card} />)}
      </div>
    </div>
  )
}
