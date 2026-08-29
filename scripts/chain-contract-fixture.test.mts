import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'
import { renderChainContractFixture } from './chain-contract-fixture.ts'

test('the pgTAP savings-chain fixture is generated from the TypeScript source of truth', () => {
  const committed = readFileSync(
    new URL('../supabase/tests/database/generated_chain_contract.test.sql', import.meta.url),
    'utf8',
  )
  assert.equal(committed, renderChainContractFixture())
})
