'use client'

import { useEffect, useId, useRef, useState } from 'react'
import { Button } from '@/components/ui/button'

export function ConfirmDialog({
  title,
  description,
  confirmLabel = 'Delete',
  pendingLabel = 'Deleting...',
  onConfirm,
  onCancel,
}: {
  title: string
  description: string
  confirmLabel?: string
  pendingLabel?: string
  onConfirm: () => void | Promise<void>
  onCancel: () => void
}) {
  const [pending, setPending] = useState(false)
  const dialogRef = useRef<HTMLDivElement>(null)
  const pendingRef = useRef(pending)
  const onCancelRef = useRef(onCancel)
  const titleId = useId()
  const descriptionId = useId()

  useEffect(() => {
    pendingRef.current = pending
  }, [pending])

  useEffect(() => {
    onCancelRef.current = onCancel
  }, [onCancel])

  useEffect(() => {
    const previousFocus = document.activeElement as HTMLElement | null
    const previousOverflow = document.body.style.overflow
    document.body.style.overflow = 'hidden'

    const focusables = () =>
      Array.from(
        dialogRef.current?.querySelectorAll<HTMLElement>(
          'a[href], button:not([disabled]), input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])',
        ) ?? [],
      )

    dialogRef.current?.querySelector<HTMLElement>('[data-cancel]')?.focus()

    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === 'Escape') {
        event.preventDefault()
        event.stopPropagation()
        if (!pendingRef.current) onCancelRef.current()
        return
      }

      if (event.key !== 'Tab') return
      const items = focusables()
      if (items.length === 0) {
        event.preventDefault()
        return
      }

      const first = items[0]
      const last = items[items.length - 1]
      if (event.shiftKey && document.activeElement === first) {
        event.preventDefault()
        last.focus()
      } else if (!event.shiftKey && document.activeElement === last) {
        event.preventDefault()
        first.focus()
      }
    }

    document.addEventListener('keydown', onKeyDown, true)
    return () => {
      document.removeEventListener('keydown', onKeyDown, true)
      document.body.style.overflow = previousOverflow
      if (previousFocus?.isConnected) {
        previousFocus.focus()
      } else {
        document.querySelector<HTMLElement>(
          'main button:not([disabled]), main a[href], main input:not([disabled]), main select:not([disabled]), main textarea:not([disabled])',
        )?.focus()
      }
    }
  }, [])

  const handleConfirm = async () => {
    pendingRef.current = true
    setPending(true)
    try {
      await onConfirm()
    } finally {
      pendingRef.current = false
      setPending(false)
    }
    onCancel()
  }

  return (
    <div
      className="fixed inset-0 z-[60] flex items-center justify-center bg-black/60 p-4"
      onClick={(event) => {
        event.stopPropagation()
        if (event.target === event.currentTarget && !pending) onCancel()
      }}
    >
      <div
        ref={dialogRef}
        role="alertdialog"
        aria-modal="true"
        aria-labelledby={titleId}
        aria-describedby={descriptionId}
        aria-busy={pending}
        className="w-full max-w-md rounded-lg border border-[var(--border)] bg-[var(--surface)] p-6 shadow-xl"
      >
        <h2 id={titleId} className="text-lg font-bold text-[var(--text)]">{title}</h2>
        <p id={descriptionId} className="mt-2 text-sm leading-6 text-[var(--text-2)]">{description}</p>
        <div className="mt-6 flex justify-end gap-3">
          <Button type="button" variant="secondary" data-cancel onClick={onCancel} disabled={pending}>
            Cancel
          </Button>
          <Button type="button" variant="danger" onClick={handleConfirm} disabled={pending}>
            {pending ? pendingLabel : confirmLabel}
          </Button>
        </div>
      </div>
    </div>
  )
}
