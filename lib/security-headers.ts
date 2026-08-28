export function createSecurityHeaders(nodeEnv = process.env.NODE_ENV) {
  const developmentConnections = nodeEnv === "development"
    ? " http://localhost:* http://127.0.0.1:* ws://localhost:* ws://127.0.0.1:*"
    : ""
  const upgradeInsecureRequests = nodeEnv === "development" ? "" : "; upgrade-insecure-requests"
  const contentSecurityPolicy = [
    "default-src 'self'",
    "base-uri 'self'",
    "object-src 'none'",
    "frame-ancestors 'none'",
    "form-action 'self'",
    "script-src 'self' 'unsafe-inline'",
    "style-src 'self' 'unsafe-inline'",
    "img-src 'self' blob: data: https:",
    "font-src 'self' data:",
    `connect-src 'self' https: wss:${developmentConnections}`,
    "manifest-src 'self'",
    "worker-src 'self' blob:",
  ].join("; ") + upgradeInsecureRequests

  return [
    { key: "Content-Security-Policy", value: contentSecurityPolicy },
    { key: "X-Frame-Options", value: "DENY" },
    { key: "X-Content-Type-Options", value: "nosniff" },
    { key: "Referrer-Policy", value: "strict-origin-when-cross-origin" },
    { key: "Permissions-Policy", value: "camera=(), geolocation=(), microphone=()" },
    { key: "Strict-Transport-Security", value: "max-age=63072000; includeSubDomains; preload" },
  ]
}
