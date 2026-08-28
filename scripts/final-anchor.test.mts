import assert from 'node:assert/strict'
import test from 'node:test'
import { validateFinalAnchor } from '../lib/final-anchor.ts'

test('blank Final is rejected rather than coerced to zero', () => {
  assert.equal(validateFinalAnchor('').status, 'error')
  assert.equal(validateFinalAnchor('   ').status, 'error')
  assert.equal(validateFinalAnchor(null).status, 'error')
})

test('non-finite and negative Final values are rejected', () => {
  assert.equal(validateFinalAnchor('not money').status, 'error')
  assert.equal(validateFinalAnchor(Number.POSITIVE_INFINITY).status, 'error')
  assert.equal(validateFinalAnchor('-0.01').status, 'error')
  assert.equal(validateFinalAnchor('1e100').status, 'error')
})

test('sub-cent Final values are rejected instead of rounded', () => {
  assert.equal(validateFinalAnchor('12.345').status, 'error')
})

test('a genuine zero requires explicit confirmation', () => {
  const firstPass = validateFinalAnchor('0.00')
  assert.equal(firstPass.status, 'confirm-zero')
  assert.equal(firstPass.value, 0)

  assert.deepEqual(validateFinalAnchor('0.00', { zeroConfirmed: true }), {
    status: 'valid',
    value: 0,
    message: null,
  })
})

test('a valid Final is returned at exact cent precision', () => {
  assert.deepEqual(validateFinalAnchor('1250.50'), {
    status: 'valid',
    value: 1250.5,
    message: null,
  })
})
