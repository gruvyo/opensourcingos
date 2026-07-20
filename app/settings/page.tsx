'use client'

import { useState, useEffect } from 'react'
import { createClient } from '@/lib/supabase/client'
import { User, Building, Settings as SettingsIcon, Shield } from 'lucide-react'

export default function SettingsPage() {
  const supabase = createClient()
  const [user, setUser] = useState<any>(null)
  const [profile, setProfile] = useState<any>(null)
  const [org, setOrg] = useState<any>(null)
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    const loadData = async () => {
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) { setLoading(false); return }
      setUser(user)

      const { data: profile } = await supabase
        .from('profiles')
        .select('*')
        .eq('id', user.id)
        .single()
      
      if (profile) {
        setProfile(profile)
        if (profile.organization_id) {
          const { data: org } = await supabase
            .from('organizations')
            .select('*')
            .eq('id', profile.organization_id)
            .single()
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
        <p className="text-sm text-gray-500 dark:text-gray-400">Loading...</p>
      </div>
    )
  }

  const sectionClass = 'rounded-lg border border-gray-200 bg-white p-6 shadow-sm dark:border-gray-700 dark:bg-gray-800'
  const labelClass = 'text-sm font-medium text-gray-500 dark:text-gray-400'
  const valueClass = 'mt-1 text-sm text-gray-900 dark:text-gray-100'

  return (
    <div className="p-8">
      <div className="mb-6">
        <h1 className="text-2xl font-bold text-gray-900 dark:text-gray-100">Settings</h1>
        <p className="mt-1 text-sm text-gray-600 dark:text-gray-400">
          Account and organization settings
        </p>
      </div>

      <div className="grid grid-cols-1 gap-6 lg:grid-cols-2">
        {/* Profile */}
        <div className={sectionClass}>
          <div className="mb-4 flex items-center gap-3">
            <div className="flex h-10 w-10 items-center justify-center rounded-lg bg-indigo-50 dark:bg-indigo-900/30">
              <User className="h-5 w-5 text-indigo-600 dark:text-indigo-400" />
            </div>
            <h3 className="text-sm font-semibold text-gray-900 dark:text-gray-100">Your Profile</h3>
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
        </div>

        {/* Organization */}
        <div className={sectionClass}>
          <div className="mb-4 flex items-center gap-3">
            <div className="flex h-10 w-10 items-center justify-center rounded-lg bg-purple-50 dark:bg-purple-900/30">
              <Building className="h-5 w-5 text-purple-600 dark:text-purple-400" />
            </div>
            <h3 className="text-sm font-semibold text-gray-900 dark:text-gray-100">Organization</h3>
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
                <span className="rounded bg-indigo-100 px-2 py-0.5 text-xs text-indigo-700 dark:bg-indigo-900/30 dark:text-indigo-300">
                  MVP Beta
                </span>
              </dd>
            </div>
          </dl>
        </div>

        {/* Preferences */}
        <div className={sectionClass}>
          <div className="mb-4 flex items-center gap-3">
            <div className="flex h-10 w-10 items-center justify-center rounded-lg bg-green-50 dark:bg-green-900/30">
              <SettingsIcon className="h-5 w-5 text-green-600 dark:text-green-400" />
            </div>
            <h3 className="text-sm font-semibold text-gray-900 dark:text-gray-100">Preferences</h3>
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
        </div>

        {/* System Info */}
        <div className={sectionClass}>
          <div className="mb-4 flex items-center gap-3">
            <div className="flex h-10 w-10 items-center justify-center rounded-lg bg-amber-50 dark:bg-amber-900/30">
              <Shield className="h-5 w-5 text-amber-600 dark:text-amber-400" />
            </div>
            <h3 className="text-sm font-semibold text-gray-900 dark:text-gray-100">System</h3>
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
        </div>
      </div>
    </div>
  )
}