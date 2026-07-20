'use client'

import { useState } from 'react'
import { createClient } from '@/lib/supabase/client'
import { Plus, Trash2, AlertTriangle, CheckCircle } from 'lucide-react'
import { formatDate } from '@/lib/utils'

type ScopeLine = {
  id: string
  line_number: number
  item_service_name: string
  item_description: string | null
  uom: string | null
  baseline_quantity: number | null
  forecast_quantity: number | null
  final_quantity: number | null
  scope_change_flag: boolean
  scope_change_description: string | null
  business_equivalency_confirmed: boolean
  category: { category_name: string } | null
}

const UOM_OPTIONS = [
  'Each', 'License', 'License-Month', 'License-Year', 'Hour', 'Day',
  'Week', 'Month', 'Year', 'FTE', 'Project', 'SOW', 'Location',
  'Shipment', 'Mile', 'Pound', 'Kilogram', 'Pallet', 'Case',
  'Unit', 'Seat', 'Subscription', 'Transaction', 'Gigabyte', 'Terabyte'
]

export function ScopeLinesTab({ eventId, scopeLines: initialLines }: { eventId: string; scopeLines: ScopeLine[] }) {
  const [scopeLines, setScopeLines] = useState(initialLines)
  const [showForm, setShowForm] = useState(false)
  const [loading, setLoading] = useState(false)
  const supabase = createClient()

  const [newLine, setNewLine] = useState({
    item_service_name: '',
    item_description: '',
    uom: '',
    baseline_quantity: '',
    forecast_quantity: '',
    final_quantity: '',
    scope_change_flag: false,
    scope_change_description: '',
    business_equivalency_confirmed: false,
  })

  const handleAdd = async (e: React.FormEvent) => {
    e.preventDefault()
    setLoading(true)

    const { data: { user } } = await supabase.auth.getUser()
    if (!user) { setLoading(false); return }

    const { data: profile } = await supabase
      .from('profiles')
      .select('organization_id')
      .eq('id', user.id)
      .single()

    const lineNumber = scopeLines.length + 1

    const { data, error } = await supabase
      .from('event_scope_lines')
      .insert({
        organization_id: profile?.organization_id,
        event_id: eventId,
        line_number: lineNumber,
        item_service_name: newLine.item_service_name,
        item_description: newLine.item_description || null,
        uom: newLine.uom || null,
        baseline_quantity: newLine.baseline_quantity ? parseFloat(newLine.baseline_quantity) : null,
        forecast_quantity: newLine.forecast_quantity ? parseFloat(newLine.forecast_quantity) : null,
        final_quantity: newLine.final_quantity ? parseFloat(newLine.final_quantity) : null,
        scope_change_flag: newLine.scope_change_flag,
        scope_change_description: newLine.scope_change_description || null,
        business_equivalency_confirmed: newLine.business_equivalency_confirmed,
      })
      .select(`
        *,
        category:categories(category_name)
      `)
      .single()

    if (!error && data) {
      setScopeLines([...scopeLines, data])
      setNewLine({
        item_service_name: '', item_description: '', uom: '',
        baseline_quantity: '', forecast_quantity: '', final_quantity: '',
        scope_change_flag: false, scope_change_description: '',
        business_equivalency_confirmed: false,
      })
      setShowForm(false)
    }
    setLoading(false)
  }

  const handleDelete = async (id: string) => {
    const { error } = await supabase.from('event_scope_lines').delete().eq('id', id)
    if (!error) {
      setScopeLines(scopeLines.filter(l => l.id !== id))
    }
  }

  const inputClass = 'block w-full rounded-lg border border-gray-300 px-3 py-2 text-sm focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500'
  const labelClass = 'block text-xs font-medium text-gray-600 mb-1'

  return (
    <div>
      <div className="mb-4 flex items-center justify-between">
        <div>
          <h3 className="text-lg font-semibold text-gray-900">Scope Lines</h3>
          <p className="text-sm text-gray-600">Define what is being sourced, line by line</p>
        </div>
        <button
          onClick={() => setShowForm(!showForm)}
          className="flex items-center gap-2 rounded-lg bg-indigo-600 px-4 py-2 text-sm font-medium text-white hover:bg-indigo-700"
        >
          <Plus className="h-4 w-4" />
          Add Scope Line
        </button>
      </div>

      {showForm && (
        <form onSubmit={handleAdd} className="mb-6 rounded-lg border border-indigo-200 bg-indigo-50 p-6">
          <h4 className="mb-4 font-medium text-gray-900">New Scope Line</h4>
          <div className="grid grid-cols-1 gap-4 md:grid-cols-3">
            <div className="md:col-span-2">
              <label className={labelClass}>Item / Service Name *</label>
              <input type="text" required value={newLine.item_service_name}
                onChange={(e) => setNewLine({ ...newLine, item_service_name: e.target.value })}
                className={inputClass} placeholder="e.g. CRM Enterprise License" />
            </div>
            <div>
              <label className={labelClass}>UOM</label>
              <select value={newLine.uom}
                onChange={(e) => setNewLine({ ...newLine, uom: e.target.value })}
                className={inputClass}>
                <option value="">Select...</option>
                {UOM_OPTIONS.map((u) => <option key={u} value={u}>{u}</option>)}
              </select>
            </div>
            <div className="md:col-span-3">
              <label className={labelClass}>Description</label>
              <input type="text" value={newLine.item_description}
                onChange={(e) => setNewLine({ ...newLine, item_description: e.target.value })}
                className={inputClass} placeholder="Brief description" />
            </div>
            <div>
              <label className={labelClass}>Baseline Qty</label>
              <input type="number" step="0.01" value={newLine.baseline_quantity}
                onChange={(e) => setNewLine({ ...newLine, baseline_quantity: e.target.value })}
                className={inputClass} />
            </div>
            <div>
              <label className={labelClass}>Forecast Qty</label>
              <input type="number" step="0.01" value={newLine.forecast_quantity}
                onChange={(e) => setNewLine({ ...newLine, forecast_quantity: e.target.value })}
                className={inputClass} />
            </div>
            <div>
              <label className={labelClass}>Final Qty</label>
              <input type="number" step="0.01" value={newLine.final_quantity}
                onChange={(e) => setNewLine({ ...newLine, final_quantity: e.target.value })}
                className={inputClass} />
            </div>
            <div className="md:col-span-3 flex items-center gap-6">
              <label className="flex items-center gap-2 text-sm text-gray-700">
                <input type="checkbox" checked={newLine.scope_change_flag}
                  onChange={(e) => setNewLine({ ...newLine, scope_change_flag: e.target.checked })}
                  className="rounded" />
                Scope change flag
              </label>
              <label className="flex items-center gap-2 text-sm text-gray-700">
                <input type="checkbox" checked={newLine.business_equivalency_confirmed}
                  onChange={(e) => setNewLine({ ...newLine, business_equivalency_confirmed: e.target.checked })}
                  className="rounded" />
                Business equivalency confirmed
              </label>
            </div>
            {newLine.scope_change_flag && (
              <div className="md:col-span-3">
                <label className={labelClass}>Scope Change Description</label>
                <input type="text" value={newLine.scope_change_description}
                  onChange={(e) => setNewLine({ ...newLine, scope_change_description: e.target.value })}
                  className={inputClass} placeholder="Explain the scope change" />
              </div>
            )}
          </div>
          <div className="mt-4 flex justify-end gap-2">
            <button type="button" onClick={() => setShowForm(false)}
              className="rounded-lg border border-gray-300 px-4 py-2 text-sm font-medium text-gray-700 hover:bg-gray-50">
              Cancel
            </button>
            <button type="submit" disabled={loading}
              className="rounded-lg bg-indigo-600 px-4 py-2 text-sm font-medium text-white hover:bg-indigo-700 disabled:opacity-50">
              {loading ? 'Adding...' : 'Add Line'}
            </button>
          </div>
        </form>
      )}

      {/* Scope Lines Table */}
      <div className="overflow-hidden rounded-lg border border-gray-200 bg-white shadow-sm">
        <table className="w-full">
          <thead>
            <tr className="border-b border-gray-200 bg-gray-50">
              <th className="px-4 py-3 text-left text-xs font-semibold uppercase text-gray-500">#</th>
              <th className="px-4 py-3 text-left text-xs font-semibold uppercase text-gray-500">Item / Service</th>
              <th className="px-4 py-3 text-left text-xs font-semibold uppercase text-gray-500">UOM</th>
              <th className="px-4 py-3 text-right text-xs font-semibold uppercase text-gray-500">Baseline Qty</th>
              <th className="px-4 py-3 text-right text-xs font-semibold uppercase text-gray-500">Forecast Qty</th>
              <th className="px-4 py-3 text-right text-xs font-semibold uppercase text-gray-500">Final Qty</th>
              <th className="px-4 py-3 text-center text-xs font-semibold uppercase text-gray-500">Scope Change</th>
              <th className="px-4 py-3 text-center text-xs font-semibold uppercase text-gray-500">Actions</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-gray-200">
            {scopeLines.length === 0 ? (
              <tr>
                <td colSpan={8} className="px-4 py-12 text-center text-sm text-gray-500">
                  No scope lines yet. Click "Add Scope Line" to define what's being sourced.
                </td>
              </tr>
            ) : (
              scopeLines.map((line) => (
                <tr key={line.id} className="hover:bg-gray-50">
                  <td className="px-4 py-3 text-sm text-gray-500">{line.line_number}</td>
                  <td className="px-4 py-3">
                    <div className="text-sm font-medium text-gray-900">{line.item_service_name}</div>
                    {line.item_description && (
                      <div className="text-xs text-gray-500">{line.item_description}</div>
                    )}
                  </td>
                  <td className="px-4 py-3 text-sm text-gray-600">{line.uom || '—'}</td>
                  <td className="px-4 py-3 text-right text-sm text-gray-600">{line.baseline_quantity ?? '—'}</td>
                  <td className="px-4 py-3 text-right text-sm text-gray-600">{line.forecast_quantity ?? '—'}</td>
                  <td className="px-4 py-3 text-right text-sm text-gray-600">{line.final_quantity ?? '—'}</td>
                  <td className="px-4 py-3 text-center">
                    {line.scope_change_flag ? (
                      <div className="flex flex-col items-center gap-1">
                        <AlertTriangle className="h-4 w-4 text-amber-500" />
                        {line.business_equivalency_confirmed && (
                          <CheckCircle className="h-3 w-3 text-green-500" />
                        )}
                      </div>
                    ) : (
                      <span className="text-xs text-gray-400">No</span>
                    )}
                  </td>
                  <td className="px-4 py-3 text-center">
                    <button onClick={() => handleDelete(line.id)}
                      className="text-gray-400 hover:text-red-600">
                      <Trash2 className="h-4 w-4" />
                    </button>
                  </td>
                </tr>
              ))
            )}
          </tbody>
        </table>
      </div>

      {scopeLines.length > 0 && (
        <p className="mt-3 text-sm text-gray-500">
          {scopeLines.length} scope line{scopeLines.length !== 1 ? 's' : ''}
        </p>
      )}
    </div>
  )
}
