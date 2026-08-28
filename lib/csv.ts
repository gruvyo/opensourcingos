const FORMULA_PREFIX = /^[\t\r\n]|^\s*[=+\-@]/

/** Quote a CSV cell and neutralize user-controlled spreadsheet formulas. */
export function csvCell(value: string | number | null, neutralizeFormula = typeof value === 'string') {
  const raw = String(value ?? '')
  const safe = neutralizeFormula && FORMULA_PREFIX.test(raw) ? `'${raw}` : raw
  return `"${safe.replace(/"/g, '""')}"`
}
