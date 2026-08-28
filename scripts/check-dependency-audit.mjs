import { readFile } from "node:fs/promises"
import { spawnSync } from "node:child_process"
import { evaluateAudit } from "./dependency-audit.mjs"

const exceptionPath = new URL("../config/dependency-audit-exceptions.json", import.meta.url)

try {
  const exceptions = JSON.parse(await readFile(exceptionPath, "utf8"))
  const audit = spawnSync("npm", ["audit", "--omit=dev", "--json"], {
    encoding: "utf8",
    maxBuffer: 10 * 1024 * 1024,
  })

  if (audit.error) throw audit.error

  let report
  try {
    report = JSON.parse(audit.stdout)
  } catch {
    throw new Error(`npm audit did not return valid JSON. ${audit.stderr.trim()}`)
  }

  const { blocked, excepted } = evaluateAudit(report, exceptions)

  for (const advisory of excepted) {
    console.warn(`EXCEPTED ${advisory.id} (${advisory.packageName}): ${advisory.title ?? advisory.url ?? "advisory"}`)
  }

  if (blocked.length > 0) {
    for (const advisory of blocked) {
      console.error(`BLOCKED ${advisory.id} (${advisory.packageName}, ${advisory.severity}): ${advisory.title ?? advisory.url ?? "advisory"}`)
    }
    process.exitCode = 1
  } else {
    console.log("Production dependency audit passed: no unexcepted moderate, high, or critical advisories.")
  }
} catch (error) {
  console.error(`Production dependency audit could not be verified: ${error instanceof Error ? error.message : error}`)
  process.exitCode = 1
}
