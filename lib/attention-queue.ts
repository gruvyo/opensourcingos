export type AttentionProject = {
  id: string
  name: string | null
  status: string | null
  dueDate: string | null
}

export type AttentionSupplier = {
  id: string
  name: string | null
  status: string | null
  risk: string | null
  nextReviewDate: string | null
}

export type AttentionItem = {
  id: string
  kind: 'project' | 'supplier'
  title: string
  href: string
  reasons: string[]
  date: string | null
  priority: number
}

export type AttentionQueue = {
  overdueProjects: number
  dueSoonProjects: number
  supplierAttention: number
  items: AttentionItem[]
}

const INACTIVE_PROJECT_STATUSES = new Set(['Cancelled', 'Complete'])
const INACTIVE_SUPPLIER_STATUSES = new Set(['Inactive'])

function addDays(dateKey: string, days: number): string {
  const date = new Date(`${dateKey}T00:00:00Z`)
  date.setUTCDate(date.getUTCDate() + days)
  return date.toISOString().slice(0, 10)
}

export function buildAttentionQueue(
  projects: AttentionProject[],
  suppliers: AttentionSupplier[],
  asOfDate: string,
  dueSoonDays = 30,
): AttentionQueue {
  const dueSoonThrough = addDays(asOfDate, dueSoonDays)
  const projectItems: AttentionItem[] = []
  const supplierItems: AttentionItem[] = []
  let overdueProjects = 0
  let dueSoonProjects = 0

  for (const project of projects) {
    if (!project.dueDate || INACTIVE_PROJECT_STATUSES.has(project.status || '')) continue

    let reason: string | null = null
    let priority = 2
    if (project.dueDate < asOfDate) {
      reason = 'Project overdue'
      priority = 0
      overdueProjects += 1
    } else if (project.dueDate <= dueSoonThrough) {
      reason = project.dueDate === asOfDate ? 'Due today' : `Due within ${dueSoonDays} days`
      dueSoonProjects += 1
    }

    if (!reason) continue
    projectItems.push({
      id: `project:${project.id}`,
      kind: 'project',
      title: project.name || 'Untitled project',
      href: `/events/${project.id}`,
      reasons: [reason],
      date: project.dueDate,
      priority,
    })
  }

  for (const supplier of suppliers) {
    if (INACTIVE_SUPPLIER_STATUSES.has(supplier.status || '')) continue
    const reasons: string[] = []
    if (supplier.risk === 'High') reasons.push('High risk')
    if (supplier.nextReviewDate && supplier.nextReviewDate < asOfDate) reasons.push('Review overdue')
    if (reasons.length === 0) continue

    supplierItems.push({
      id: `supplier:${supplier.id}`,
      kind: 'supplier',
      title: supplier.name || 'Unnamed supplier',
      href: `/suppliers/${supplier.id}`,
      reasons,
      date: reasons.includes('Review overdue') ? supplier.nextReviewDate : null,
      priority: supplier.risk === 'High' ? 1 : 1.5,
    })
  }

  return {
    overdueProjects,
    dueSoonProjects,
    supplierAttention: supplierItems.length,
    items: [...projectItems, ...supplierItems].sort((a, b) => (
      a.priority - b.priority
      || (a.date || '9999-12-31').localeCompare(b.date || '9999-12-31')
      || a.title.localeCompare(b.title)
    )),
  }
}
