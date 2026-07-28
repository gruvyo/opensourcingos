'use client'

import {
  BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer,
  PieChart, Pie, Cell, Legend,
} from 'recharts'
import { formatCurrency } from '@/lib/utils'
import { Card } from '@/components/ui/card'

const COLORS = ['#6366f1', '#10b981', '#f59e0b', '#ef4444', '#8b5cf6', '#ec4899', '#06b6d4', '#84cc16']

// Neutral colours that stay legible on BOTH light and dark grounds.
const AXIS_TICK = { fontSize: 11, fill: '#94a3b8' }
const GRID_STROKE = 'rgba(148,163,184,0.18)'
const AXIS_STROKE = 'rgba(148,163,184,0.35)'
const TOOLTIP_STYLE = {
  background: 'var(--surface)',
  border: '1px solid var(--border)',
  borderRadius: 8,
  fontSize: 12,
  color: 'var(--text)',
}

function currencyFormatter(value: any): string {
  return formatCurrency(Number(value) || 0)
}

function compactFormatter(value: any): string {
  const num = Number(value) || 0
  return `$${(num / 1000).toFixed(0)}k`
}

const titleClass = 'mb-4 text-sm font-semibold uppercase tracking-wider text-[var(--text-3)]'

export function SavingsByCategoryChart({ data }: { data: { name: string; value: number }[] }) {
  if (!data || data.length === 0) {
    return <EmptyChart message="No savings data by category yet" />
  }
  return (
    <Card className="p-6">
      <h3 className={titleClass}>Savings by Category</h3>
      <ResponsiveContainer width="100%" height={300}>
        <BarChart data={data} margin={{ top: 10, right: 10, left: 0, bottom: 0 }}>
          <CartesianGrid strokeDasharray="3 3" stroke={GRID_STROKE} />
          <XAxis dataKey="name" tick={AXIS_TICK} stroke={AXIS_STROKE} interval={0} angle={-20} textAnchor="end" height={60} />
          <YAxis tick={AXIS_TICK} stroke={AXIS_STROKE} tickFormatter={compactFormatter} />
          <Tooltip formatter={currencyFormatter} contentStyle={TOOLTIP_STYLE} labelStyle={{ color: 'var(--text)' }} itemStyle={{ color: 'var(--text-2)' }} cursor={{ fill: 'rgba(148,163,184,0.12)' }} />
          <Bar dataKey="value" fill="#6366f1" radius={[4, 4, 0, 0]} />
        </BarChart>
      </ResponsiveContainer>
    </Card>
  )
}

export function EventsByStatusChart({ data }: { data: { name: string; value: number }[] }) {
  if (!data || data.length === 0) {
    return <EmptyChart message="No events data yet" />
  }
  return (
    <Card className="p-6">
      <h3 className={titleClass}>Events by Status</h3>
      <ResponsiveContainer width="100%" height={300}>
        <PieChart>
          <Pie
            data={data}
            cx="50%"
            cy="50%"
            labelLine={false}
            label={(entry: any) => `${entry.name}: ${entry.value}`}
            outerRadius={80}
            fill="#8884d8"
            dataKey="value"
          >
            {data.map((_, index) => (
              <Cell key={`cell-${index}`} fill={COLORS[index % COLORS.length]} />
            ))}
          </Pie>
          <Tooltip contentStyle={TOOLTIP_STYLE} labelStyle={{ color: 'var(--text)' }} itemStyle={{ color: 'var(--text-2)' }} />
        </PieChart>
      </ResponsiveContainer>
    </Card>
  )
}

export function SavingsByTypeChart({ data }: { data: { name: string; value: number }[] }) {
  if (!data || data.length === 0) {
    return <EmptyChart message="No savings type data yet" />
  }
  return (
    <Card className="p-6">
      <h3 className={titleClass}>Savings by Type</h3>
      <ResponsiveContainer width="100%" height={300}>
        <BarChart data={data} layout="vertical" margin={{ top: 10, right: 10, left: 80, bottom: 0 }}>
          <CartesianGrid strokeDasharray="3 3" stroke={GRID_STROKE} />
          <XAxis type="number" tick={AXIS_TICK} stroke={AXIS_STROKE} tickFormatter={compactFormatter} />
          <YAxis type="category" dataKey="name" tick={AXIS_TICK} stroke={AXIS_STROKE} width={100} />
          <Tooltip formatter={currencyFormatter} contentStyle={TOOLTIP_STYLE} labelStyle={{ color: 'var(--text)' }} itemStyle={{ color: 'var(--text-2)' }} cursor={{ fill: 'rgba(148,163,184,0.12)' }} />
          <Bar dataKey="value" fill="#10b981" radius={[0, 4, 4, 0]} />
        </BarChart>
      </ResponsiveContainer>
    </Card>
  )
}

/**
 * Savings by fiscal year. Fed from portfolioByYear(), so it books whole months
 * exactly like the Schedule tab — the two can no longer disagree.
 *
 * `selectedYear` dims the years that are filtered out rather than removing
 * them, because a single bar with nothing beside it tells you nothing about
 * whether that year was good.
 */
export function SavingsByYearChart({
  data,
  selectedYear,
}: {
  data: { year: number; reduction: number | null; avoidance: number; total: number }[]
  selectedYear?: number | null
}) {
  if (!data || data.length === 0) {
    return <EmptyChart message="No savings placed in a year yet" />
  }
  const rows = data.map(d => ({
    year: String(d.year),
    // A null reduction means not applicable. Charting it as 0 is the honest
    // option here — a bar cannot render "n/a" — and the table beside this
    // chart carries the distinction.
    reduction: d.reduction ?? 0,
    avoidance: d.avoidance,
    total: d.total,
    dim: selectedYear != null && d.year !== selectedYear,
  }))
  const opacity = (i: number) => (rows[i].dim ? 0.25 : 1)

  return (
    <Card className="p-6">
      <h3 className={titleClass}>
        Savings by Fiscal Year{selectedYear != null && <span className="ml-2 normal-case text-[var(--text-2)]">· FY{selectedYear} highlighted</span>}
      </h3>
      <ResponsiveContainer width="100%" height={350}>
        <BarChart data={rows} margin={{ top: 10, right: 10, left: 0, bottom: 0 }}>
          <CartesianGrid strokeDasharray="3 3" stroke={GRID_STROKE} />
          <XAxis dataKey="year" tick={{ fontSize: 12, fill: '#94a3b8' }} stroke={AXIS_STROKE} />
          <YAxis tick={AXIS_TICK} stroke={AXIS_STROKE} tickFormatter={compactFormatter} />
          <Tooltip formatter={currencyFormatter} contentStyle={TOOLTIP_STYLE} labelStyle={{ color: 'var(--text)' }} itemStyle={{ color: 'var(--text-2)' }} cursor={{ fill: 'rgba(148,163,184,0.12)' }} />
          <Legend wrapperStyle={{ fontSize: 12, color: 'var(--text-2)' }} />
          <Bar dataKey="reduction" name="Cost Reduction" fill="#6366f1" radius={[4, 4, 0, 0]}>
            {rows.map((_, i) => <Cell key={i} fillOpacity={opacity(i)} />)}
          </Bar>
          <Bar dataKey="avoidance" name="Cost Avoidance" fill="#f59e0b" radius={[4, 4, 0, 0]}>
            {rows.map((_, i) => <Cell key={i} fillOpacity={opacity(i)} />)}
          </Bar>
          <Bar dataKey="total" name="Total Savings" fill="#10b981" radius={[4, 4, 0, 0]}>
            {rows.map((_, i) => <Cell key={i} fillOpacity={opacity(i)} />)}
          </Bar>
        </BarChart>
      </ResponsiveContainer>
    </Card>
  )
}

function EmptyChart({ message }: { message: string }) {
  return (
    <Card className="p-6">
      <h3 className={titleClass}>Chart</h3>
      <div className="flex h-[300px] items-center justify-center text-sm text-[var(--text-3)]">{message}</div>
    </Card>
  )
}
