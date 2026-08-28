/**
 * Serialize a local calendar date without converting it through UTC.
 *
 * Database date columns represent calendar dates, not instants. Using
 * Date#toISOString here can move the value to the previous or next day when
 * the user's local timezone differs from UTC.
 */
export function localDateKey(date: Date): string {
  const year = date.getFullYear()
  const month = String(date.getMonth() + 1).padStart(2, '0')
  const day = String(date.getDate()).padStart(2, '0')
  return `${year}-${month}-${day}`
}
