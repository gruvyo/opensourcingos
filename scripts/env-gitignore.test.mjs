import test from "node:test"
import assert from "node:assert/strict"
import { spawnSync } from "node:child_process"

function isIgnored(path) {
  return spawnSync("git", ["check-ignore", "--no-index", "--quiet", path]).status === 0
}

test("ignores every Next.js environment variant, including a bare .env", () => {
  for (const path of [".env", ".env.local", ".env.development", ".env.production", ".env.test.local"]) {
    assert.equal(isIgnored(path), true, `${path} must be ignored`)
  }
})

test("keeps the public environment template committable", () => {
  assert.equal(isIgnored(".env.example"), false)
})
