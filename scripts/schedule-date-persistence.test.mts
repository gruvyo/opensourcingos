import test from 'node:test'
import assert from 'node:assert/strict'
import { localDateKey } from '../lib/date-key.ts'

function withTimeZone(timeZone: string, assertion: () => void) {
  const original = process.env.TZ
  try {
    process.env.TZ = timeZone
    assertion()
  } finally {
    if (original === undefined) delete process.env.TZ
    else process.env.TZ = original
  }
}

test('persists a locally selected date east of UTC without moving it to the prior day', () => {
  withTimeZone('Pacific/Auckland', () => {
    const selectedDate = new Date(2026, 7, 31)
    assert.equal(selectedDate.toISOString().slice(0, 10), '2026-08-30')
    assert.equal(localDateKey(selectedDate), '2026-08-31')
  })
})

test('persists the same local calendar date west of UTC', () => {
  withTimeZone('America/Los_Angeles', () => {
    assert.equal(localDateKey(new Date(2026, 7, 31)), '2026-08-31')
  })
})
