import test from "node:test"
import assert from "node:assert/strict"
import { evaluateAudit, validateExceptions } from "./dependency-audit.mjs"

const emptyConfig = { version: 1, exceptions: [] }
const report = (vulnerabilities = {}) => ({ auditReportVersion: 2, vulnerabilities })
const direct = (severity = "moderate") => ({
  severity,
  via: [{ source: 1234, name: "example", severity, title: "Example advisory", url: "https://github.com/advisories/GHSA-AAAA-BBBB-CCCC" }],
})

test("passes a clean audit report", () => {
  assert.deepEqual(evaluateAudit(report(), emptyConfig).blocked, [])
})

test("blocks an unexcepted moderate production advisory", () => {
  const result = evaluateAudit(report({ example: direct() }), emptyConfig)
  assert.deepEqual(result.blocked.map(({ id }) => id), ["GHSA-AAAA-BBBB-CCCC"])
})

test("allows an active, documented advisory exception", () => {
  const config = {
    version: 1,
    exceptions: [{ advisoryId: "GHSA-AAAA-BBBB-CCCC", reason: "Upstream fix is pending.", expiresOn: "2026-09-30" }],
  }
  const result = evaluateAudit(report({ example: direct() }), config, new Date("2026-08-28T00:00:00Z"))
  assert.equal(result.blocked.length, 0)
  assert.equal(result.excepted.length, 1)
})

test("rejects expired exceptions even when the audit is clean", () => {
  const config = {
    version: 1,
    exceptions: [{ advisoryId: "GHSA-AAAA-BBBB-CCCC", reason: "Temporary exception.", expiresOn: "2026-08-27" }],
  }
  assert.throws(() => validateExceptions(config, new Date("2026-08-28T00:00:00Z")), /expired/)
})

test("resolves transitive npm audit vulnerability chains", () => {
  const result = evaluateAudit(
    report({ parent: { severity: "high", via: ["child"] }, child: direct("high") }),
    emptyConfig,
  )
  assert.deepEqual(result.blocked.map(({ packageName, id }) => [packageName, id]), [["child", "GHSA-AAAA-BBBB-CCCC"]])
})

test("does not block low-severity advisories", () => {
  assert.equal(evaluateAudit(report({ example: direct("low") }), emptyConfig).blocked.length, 0)
})

test("fails closed on an unsupported or incomplete audit response", () => {
  assert.throws(() => evaluateAudit({ error: { code: "ENETUNREACH" } }, emptyConfig), /supported version 2/)
})
