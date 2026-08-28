import assert from 'node:assert/strict'
import test from 'node:test'
import {
  isTerminalStatus,
  statusRequiresSavingsDisposition,
  type TerminalStatusOption,
} from '../lib/terminal-status.ts'

const options: TerminalStatusOption[] = [
  { label: 'Complete', project_type: 'Sourcing', is_terminal: true, requires_savings_disposition: true },
  { label: 'Cancelled', project_type: 'Sourcing', is_terminal: true },
  { label: 'In Progress', project_type: 'Sourcing', is_terminal: false },
  { label: 'Complete', project_type: 'Support', is_terminal: true },
]

test('uses managed metadata rather than a hard-coded label set', () => {
  assert.equal(isTerminalStatus('Complete', 'Sourcing', options), true)
  assert.equal(isTerminalStatus('In Progress', 'Sourcing', options), false)
  assert.equal(isTerminalStatus('Complete', 'Unknown', options), false)
})

test('a renamed terminal option stays terminal', () => {
  const renamed = options.map(option => option.label === 'Complete' && option.project_type === 'Sourcing'
    ? { ...option, label: 'Closed' }
    : option)

  assert.equal(isTerminalStatus('Closed', 'Sourcing', renamed), true)
  assert.equal(isTerminalStatus('Complete', 'Sourcing', renamed), false)
  assert.equal(statusRequiresSavingsDisposition('Closed', 'Sourcing', renamed), true)
})

test('a custom option honors its explicit terminal flag', () => {
  const custom = { label: 'Archived', project_type: 'Sourcing', is_terminal: true }
  assert.equal(isTerminalStatus('Archived', 'Sourcing', [...options, custom]), true)
  assert.equal(isTerminalStatus('Archived', 'Support', [...options, custom]), false)
})

test('cancelled is terminal without invoking the sourcing completion decision', () => {
  assert.equal(isTerminalStatus('Cancelled', 'Sourcing', options), true)
  assert.equal(statusRequiresSavingsDisposition('Cancelled', 'Sourcing', options), false)
})
