const BLOCKING_SEVERITIES = new Set(["moderate", "high", "critical"])

function advisoryId(via) {
  const ghsa = via.url?.match(/\b(GHSA-[\w-]+)\b/i)?.[1]
  return ghsa?.toUpperCase() ?? String(via.source ?? "")
}

export function validateExceptions(config, today = new Date()) {
  if (config?.version !== 1 || !Array.isArray(config.exceptions)) {
    throw new Error("Dependency audit exceptions must use version 1 and an exceptions array.")
  }

  const active = new Map()
  const todayKey = today.toISOString().slice(0, 10)

  for (const exception of config.exceptions) {
    const id = String(exception?.advisoryId ?? "").trim()
    const reason = String(exception?.reason ?? "").trim()
    const expiresOn = String(exception?.expiresOn ?? "").trim()

    if (!id || !reason || !/^\d{4}-\d{2}-\d{2}$/.test(expiresOn)) {
      throw new Error("Every dependency audit exception needs advisoryId, reason, and expiresOn (YYYY-MM-DD).")
    }
    if (active.has(id)) {
      throw new Error(`Duplicate dependency audit exception: ${id}`)
    }
    if (expiresOn < todayKey) {
      throw new Error(`Dependency audit exception ${id} expired on ${expiresOn}.`)
    }

    active.set(id, exception)
  }

  return active
}

function collectAdvisories(packageName, vulnerabilities, visited = new Set()) {
  if (visited.has(packageName)) return []
  visited.add(packageName)

  const vulnerability = vulnerabilities[packageName]
  if (!vulnerability || !Array.isArray(vulnerability.via)) return []

  return vulnerability.via.flatMap((via) => {
    if (typeof via === "string") {
      return collectAdvisories(via, vulnerabilities, visited)
    }

    const id = advisoryId(via)
    return id ? [{ id, packageName, severity: via.severity, title: via.title, url: via.url }] : []
  })
}

export function evaluateAudit(report, exceptionConfig, today = new Date()) {
  if (report?.auditReportVersion !== 2 || !report.vulnerabilities || typeof report.vulnerabilities !== "object") {
    throw new Error("npm audit did not return a supported version 2 vulnerability report.")
  }

  const exceptions = validateExceptions(exceptionConfig, today)
  const blocked = []
  const excepted = []

  for (const [packageName, vulnerability] of Object.entries(report.vulnerabilities)) {
    if (!BLOCKING_SEVERITIES.has(vulnerability.severity)) continue

    const advisories = collectAdvisories(packageName, report.vulnerabilities)
    if (advisories.length === 0) {
      blocked.push({ packageName, severity: vulnerability.severity, id: "unknown", title: "Unresolved advisory chain" })
      continue
    }

    for (const advisory of advisories) {
      if (exceptions.has(advisory.id)) {
        excepted.push(advisory)
      } else {
        blocked.push(advisory)
      }
    }
  }

  const unique = (items) => [...new Map(items.map((item) => [`${item.packageName}:${item.id}`, item])).values()]
  return { blocked: unique(blocked), excepted: unique(excepted) }
}
