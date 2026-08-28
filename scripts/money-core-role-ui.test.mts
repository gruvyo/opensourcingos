import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import test from 'node:test'

const read = (path: string) => readFile(new URL(`../${path}`, import.meta.url), 'utf8')

test('viewer-facing project tabs receive the current role and hide write controls', async () => {
  const eventDetail = await read('components/event-detail.tsx')
  for (const component of ['ScopeLinesTab', 'BaselinesTab', 'OffersTab', 'CalculationsTab']) {
    assert.match(
      eventDetail,
      new RegExp(`<${component}[^>]*currentUserRole=\\{currentProfile\\.role\\}`, 's'),
    )
  }
  assert.match(eventDetail, /const canEditMoney = currentProfile\.role === 'admin' \|\| currentProfile\.role === 'procurement_user'/)
  assert.match(eventDetail, /\{canEditMoney && \(/)
})

test('viewers cannot open the new-project form and the project list hides its create action', async () => {
  const [newPage, listPage] = await Promise.all([
    read('app/events/new/page.tsx'),
    read('app/events/page.tsx'),
  ])
  assert.match(newPage, /profile\?\.role !== 'admin' && profile\?\.role !== 'procurement_user'/)
  assert.match(newPage, /redirect\('\/events'\)/)
  assert.match(listPage, /const canCreate = profile\?\.role === 'admin' \|\| profile\?\.role === 'procurement_user'/)
  assert.match(listPage, /\{canCreate && <Link/)
})

test('browser money writes send neither actor fields nor protected realization payloads', async () => {
  const moneySources = await Promise.all([
    'components/edit-project-modal.tsx',
    'components/baselines-tab.tsx',
    'components/offers-tab.tsx',
    'components/calculations-tab.tsx',
    'components/schedule-tab.tsx',
    'components/realization-tab.tsx',
  ].map(read))
  const combined = moneySources.join('\n')
  assert.doesNotMatch(combined, /(created_by|updated_by): user(?:\?|!)?\.id/)
  assert.doesNotMatch(combined, /updated_at: new Date\(\)\.toISOString\(\)/)

  const eventForm = await read('components/event-form.tsx')
  const eventPayload = eventForm.slice(
    eventForm.indexOf('const eventData ='),
    eventForm.indexOf(".from('sourcing_events')"),
  )
  assert.doesNotMatch(eventPayload, /created_by|updated_by/)

  const realization = await read('components/realization-tab.tsx')
  assert.match(realization, /syncRealizationPeriodsAtomically\(supabase, eventId\)/)
  assert.doesNotMatch(realization, /from\('realization_periods'\)\.insert/)
})
