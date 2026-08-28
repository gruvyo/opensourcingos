import test from "node:test"
import assert from "node:assert/strict"
import nextConfig from "../next.config.ts"
import { createSecurityHeaders } from "../lib/security-headers.ts"

test("applies security headers to every route, including authenticated pages", async () => {
  assert.equal(typeof nextConfig.headers, "function")
  const rules = await nextConfig.headers!()
  assert.equal(rules.some((rule) => rule.source === "/:path*"), true)
})

test("prevents framing and constrains executable browser content", () => {
  const headers = new Map(createSecurityHeaders("production").map(({ key, value }) => [key, value]))
  assert.equal(headers.get("X-Frame-Options"), "DENY")
  assert.match(headers.get("Content-Security-Policy") ?? "", /frame-ancestors 'none'/)
  assert.match(headers.get("Content-Security-Policy") ?? "", /object-src 'none'/)
  assert.match(headers.get("Content-Security-Policy") ?? "", /upgrade-insecure-requests/)
  assert.equal(headers.get("X-Content-Type-Options"), "nosniff")
  assert.equal(headers.get("Referrer-Policy"), "strict-origin-when-cross-origin")
  assert.equal(headers.get("Permissions-Policy"), "camera=(), geolocation=(), microphone=()")
  assert.match(headers.get("Strict-Transport-Security") ?? "", /max-age=63072000/)
})

test("allows local Supabase connections only in development", () => {
  const development = createSecurityHeaders("development").find(({ key }) => key === "Content-Security-Policy")?.value ?? ""
  const production = createSecurityHeaders("production").find(({ key }) => key === "Content-Security-Policy")?.value ?? ""
  assert.match(development, /http:\/\/127\.0\.0\.1:\*/)
  assert.doesNotMatch(production, /http:\/\/127\.0\.0\.1/)
})
