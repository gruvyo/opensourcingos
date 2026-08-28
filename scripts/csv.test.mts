import test from 'node:test'
import assert from 'node:assert/strict'
import { csvCell } from '../lib/csv.ts'

test('neutralizes spreadsheet formulas while preserving valid CSV quoting', () => {
  assert.equal(csvCell('=HYPERLINK("https://example.com")'), '"\'=HYPERLINK(""https://example.com"")"')
  assert.equal(csvCell('+cmd'), '"\'+cmd"')
  assert.equal(csvCell('-cmd'), '"\'-cmd"')
  assert.equal(csvCell('@SUM(A1:A2)'), '"\'@SUM(A1:A2)"')
  assert.equal(csvCell('  =1+1'), '"\'  =1+1"')
  assert.equal(csvCell('\t=1+1'), '"\'\t=1+1"')
})

test('leaves ordinary text and trusted negative money unchanged', () => {
  assert.equal(csvCell('Normal "Supplier"'), '"Normal ""Supplier"""')
  assert.equal(csvCell(-12.34), '"-12.34"')
  assert.equal(csvCell('-12.34', false), '"-12.34"')
})
