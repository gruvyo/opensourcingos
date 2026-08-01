import { Card } from '@/components/ui/card'

export type ActivityBreakdown = {
  title: string
  description: string
  items: Array<{ label: string; value: number }>
}

export function DashboardActivityBreakdowns({ cards }: { cards: ActivityBreakdown[] }) {
  return (
    <section aria-labelledby="portfolio-activity-title" className="mt-10">
      <div className="mb-4">
        <h2 id="portfolio-activity-title" className="text-lg font-semibold text-[var(--text)]">
          Portfolio activity
        </h2>
        <p className="mt-1 text-sm text-[var(--text-2)]">
          Project volume and ownership across the active sourcing portfolio.
        </p>
      </div>

      <div className="grid grid-cols-1 gap-4 md:grid-cols-2 xl:grid-cols-4">
        {cards.map(card => (
          <Card key={card.title} className="overflow-hidden">
            <div className="border-b border-[var(--border)] px-5 py-4">
              <h3 className="text-sm font-semibold text-[var(--text)]">{card.title}</h3>
              <p className="mt-1 text-xs text-[var(--text-3)]">{card.description}</p>
            </div>
            <div className="divide-y divide-[var(--border)]">
              {card.items.length === 0 ? (
                <p className="px-5 py-6 text-sm text-[var(--text-3)]">No data yet</p>
              ) : card.items.map(item => (
                <div key={item.label} className="flex items-center justify-between gap-4 px-5 py-3">
                  <span className="truncate text-sm text-[var(--text-2)]" title={item.label}>{item.label}</span>
                  <span className="shrink-0 text-sm font-semibold tabular-nums text-[var(--text)]">{item.value}</span>
                </div>
              ))}
            </div>
          </Card>
        ))}
      </div>
    </section>
  )
}
