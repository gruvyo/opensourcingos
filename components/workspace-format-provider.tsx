'use client'

import { createContext, useContext, useMemo } from 'react'
import {
  DEFAULT_WORKSPACE_CURRENCY,
  DEFAULT_WORKSPACE_LOCALE,
  workspaceFormatters,
} from '@/lib/workspace-settings'

type WorkspaceFormat = ReturnType<typeof workspaceFormatters>

const WorkspaceFormatContext = createContext<WorkspaceFormat>(
  workspaceFormatters(DEFAULT_WORKSPACE_CURRENCY, DEFAULT_WORKSPACE_LOCALE),
)

export function WorkspaceFormatProvider({
  currencyCode,
  locale,
  children,
}: {
  currencyCode: string
  locale: string
  children: React.ReactNode
}) {
  const value = useMemo(() => workspaceFormatters(currencyCode, locale), [currencyCode, locale])
  return <WorkspaceFormatContext.Provider value={value}>{children}</WorkspaceFormatContext.Provider>
}

export function useWorkspaceFormat(): WorkspaceFormat {
  return useContext(WorkspaceFormatContext)
}
