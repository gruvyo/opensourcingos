import { formatCurrency, formatReduction } from '@/lib/utils'
import { Card } from '@/components/ui/card'
import { ArrowDownRight, ArrowUpRight, CircleDollarSign, Gauge } from 'lucide-react'
import type { ComponentType } from 'react'

type Stats = {
  totalSavings: number
  totalCostReduction: number | null
  totalCostAvoidance: number
  booked: number
  forecast: number
  realizationRate: number
  realizedSavings: number
  scopeLabel: string
}

type CardDef = {
  label: string
  value: string
  icon: ComponentType<{ className?: string }>
  iconClass: string
  iconBackground: string
  sub: string
  progress?: number
}

function StatCard({ card }: { card: CardDef }) {
  const Icon = card.icon

  return (
    <Card className="relative overflow-hidden p-5 shadow-[0_12px_30px_-24px_rgba(15,23,41,0.45)]">
      <div className="absolute inset-x-0 top-0 h-0.5 bg-gradient-to-r from-transparent via-[var(--brand)] to-transparent opacity-60" />
      <div className="flex items-start justify-between gap-3">
        <div>
          <p className="text-xs font-semibold uppercase tracking-[0.12em] text-[var(--text-3)]">
            {card.label}
          </p>
          <p className="mt-3 text-2xl font-bold tabular-nums tracking-tight text-[var(--text)] xl:text-[1.7rem]">
            {card.value}
          </p>
        </div>

        {card.progress === undefined ? (
          <div className={`flex h-10 w-10 shrink-0 items-center justify-center rounded-full ${card.iconBackground}`}>
            <Icon className={`h-5 w-5 ${card.iconClass}`} aria-hidden="true" />
          </div>
        ) : (
          <div
            className="grid h-11 w-11 shrink-0 place-items-center rounded-full"
            style={{
              background: `conic-gradient(var(--brand) ${Math.min(100, Math.max(0, card.progress))}%, var(--surface-2) 0)`,
            }}
            aria-label={`${card.progress.toFixed(0)} percent realized`}
          >
            <div className="grid h-8 w-8 place-items-center rounded-full bg-[var(--surface)] text-[10px] font-bold tabular-nums text-[var(--brand-ink)]">
              {card.progress.toFixed(0)}%
            </div>
          </div>
        )}
      </div>
      <p className="mt-2 min-h-8 text-xs leading-4 text-[var(--text-3)]">{card.sub}</p>
    </Card>
  )
}

export function DashboardStats({ stats }: { stats: Stats }) {
  const cards: CardDef[] = [
    {
      label: 'Total Savings',
      value: formatCurrency(stats.totalSavings),
      icon: CircleDollarSign,
      iconClass: 'text-emerald-600 dark:text-emerald-300',
      iconBackground: 'bg-emerald-50 dark:bg-emerald-500/15',
      sub: stats.scopeLabel === 'All years'
        ? `${formatCurrency(stats.booked)} booked · ${formatCurrency(stats.forecast)} forecast`
        : `${stats.scopeLabel} cost reduction + cost avoidance`,
    },
    {
      label: 'Cost Reduction',
      value: formatReduction(stats.totalCostReduction),
      icon: ArrowDownRight,
      iconClass: 'text-indigo-600 dark:text-indigo-300',
      iconBackground: 'bg-indigo-50 dark:bg-indigo-500/15',
      sub: 'Hard reduction against a defensible spend baseline',
    },
    {
      label: 'Cost Avoidance',
      value: formatCurrency(stats.totalCostAvoidance),
      icon: ArrowUpRight,
      iconClass: 'text-violet-600 dark:text-violet-300',
      iconBackground: 'bg-violet-50 dark:bg-violet-500/15',
      sub: 'Negotiated value below the supplier’s opening position',
    },
    {
      label: 'Realization',
      value: formatCurrency(stats.realizedSavings),
      icon: Gauge,
      iconClass: 'text-[var(--brand-ink)]',
      iconBackground: 'bg-[var(--brand-soft)]',
      sub: `${stats.realizationRate.toFixed(1)}% of projected savings recorded as realized`,
      progress: stats.realizationRate,
    },
  ]

  return (
    <section aria-label={`${stats.scopeLabel} portfolio summary`} className="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-4">
      {cards.map(card => <StatCard key={card.label} card={card} />)}
    </section>
  )
}
