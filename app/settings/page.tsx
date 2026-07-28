'use client'

import { useState, useEffect } from 'react'
import { createClient } from '@/lib/supabase/client'
import { User, Building, Settings as SettingsIcon, Shield } from 'lucide-react'
import { Card } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'

export default function SettingsPage() {
  const supabase = createClient()
  const [user, setUser] = useState<any>(null)
  const [profile, setProfile] = useState<any>(null)
  const [org, setOrg] = useState<any>(null)
  const [loading, setLoading] = useState(true)
  const [loadError, setLoadError] = useState<string | null>(null)

  useEffect(() => {
    const loadData = async () => {
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) { setLoading(false); return }
      setUser(user)

      const { data: profile, error: profileError } = await supabase
        .from('profiles')
        .select('*')
        .eq('id', user.id)
        .single()

      // .single() legitimately errors (PGRST116) when there's no row yet —
      // that's not a load failure, just an empty profile.
      if (profileError && profileError.code !== 'PGRST116') {
        setLoadError((prev) => prev || profileError.message)
      }

      if (profile) {
        setProfile(profile)
        if (profile.organization_id) {
          const { data: org, error: orgError } = await supabase
            .from('organizations')
            .select('*')
            .eq('id', profile.organization_id)
            .single()
          if (orgError && orgError.code !== 'PGRST116') {
            setLoadError((prev) => prev || orgError.message)
          }
          if (org) setOrg(org)
        }
      }
      setLoading(false)
    }
    loadData()
  }, [supabase])

  if (loading) {
    return (
      <div className="p-8">
        <p className="text-sm text-[var(--text-3)]">Loading...</p>
      </div>
    )
  }

  const sectionClass = 'p-6'
  const labelClass = 'text-sm font-medium text-[var(--text-3)]'
  const valueClass = 'mt-1 text-sm text-[var(--text)]'

  return (
    <div className="p-8">
      <div className="mb-6">
        <h1 className="text-2xl font-bold text-[var(--text)]">Settings</h1>
        <p className="mt-1 text-sm text-[var(--text-2)]">
          Account and organization settings
        </p>
      </div>

      {loadError && (
        <div className="mb-6 rounded-lg bg-red-50 p-4 text-sm text-red-700 dark:bg-red-900/30 dark:text-red-300" role="alert">
          <strong>These figures are incomplete.</strong> A query failed: {loadError}. Do not report
          from this page until it loads cleanly.
        </div>
      )}

      <div className="grid grid-cols-1 gap-6 lg:grid-cols-2">
        {/* Profile */}
        <Card className={sectionClass}>
          <div className="mb-4 flex items-center gap-3">
            <div className="flex h-10 w-10 items-center justify-center rounded-lg bg-indigo-50 dark:bg-indigo-900/30">
              <User className="h-5 w-5 text-indigo-600 dark:text-indigo-400" />
            </div>
            <h3 className="text-sm font-semibold text-[var(--text)]">Your Profile</h3>
          </div>
          <dl className="space-y-3">
            <div>
              <dt className={labelClass}>Email</dt>
              <dd className={valueClass}>{user?.email || '—'}</dd>
            </div>
            <div>
              <dt className={labelClass}>User ID</dt>
              <dd className={`${valueClass} font-mono text-xs`}>{user?.id?.slice(0, 8) || '—'}...</dd>
            </div>
            <div>
              <dt className={labelClass}>Role</dt>
              <dd className={valueClass}>{profile?.role || 'User'}</dd>
            </div>
            <div>
              <dt className={labelClass}>Full Name</dt>
              <dd className={valueClass}>{profile?.full_name || 'Not set'}</dd>
            </div>
          </dl>
        </Card>

        {/* Organization */}
        <Card className={sectionClass}>
          <div className="mb-4 flex items-center gap-3">
            <div className="flex h-10 w-10 items-center justify-center rounded-lg bg-purple-50 dark:bg-purple-900/30">
              <Building className="h-5 w-5 text-purple-600 dark:text-purple-400" />
            </div>
            <h3 className="text-sm font-semibold text-[var(--text)]">Organization</h3>
          </div>
          <dl className="space-y-3">
            <div>
              <dt className={labelClass}>Organization Name</dt>
              <dd className={valueClass}>{org?.org_name || '—'}</dd>
            </div>
            <div>
              <dt className={labelClass}>Organization ID</dt>
              <dd className={`${valueClass} font-mono text-xs`}>{org?.id?.slice(0, 8) || '—'}...</dd>
            </div>
            <div>
              <dt className={labelClass}>Currency</dt>
              <dd className={valueClass}>USD ($)</dd>
            </div>
            <div>
              <dt className={labelClass}>Plan</dt>
              <dd className={valueClass}>
                <Badge tone="brand">MVP Beta</Badge>
              </dd>
            </div>
          </dl>
        </Card>

        {/* Preferences */}
        <Card className={sectionClass}>
          <div className="mb-4 flex items-center gap-3">
            <div className="flex h-10 w-10 items-center justify-center rounded-lg bg-green-50 dark:bg-green-900/30">
              <SettingsIcon className="h-5 w-5 text-green-600 dark:text-green-400" />
            </div>
            <h3 className="text-sm font-semibold text-[var(--text)]">Preferences</h3>
          </div>
          <dl className="space-y-3">
            <div>
              <dt className={labelClass}>Theme</dt>
              <dd className={valueClass}>Dark mode (toggle in sidebar)</dd>
            </div>
            <div>
              <dt className={labelClass}>Date Format</dt>
              <dd className={valueClass}>MMM D, YYYY</dd>
            </div>
            <div>
              <dt className={labelClass}>Number Format</dt>
              <dd className={valueClass}>US ($1,234)</dd>
            </div>
          </dl>
        </Card>

        {/* System Info */}
        <Card className={sectionClass}>
          <div className="mb-4 flex items-center gap-3">
            <div className="flex h-10 w-10 items-center justify-center rounded-lg bg-amber-50 dark:bg-amber-900/30">
              <Shield className="h-5 w-5 text-amber-600 dark:text-amber-400" />
            </div>
            <h3 className="text-sm font-semibold text-[var(--text)]">System</h3>
          </div>
          <dl className="space-y-3">
            <div>
              <dt className={labelClass}>Version</dt>
              <dd className={valueClass}>MVP Beta</dd>
            </div>
            <div>
              <dt className={labelClass}>Database</dt>
              <dd className={valueClass}>Supabase (PostgreSQL)</dd>
            </div>
            <div>
              <dt className={labelClass}>Hosting</dt>
              <dd className={valueClass}>Vercel</dd>
            </div>
            <div>
              <dt className={labelClass}>Authentication</dt>
              <dd className={valueClass}>Supabase Auth (Email)</dd>
            </div>
          </dl>
        </Card>
      </div>
    </div>
  )
}