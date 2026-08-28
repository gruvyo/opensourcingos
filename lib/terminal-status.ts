export type TerminalStatusOption = {
  label: string
  project_type: string | null
  is_terminal: boolean
  requires_savings_disposition?: boolean
}

function statusKey(status: string | null | undefined, projectType: string | null | undefined): string {
  return `${projectType || ''}\u0000${(status || '').trim().toLocaleLowerCase('en-US')}`
}

/** Terminality belongs to the managed option row, so it survives a rename. */
export function isTerminalStatus(
  status: string | null | undefined,
  projectType: string | null | undefined,
  options: TerminalStatusOption[],
): boolean {
  if (!status || !projectType) return false
  const key = statusKey(status, projectType)
  return options.some(option => option.is_terminal && statusKey(option.label, option.project_type) === key)
}

/** A Sourcing completion outcome needs an explicit executed/no-savings decision. */
export function statusRequiresSavingsDisposition(
  status: string | null | undefined,
  projectType: string | null | undefined,
  options: TerminalStatusOption[],
): boolean {
  if (!status || !projectType) return false
  const key = statusKey(status, projectType)
  return options.some(option => (
    option.requires_savings_disposition === true
    && statusKey(option.label, option.project_type) === key
  ))
}
