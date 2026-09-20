import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Content-Type': 'application/json',
}

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: corsHeaders })

// ---- Input validation helpers -------------------------------------------
// Every field coming from the request body is untrusted. Nothing here is
// ever interpolated into a SQL string — all database access below goes
// through the supabase-js client, which sends parameterized requests to
// PostgREST / GoTrue, so SQL injection isn't a viable vector — but we
// still validate shape, type, and length before using any of it, and
// before it reaches Supabase Auth's own admin APIs.
const ALLOWED_ACTIONS = new Set(['list', 'invite', 'remove'])
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

function validEmail(value: unknown): value is string {
  return typeof value === 'string' && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value.trim()) && value.trim().length <= 320
}
function validUuid(value: unknown): value is string {
  return typeof value === 'string' && UUID_RE.test(value)
}

// ---- Secrets --------------------------------------------------------------
// Read exclusively from the environment (set via `supabase secrets set` /
// the Dashboard's Edge Function secrets). Never hardcode keys here — the
// service role key in particular must never appear in source control or
// in any file shipped to the browser.
const supabaseUrl = Deno.env.get('SUPABASE_URL')
const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  if (req.method !== 'POST') return json({ error: 'Method not allowed' }, 405)

  if (!supabaseUrl || !serviceRoleKey) {
    // Fail closed rather than proceeding with an undefined key.
    console.error('Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY environment variables.')
    return json({ error: 'Server misconfiguration.' }, 500)
  }

  const adminClient = createClient(supabaseUrl, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  })

  // ---- API resilience: IP-level throttle, before we even check auth ----
  // Applies to every request, authenticated or not, so a flood of bad
  // tokens can't be used to hammer the function or the database behind it.
  const clientIp = req.headers.get('x-forwarded-for')?.split(',')[0].trim()
    || req.headers.get('cf-connecting-ip')
    || 'unknown'
  const { data: ipAllowed, error: ipLimitError } = await adminClient.rpc('check_rate_limit', {
    p_key: `manage-admin:ip:${clientIp}`,
    p_max_requests: 30,
    p_window_seconds: 60,
  })
  if (ipLimitError) {
    console.error('Rate limit check failed:', ipLimitError.message)
    // Don't fail open on a broken limiter for a privileged endpoint.
    return json({ error: 'Service temporarily unavailable. Please try again shortly.' }, 503)
  }
  if (ipAllowed === false) {
    return json({ error: 'Too many requests. Please wait a moment and try again.' }, 429)
  }

  const authHeader = req.headers.get('Authorization')
  if (!authHeader?.startsWith('Bearer ')) return json({ error: 'Missing authorization' }, 401)
  const token = authHeader.replace('Bearer ', '')

  const userClient = createClient(supabaseUrl, serviceRoleKey, {
    global: { headers: { Authorization: `Bearer ${token}` } },
    auth: { autoRefreshToken: false, persistSession: false },
  })

  const { data: { user }, error: userError } = await userClient.auth.getUser(token)
  if (userError || !user) return json({ error: 'Invalid session' }, 401)

  const callerRole = user.app_metadata?.role
  if (callerRole !== 'owner') {
    return json({ error: 'Only the owner can manage administrators.' }, 403)
  }

  // ---- Per-user throttle, now that we know who's calling ----
  const { data: userAllowed, error: userLimitError } = await adminClient.rpc('check_rate_limit', {
    p_key: `manage-admin:user:${user.id}`,
    p_max_requests: 20,
    p_window_seconds: 60,
  })
  if (userLimitError) {
    console.error('Rate limit check failed:', userLimitError.message)
    return json({ error: 'Service temporarily unavailable. Please try again shortly.' }, 503)
  }
  if (userAllowed === false) {
    return json({ error: 'Too many requests from your account. Please wait a moment and try again.' }, 429)
  }

  let body: { action?: unknown; email?: unknown; userId?: unknown }
  try {
    body = await req.json()
  } catch {
    return json({ error: 'Invalid JSON body' }, 400)
  }

  if (typeof body.action !== 'string' || !ALLOWED_ACTIONS.has(body.action)) {
    return json({ error: 'Unknown action.' }, 400)
  }
  const action = body.action

  if (action === 'list') {
    const { data, error } = await adminClient.auth.admin.listUsers({ page: 1, perPage: 1000 })
    if (error) return json({ error: error.message }, 400)

    const admins = (data.users || [])
      .filter((u) => ['owner', 'admin'].includes(u.app_metadata?.role))
      .map((u) => ({
        id: u.id,
        email: u.email,
        role: u.app_metadata?.role,
        created_at: u.created_at,
        last_sign_in_at: u.last_sign_in_at,
        email_confirmed_at: u.email_confirmed_at,
      }))
      .sort((a, b) => (a.role === 'owner' ? -1 : b.role === 'owner' ? 1 : (a.email || '').localeCompare(b.email || '')))

    return json({ admins })
  }

  if (action === 'invite') {
    // Extra throttle specific to invitations: this sends real emails, so
    // it's the action most worth protecting against accidental or
    // malicious spam, on top of the general per-user limit above.
    const { data: inviteAllowed, error: inviteLimitError } = await adminClient.rpc('check_rate_limit', {
      p_key: `manage-admin:invite:${user.id}`,
      p_max_requests: 5,
      p_window_seconds: 300,
    })
    if (inviteLimitError) {
      console.error('Rate limit check failed:', inviteLimitError.message)
      return json({ error: 'Service temporarily unavailable. Please try again shortly.' }, 503)
    }
    if (inviteAllowed === false) {
      return json({ error: 'Too many invitations sent recently. Please wait a few minutes and try again.' }, 429)
    }

    if (!validEmail(body.email)) return json({ error: 'Enter a valid email address.' }, 400)
    const email = (body.email as string).trim().toLowerCase()

    const { data: listData, error: listError } = await adminClient.auth.admin.listUsers({ page: 1, perPage: 1000 })
    if (listError) return json({ error: listError.message }, 400)

    const existing = (listData.users || []).find((u) => (u.email || '').toLowerCase() === email)
    if (existing) {
      const existingRole = existing.app_metadata?.role
      if (existingRole === 'owner' || existingRole === 'admin') {
        return json({ error: 'This email is already an administrator.' }, 409)
      }
      return json({ error: 'An account with this email already exists. Use Supabase password reset for that account, then promote it separately.' }, 409)
    }

    // The Edge Function URL is NOT the website URL. Use an explicit app URL
    // so invitation links return to the admin page after the user accepts.
    const appUrl = Deno.env.get('ADMIN_APP_URL') || 'http://localhost:5500'
    const redirectTo = `${appUrl.replace(/\/$/, '')}/admin.html`
    const { data: invited, error: inviteError } = await adminClient.auth.admin.inviteUserByEmail(email, {
      redirectTo,
    })
    if (inviteError || !invited.user) return json({ error: inviteError?.message || 'Could not send invitation.' }, 400)

    const { data: updated, error: roleError } = await adminClient.auth.admin.updateUserById(invited.user.id, {
      app_metadata: { ...(invited.user.app_metadata || {}), role: 'admin' },
    })
    if (roleError) {
      // Prevent an invited account from remaining partially configured if role assignment fails.
      await adminClient.auth.admin.deleteUser(invited.user.id)
      return json({ error: roleError.message }, 400)
    }

    return json({
      ok: true,
      admin: { id: updated.user.id, email: updated.user.email, role: 'admin' },
      message: `Invitation sent to ${email}.`,
    })
  }

  if (action === 'remove') {
    if (!validUuid(body.userId)) return json({ error: 'Missing or invalid administrator id.' }, 400)
    const userId = body.userId as string
    if (userId === user.id) return json({ error: 'You cannot remove yourself as an administrator.' }, 400)

    const { data: targetData, error: targetError } = await adminClient.auth.admin.getUserById(userId)
    if (targetError || !targetData.user) return json({ error: 'Administrator not found.' }, 404)
    if (targetData.user.app_metadata?.role === 'owner') return json({ error: 'The owner account cannot be removed.' }, 400)
    if (targetData.user.app_metadata?.role !== 'admin') return json({ error: 'This user is not an administrator.' }, 400)

    const { error } = await adminClient.auth.admin.updateUserById(userId, {
      app_metadata: { ...(targetData.user.app_metadata || {}), role: 'user' },
    })
    if (error) return json({ error: error.message }, 400)

    return json({ ok: true, message: 'Administrator access revoked.' })
  }

  return json({ error: 'Unknown action.' }, 400)
})
