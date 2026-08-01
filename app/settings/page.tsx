import type { ReactNode } from 'react'
import {
  Building2,
  CalendarDays,
  Check,
  CircleUserRound,
  Database,
  KeyRound,
  Landmark,
  ShieldCheck,
} from 'lucide-react'
import { createClient } from '@/lib/supabase/server'
import { Badge } from '@/components/ui/badge'
import { Card } from '@/components/ui/card'
import { PageHeader } from '@/components/ui/page-header'

function SettingsPanel({
  icon: Icon,
  title,
  description,
  children,
}: {
  icon: typeof Building2
  title: string
  description: string
  children: ReactNode
}) {
  return (
    <Card className="overflow-hidden">
      <div className="flex items-start gap-3 border-b border-[var(--border)] px-5 py-4 sm:px-6">
        <div className="grid h-10 w-10 shrink-0 place-items-center rounded-lg bg-[var(--brand-soft)] text-[var(--brand-ink)]">
          <Icon className="h-5 w-5" aria-hidden="true" />
        </div>
        <div>
          <h2 className="text-sm font-semibold text-[var(--text)]">{title}</h2>
          <p className="mt-1 text-xs leading-5 text-[var(--text-3)]">{description}</p>
        </div>
      </div>
      <div className="p-5 sm:p-6">{children}</div>
    </Card>
  )
}

function SettingRow({ label, value, detail }: { label: string; value: ReactNode; detail?: string }) {
  return (
    <div className="flex flex-col gap-1 border-b border-[var(--border)] py-3 first:pt-0 last:border-0 last:pb-0 sm:flex-row sm:items-start sm:justify-between sm:gap-6">
      <div>
        <p className="text-sm font-medium text-[var(--text)]">{label}</p>
        {detail ? <p className="mt-0.5 text-xs text-[var(--text-3)]">{detail}</p> : null}
      </div>
      <div className="text-sm text-[var(--text-2)] sm:max-w-[55%] sm:text-right">{value}</div>
    </div>
  )
}

function Assurance({ children }: { children: ReactNode }) {
  return (
    <li className="flex gap-2 text-sm leading-6 text-[var(--text-2)]">
      <Check className="mt-1 h-4 w-4 shrink-0 text-[var(--success)]" aria-hidden="true" />
      <span>{children}</span>
    </li>
  )
}

export default async function SettingsPage() {
  const supabase = await createClient()
  const { data: authData, error: authError } = await supabase.auth.getUser()
  const user = authData.user

  const profileResult = user
    ? await supabase.from('profiles').select('id, organization_id, email, full_name, role').eq('id', user.id).maybeSingle()
    : { data: null, error: null }
  const profile = profileResult.data

  const organizationResult = profile?.organization_id
    ? await supabase.from('organizations').select('id, name, created_at').eq('id', profile.organization_id).maybeSingle()
    : { data: null, error: null }
  const organization = organizationResult.data

  const loadError = authError?.message || profileResult.error?.message || organizationResult.error?.message || null
  const workspaceId = organization?.id ? `${organization.id.slice(0, 8)}…` : '—'

  return (
    <div className="mx-auto w-full max-w-[1400px] p-4 sm:p-6 lg:p-8">
      <PageHeader
        eyebrow="Workspace administration"
        title="Settings"
        description="Identity, workspace context, reporting defaults, and the controls behind trustworthy procurement reporting."
        actions={<Badge tone="brand" className="px-3 py-1.5">Public beta</Badge>}
      />

      {loadError ? (
        <div className="mt-6 rounded-xl bg-red-50 p-4 text-sm text-red-700 dark:bg-red-900/30 dark:text-red-300" role="alert">
          <strong>Settings are incomplete.</strong> A query failed: {loadError}.
        </div>
      ) : null}

      <div className="mt-6 grid grid-cols-1 gap-6 xl:grid-cols-2">
        <SettingsPanel
          icon={CircleUserRound}
          title="Identity & access"
          description="The account currently signed in and its workspace role."
        >
          <SettingRow label="Name" value={profile?.full_name || user?.user_metadata?.full_name || 'Not provided'} />
          <SettingRow label="Email" value={user?.email || profile?.email || '—'} />
          <SettingRow label="Role" value={<Badge tone="info">{profile?.role || 'viewer'}</Badge>} detail="Controls what this account may manage." />
          <SettingRow label="Authentication" value="Google via Supabase Auth" detail="No password is stored by OpenSourcingOS." />
        </SettingsPanel>

        <SettingsPanel
          icon={Building2}
          title="Workspace"
          description="The organization boundary applied to projects, suppliers, and reporting."
        >
          <SettingRow label="Organization" value={organization?.name || '—'} />
          <SettingRow label="Workspace ID" value={<span className="font-mono text-xs">{workspaceId}</span>} />
          <SettingRow label="Data isolation" value={<Badge tone="success">Row Level Security</Badge>} detail="Business records are scoped to this workspace." />
          <SettingRow label="Environment" value="Hosted public beta" />
        </SettingsPanel>

        <SettingsPanel
          icon={Landmark}
          title="Reporting defaults"
          description="Current conventions used throughout portfolio and savings views."
        >
          <SettingRow label="Currency" value="USD ($)" detail="Applied to financial values and exports." />
          <SettingRow label="Fiscal calendar" value="Calendar year" detail="January through December." />
          <SettingRow label="Date presentation" value="MMM D, YYYY" />
          <SettingRow label="Theme" value="Light or dark" detail="Use the control in the navigation sidebar." />
        </SettingsPanel>

        <SettingsPanel
          icon={ShieldCheck}
          title="Methodology controls"
          description="Guardrails that keep reported savings traceable and defensible."
        >
          <ul className="space-y-2">
            <Assurance>Opening proposal, baseline, and final offer remain linked as one commercial chain.</Assurance>
            <Assurance>Cost Reduction requires a defensible baseline or a recorded override.</Assurance>
            <Assurance>Cost increases remain negative and missing anchors remain not applicable.</Assurance>
            <Assurance>Schedules preserve total deal economics across fiscal-year reporting.</Assurance>
          </ul>
        </SettingsPanel>
      </div>

      <section className="mt-8" aria-labelledby="connections-title">
        <div className="mb-4">
          <h2 id="connections-title" className="text-lg font-semibold text-[var(--text)]">Platform connections</h2>
          <p className="mt-1 text-sm text-[var(--text-2)]">Services currently supporting this workspace.</p>
        </div>
        <div className="grid grid-cols-1 gap-4 md:grid-cols-3">
          {[
            { icon: KeyRound, label: 'Identity', value: 'Google sign-in', state: 'Connected' },
            { icon: Database, label: 'Data', value: 'Supabase PostgreSQL', state: 'Protected' },
            { icon: CalendarDays, label: 'Reporting', value: 'Fiscal-year schedules', state: 'Active' },
          ].map(connection => (
            <Card key={connection.label} className="flex items-center gap-4 p-5">
              <div className="grid h-10 w-10 shrink-0 place-items-center rounded-lg bg-[var(--surface-2)] text-[var(--text-2)]">
                <connection.icon className="h-5 w-5" aria-hidden="true" />
              </div>
              <div className="min-w-0 flex-1">
                <p className="text-xs font-medium text-[var(--text-3)]">{connection.label}</p>
                <p className="truncate text-sm font-semibold text-[var(--text)]">{connection.value}</p>
              </div>
              <Badge tone="success">{connection.state}</Badge>
            </Card>
          ))}
        </div>
      </section>
    </div>
  )
}
