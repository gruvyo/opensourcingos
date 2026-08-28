import type { AnchorHTMLAttributes, ReactNode } from 'react'
import { safeExternalHttpUrl } from '@/lib/safe-external-url'

type SafeExternalLinkProps = Omit<AnchorHTMLAttributes<HTMLAnchorElement>, 'href' | 'rel' | 'target'> & {
  children: ReactNode
  href: string | null | undefined
}

export function SafeExternalLink({ children, href, ...props }: SafeExternalLinkProps) {
  const safeHref = safeExternalHttpUrl(href)
  if (!safeHref) return null

  return <a {...props} href={safeHref} target="_blank" rel="noopener noreferrer">{children}</a>
}
