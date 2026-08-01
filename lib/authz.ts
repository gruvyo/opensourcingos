import 'server-only'

import { createClient } from '@/lib/supabase/server'

export type WorkspaceRole = 'admin' | 'procurement_user' | 'viewer'

export async function requireWorkspace(allowedRoles?: WorkspaceRole[]) {
  const supabase = await createClient()
  const { data: authData, error: authError } = await supabase.auth.getUser()
  if (authError || !authData.user) throw new Error('You must be signed in to continue.')

  const { data: profile, error: profileError } = await supabase
    .from('profiles')
    .select('id, organization_id, email, full_name, role')
    .eq('id', authData.user.id)
    .maybeSingle()

  if (profileError || !profile?.organization_id) {
    throw new Error('Your workspace profile could not be loaded.')
  }

  const role = profile.role as WorkspaceRole
  if (allowedRoles && !allowedRoles.includes(role)) {
    throw new Error('Your workspace role does not allow this change.')
  }

  return { supabase, user: authData.user, profile: { ...profile, role } }
}
