export type ReadError = { message?: string } | null | undefined

export type LoadedRows<T> =
  | { status: 'loaded'; rows: T[] }
  | { status: 'error'; message: string }

/** A failed or indeterminate read must never be converted into an empty list. */
export function resolveLoadedRows<T>(
  subject: string,
  result: { data: T[] | null; error: ReadError },
): LoadedRows<T> {
  if (result.error) {
    return {
      status: 'error',
      message: `${subject} could not be loaded (${result.error.message || 'unknown read error'}).`,
    }
  }
  if (!Array.isArray(result.data)) {
    return {
      status: 'error',
      message: `${subject} could not be loaded because the database returned no readable result.`,
    }
  }
  return { status: 'loaded', rows: result.data }
}
