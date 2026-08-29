'use client'

import {
  CartesianGrid,
  Legend,
  Line,
  LineChart,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from 'recharts'
import { useWorkspaceFormat } from '@/components/workspace-format-provider'

export type DashboardTrendPoint = {
  year: number
  estimated: number
  executed: number
}

const AXIS_TICK = { fontSize: 11, fill: '#94a3b8' }
const GRID_STROKE = 'rgba(148,163,184,0.18)'
const AXIS_STROKE = 'rgba(148,163,184,0.35)'

export function DashboardOverviewChart({
  data,
  selectedYear,
}: {
  data: DashboardTrendPoint[]
  selectedYear: number | null
}) {
  const { currencyCode, locale, formatDashboardCurrency } = useWorkspaceFormat()
  const compactCurrency = (value: number): string => new Intl.NumberFormat(locale, {
    style: 'currency',
    currency: currencyCode,
    notation: 'compact',
    maximumFractionDigits: 1,
  }).format(Number(value) || 0)

  if (data.length === 0) {
    return (
      <div className="grid h-64 place-items-center text-sm text-[var(--text-3)]">
        Savings will appear here once projects have reporting dates.
      </div>
    )
  }

  return (
    <div className="h-64 w-full" aria-label="Estimated pipeline and executed savings by fiscal year">
      <ResponsiveContainer width="100%" height="100%">
        <LineChart data={data} margin={{ top: 12, right: 12, left: -12, bottom: 0 }}>
          <CartesianGrid strokeDasharray="3 3" stroke={GRID_STROKE} vertical={false} />
          <XAxis
            dataKey="year"
            tick={AXIS_TICK}
            stroke={AXIS_STROKE}
            tickFormatter={year => `FY${String(year).slice(-2)}`}
          />
          <YAxis tick={AXIS_TICK} stroke={AXIS_STROKE} tickFormatter={compactCurrency} />
          <Tooltip
            formatter={value => formatDashboardCurrency(Number(value) || 0)}
            labelFormatter={year => `Fiscal year ${year}`}
            contentStyle={{
              background: 'var(--surface)',
              border: '1px solid var(--border)',
              borderRadius: 10,
              color: 'var(--text)',
              fontSize: 12,
            }}
          />
          <Legend wrapperStyle={{ color: 'var(--text-2)', fontSize: 12 }} />
          <Line
            type="monotone"
            dataKey="executed"
            name="Executed savings"
            stroke="#4f46e5"
            strokeWidth={3}
            dot={({ cx, cy, payload }) => (
              <circle
                cx={cx}
                cy={cy}
                r={payload.year === selectedYear ? 5 : 3}
                fill={payload.year === selectedYear ? '#4f46e5' : 'var(--surface)'}
                stroke="#4f46e5"
                strokeWidth={2}
              />
            )}
            activeDot={{ r: 5 }}
          />
          <Line
            type="monotone"
            dataKey="estimated"
            name="Estimated pipeline"
            stroke="#10b981"
            strokeWidth={2}
            strokeDasharray="6 4"
            dot={false}
            activeDot={{ r: 4 }}
          />
        </LineChart>
      </ResponsiveContainer>
    </div>
  )
}
