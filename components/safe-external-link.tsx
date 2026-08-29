import type { AnchorHTMLAttributes, ReactNode } from 'react'
import { safeExternalHttpUrl } from '@/lib/safe-external-url'

type SafeExternalLinkProps = Omit<AnchorHTMLAttributes<HTMLAnchorElement>, 'href' | 'rel' | 'target'> & {
  children: ReactNode
  href: string | null | undefined
}

export function SafeExternalLink({ children, href, ...props }: SafeExternalLinkProps) {
  const safeHref = safeExternalHttpUrl(href)
  if (!safeHref) {
    if (!href?.trim()) return null
    return <span className={props.className} title="Stored value is not a valid HTTP(S) URL">{children}: {href} (invalid URL)</span>
  }

  return <a {...props} href={safeHref} target="_blank" rel="noopener noreferrer">{children}</a>
}
