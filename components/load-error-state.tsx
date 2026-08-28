import { AlertCircle, RotateCcw } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Card } from '@/components/ui/card'

export function LoadErrorState({
  title,
  message,
  onRetry,
  compact = false,
}: {
  title: string
  message: string
  onRetry: () => void | Promise<void>
  compact?: boolean
}) {
  return (
    <Card role="alert" className={compact ? 'm-4 p-4' : 'p-8 text-center'}>
      <AlertCircle className={`${compact ? 'mb-2 h-5 w-5' : 'mx-auto mb-3 h-8 w-8'} text-red-500`} aria-hidden="true" />
      <h3 className="text-sm font-semibold text-[var(--text)]">{title}</h3>
      <p className="mt-1 text-sm text-[var(--text-3)]">{message} No data was treated as empty, and affected editing is paused.</p>
      <Button type="button" variant="secondary" size="sm" className="mt-4" onClick={() => void onRetry()}>
        <RotateCcw className="h-3.5 w-3.5" aria-hidden="true" />
        Try again
      </Button>
    </Card>
  )
}
