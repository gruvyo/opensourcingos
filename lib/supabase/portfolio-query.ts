export const PORTFOLIO_PAGE_SIZE = 1_000
export const PORTFOLIO_ROW_LIMIT = 50_000

type QueryError = { message: string }

export type PortfolioPage<Row> = {
  data: Row[] | null
  error: QueryError | null
  count: number | null
}

export type PortfolioQueryResult<Row> = {
  data: Row[]
  error: QueryError | null
}

type PageLoader<Row> = (
  from: number,
  to: number,
) => PromiseLike<PortfolioPage<Row>>

type PortfolioQueryOptions = {
  pageSize?: number
  rowLimit?: number
}

function queryError(message: string): QueryError {
  return { message }
}

/**
 * Load a complete, deterministically ordered portfolio query without relying on
 * PostgREST's configured maximum-row response. Every caller must request an
 * exact count and apply a stable order before its range.
 *
 * The explicit ceiling protects server memory and response size. Reaching it
 * fails visibly instead of returning a plausible but incomplete portfolio.
 */
export async function fetchPortfolioRows<Row>(
  label: string,
  loadPage: PageLoader<Row>,
  options: PortfolioQueryOptions = {},
): Promise<PortfolioQueryResult<Row>> {
  const pageSize = Math.max(1, Math.floor(options.pageSize ?? PORTFOLIO_PAGE_SIZE))
  const rowLimit = Math.max(1, Math.floor(options.rowLimit ?? PORTFOLIO_ROW_LIMIT))
  const rows: Row[] = []
  let expectedCount: number | null = null

  while (expectedCount === null || rows.length < expectedCount) {
    const from = rows.length
    const to = Math.min(from + pageSize, rowLimit) - 1
    const page = await loadPage(from, to)

    if (page.error) return { data: [], error: page.error }
    if (page.count === null) {
      return {
        data: [],
        error: queryError(`${label} did not return an exact row count. Do not report from this page.`),
      }
    }

    if (expectedCount === null) {
      expectedCount = page.count
      if (expectedCount > rowLimit) {
        return {
          data: [],
          error: queryError(
            `${label} contains ${expectedCount.toLocaleString()} rows, above the ${rowLimit.toLocaleString()}-row reporting limit. Add narrower filters or UI pagination before reporting.`,
          ),
        }
      }
      if (expectedCount === 0) return { data: [], error: null }
    } else if (page.count !== expectedCount) {
      return {
        data: [],
        error: queryError(`${label} changed while it was loading. Refresh before reporting.`),
      }
    }

    const pageRows = page.data ?? []
    if (pageRows.length === 0) {
      return {
        data: [],
        error: queryError(`${label} stopped loading at ${rows.length.toLocaleString()} of ${expectedCount.toLocaleString()} rows. Do not report from this page.`),
      }
    }

    rows.push(...pageRows)
    if (rows.length > expectedCount) {
      return {
        data: [],
        error: queryError(`${label} returned inconsistent pagination results. Refresh before reporting.`),
      }
    }
  }

  return { data: rows, error: null }
}
