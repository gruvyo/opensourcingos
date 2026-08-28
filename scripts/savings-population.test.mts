import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import test from 'node:test'
import {
  isSourcingProject,
  sourcingSavingsPopulation,
} from '../lib/savings-population.ts'

test('keeps only Sourcing Project savings and their exact children', () => {
  const population = sourcingSavingsPopulation(
    [
      { id: 'sourcing', project_type: 'Sourcing' },
      { id: 'support', project_type: 'Support' },
      { id: 'legacy', project_type: null },
    ],
    [
      { id: 'sourcing-calc', event_id: 'sourcing', amount: 100 },
      { id: 'support-calc', event_id: 'support', amount: 999 },
      { id: 'legacy-calc', event_id: 'legacy', amount: 50 },
      { id: 'orphan-calc', event_id: null, amount: 777 },
    ],
    [
      { savings_calculation_id: 'sourcing-calc', amount: 100 },
      { savings_calculation_id: 'support-calc', amount: 999 },
      { savings_calculation_id: 'orphan-calc', amount: 777 },
    ],
    [
      { event_id: 'sourcing', amount: 100 },
      { event_id: 'support', amount: 999 },
      { event_id: null, amount: 777 },
    ],
  )

  assert.deepEqual(population.events.map(row => row.id), ['sourcing', 'legacy'])
  assert.deepEqual(population.calculations.map(row => row.id), ['sourcing-calc', 'legacy-calc'])
  assert.deepEqual(population.periodRows.map(row => row.savings_calculation_id), ['sourcing-calc'])
  assert.deepEqual(population.realizationRows.map(row => row.event_id), ['sourcing'])
})

test('treats historical null Project Type as Sourcing, never Support', () => {
  assert.equal(isSourcingProject({ id: 'legacy', project_type: null }), true)
  assert.equal(isSourcingProject({ id: 'sourcing', project_type: 'Sourcing' }), true)
  assert.equal(isSourcingProject({ id: 'support', project_type: 'Support' }), false)
})

const read = (path: string) => readFile(new URL(`../${path}`, import.meta.url), 'utf8')

test('all portfolio money surfaces apply the shared population boundary', async () => {
  const [dashboard, savings, reports, realization, supplier, eventDetail] = await Promise.all([
    read('app/dashboard/page.tsx'),
    read('app/savings/page.tsx'),
    read('components/reports-view.tsx'),
    read('app/realization/page.tsx'),
    read('app/suppliers/[supplierId]/page.tsx'),
    read('components/event-detail.tsx'),
  ])

  assert.match(dashboard, /sourcingSavingsPopulation\(/)
  assert.match(savings, /sourcingSavingsPopulation\(/)
  assert.match(reports, /sourcingSavingsPopulation\(/)
  assert.match(realization, /isSourcingProject\(event\)/)
  assert.match(supplier, /savingsEventIds[\s\S]*project_type \|\| 'Sourcing'/)
  assert.match(eventDetail, /const SUPPORT_TABS = \[[\s\S]*overview[\s\S]*updates[\s\S]*\]/)
  assert.match(eventDetail, /!isSupport && activeTab === 'calculations'/)
  assert.match(eventDetail, /!isSupport && activeTab === 'schedule'/)
  assert.match(eventDetail, /!isSupport && activeTab === 'realization'/)
})
