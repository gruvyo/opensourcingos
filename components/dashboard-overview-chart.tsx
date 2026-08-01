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
import { formatCurrency } from '@/lib/utils'

export type DashboardTrendPoint = {
  year: number
  total: number
  realized: number
}

const AXIS_TICK = { fontSize: 11, fill: '#94a3b8' }
const GRID_STROKE = 'rgba(148,163,184,0.18)'
const AXIS_STROKE = 'rgba(148,163,184,0.35)'

function compactCurrency(value: number): string {
  const amount = Number(value) || 0
  if (Math.abs(amount) >= 1_000_000) return `$${(amount / 1_000_000).toFixed(1)}m`
  if (Math.abs(amount) >= 1_000) return `$${(amount / 1_000).toFixed(0)}k`
  return formatCurrency(amount)
}

export function DashboardOverviewChart({
  data,
  selectedYear,
}: {
  data: DashboardTrendPoint[]
  selectedYear: number | null
}) {
  if (data.length === 0) {
    return (
      <div className="grid h-64 place-items-center text-sm text-[var(--text-3)]">
        Savings will appear here once projects have reporting dates.
      </div>
    )
  }

  return (
    <div className="h-64 w-full" aria-label="Total and realized savings by fiscal year">
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
            formatter={value => formatCurrency(Number(value) || 0)}
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
            dataKey="total"
            name="Total savings"
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
            dataKey="realized"
            name="Realized savings"
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
