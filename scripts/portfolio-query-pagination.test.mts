import assert from 'node:assert/strict'
import test from 'node:test'

import { fetchPortfolioRows } from '../lib/supabase/portfolio-query.ts'

function loaderFor<Row>(rows: Row[], calls: Array<[number, number]>) {
  return async (from: number, to: number) => {
    calls.push([from, to])
    return {
      data: rows.slice(from, to + 1),
      error: null,
      count: rows.length,
    }
  }
}

test('loads every row across deterministic pages', async () => {
  const rows = Array.from({ length: 2_500 }, (_, id) => ({ id }))
  const calls: Array<[number, number]> = []

  const result = await fetchPortfolioRows('Projects', loaderFor(rows, calls))

  assert.equal(result.error, null)
  assert.deepEqual(result.data, rows)
  assert.deepEqual(calls, [[0, 999], [1_000, 1_999], [2_000, 2_999]])
})

test('handles an empty portfolio with one request', async () => {
  const calls: Array<[number, number]> = []
  const result = await fetchPortfolioRows('Projects', loaderFor([], calls))

  assert.deepEqual(result, { data: [], error: null })
  assert.deepEqual(calls, [[0, 999]])
})

test('discards partial data when a later page fails', async () => {
  const result = await fetchPortfolioRows('Savings calculations', async (from, to) => {
    if (from === 0) {
      return {
        data: Array.from({ length: to - from + 1 }, (_, id) => ({ id })),
        error: null,
        count: 1_001,
      }
    }
    return { data: null, error: { message: 'database unavailable' }, count: 1_001 }
  })

  assert.deepEqual(result, { data: [], error: { message: 'database unavailable' } })
})

test('fails visibly before loading a portfolio above the safety ceiling', async () => {
  let calls = 0
  const result = await fetchPortfolioRows('Savings periods', async () => {
    calls++
    return { data: [{ id: 1 }], error: null, count: 50_001 }
  })

  assert.equal(calls, 1)
  assert.deepEqual(result.data, [])
  assert.match(result.error?.message ?? '', /above the 50,000-row reporting limit/)
})

test('requires an exact count so truncated pages cannot look complete', async () => {
  const result = await fetchPortfolioRows('Suppliers', async () => ({
    data: [{ id: 1 }],
    error: null,
    count: null,
  }))

  assert.deepEqual(result.data, [])
  assert.match(result.error?.message ?? '', /did not return an exact row count/)
})

test('detects a portfolio changing between pages', async () => {
  const result = await fetchPortfolioRows('Projects', async (from, to) => ({
    data: Array.from({ length: to - from + 1 }, (_, id) => ({ id: from + id })),
    error: null,
    count: from === 0 ? 1_001 : 1_002,
  }))

  assert.deepEqual(result.data, [])
  assert.match(result.error?.message ?? '', /changed while it was loading/)
})
