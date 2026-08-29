'use client'

import Link from 'next/link'
import { CalendarClock, ChevronRight, ShieldAlert, TriangleAlert } from 'lucide-react'
import type { AttentionQueue as AttentionQueueData } from '@/lib/attention-queue'
import { Card } from '@/components/ui/card'
import { useWorkspaceFormat } from '@/components/workspace-format-provider'

export function AttentionQueue({ queue }: { queue: AttentionQueueData }) {
  const { formatDate } = useWorkspaceFormat()

  return (
    <Card className="mt-6 overflow-hidden">
      <div className="flex flex-wrap items-center justify-between gap-3 border-b border-[var(--border)] px-5 py-4 sm:px-6">
        <div>
          <h2 className="text-sm font-semibold text-[var(--text)]">Attention queue</h2>
          <p className="mt-1 text-xs text-[var(--text-3)]">Urgent supplier items and project deadlines due within 30 days</p>
        </div>
        <Link href="/reports" className="inline-flex items-center gap-1 text-xs font-semibold text-[var(--brand-ink)] hover:underline">
          Review portfolio
          <ChevronRight className="h-3.5 w-3.5" aria-hidden="true" />
        </Link>
      </div>

      <div className="grid grid-cols-1 border-b border-[var(--border)] bg-[var(--surface-2)] sm:grid-cols-3">
        <Summary label="Overdue projects" value={queue.overdueProjects} icon={TriangleAlert} />
        <Summary label="Due next 30 days" value={queue.dueSoonProjects} icon={CalendarClock} />
        <Summary label="Supplier attention" value={queue.supplierAttention} icon={ShieldAlert} />
      </div>

      {queue.items.length === 0 ? (
        <div className="px-6 py-8 text-center">
          <p className="text-sm font-medium text-[var(--text)]">Nothing urgent right now</p>
          <p className="mt-1 text-xs text-[var(--text-3)]">No active deadlines or supplier alerts need attention.</p>
        </div>
      ) : (
        <ul className="divide-y divide-[var(--border)]" aria-label="Portfolio items needing attention">
          {queue.items.slice(0, 8).map(item => (
            <li key={item.id}>
              <Link href={item.href} className="flex items-center justify-between gap-4 px-5 py-3.5 transition-colors hover:bg-[var(--surface-2)] sm:px-6">
                <div className="min-w-0">
                  <p className="truncate text-sm font-medium text-[var(--text)]">{item.title}</p>
                  <div className="mt-1 flex flex-wrap items-center gap-1.5">
                    {item.reasons.map(reason => (
                      <span key={reason} className="rounded-full bg-amber-100 px-2 py-0.5 text-[11px] font-medium text-amber-800 dark:bg-amber-900/30 dark:text-amber-300">
                        {reason}
                      </span>
                    ))}
                    <span className="text-[11px] text-[var(--text-3)]">{item.kind === 'project' ? 'Project' : 'Supplier'}</span>
                  </div>
                </div>
                <div className="flex shrink-0 items-center gap-2 text-xs text-[var(--text-3)]">
                  {item.date ? formatDate(item.date) : null}
                  <ChevronRight className="h-4 w-4" aria-hidden="true" />
                </div>
              </Link>
            </li>
          ))}
        </ul>
      )}
    </Card>
  )
}

function Summary({
  label,
  value,
  icon: Icon,
}: {
  label: string
  value: number
  icon: typeof TriangleAlert
}) {
  return (
    <div className="flex items-center gap-3 border-b border-[var(--border)] px-5 py-3 last:border-b-0 sm:border-b-0 sm:border-r sm:last:border-r-0 sm:px-6">
      <Icon className="h-4 w-4 text-[var(--brand-ink)]" aria-hidden="true" />
      <div>
        <p className="text-lg font-semibold tabular-nums text-[var(--text)]">{value}</p>
        <p className="text-[11px] text-[var(--text-3)]">{label}</p>
      </div>
    </div>
  )
}
