import assert from 'node:assert/strict'
import test from 'node:test'
import { resolveLoadedRows } from '../lib/load-state.ts'

test('a successful empty read is an empty state', () => {
  assert.deepEqual(resolveLoadedRows('Offers', { data: [], error: null }), {
    status: 'loaded',
    rows: [],
  })
})

test('a failed read is an error state, never an empty list', () => {
  assert.deepEqual(resolveLoadedRows('Offers', { data: null, error: { message: 'network unavailable' } }), {
    status: 'error',
    message: 'Offers could not be loaded (network unavailable).',
  })
})

test('a null result without an explicit error still fails closed', () => {
  const result = resolveLoadedRows('Baselines', { data: null, error: null })
  assert.equal(result.status, 'error')
})
