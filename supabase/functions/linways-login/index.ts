// College Project — Linways Login Auth Function (stateless)
// Split-token architecture (LINWAYS_INTEGRATION_ARCHITECTURE.md option C):
//   login handshake -> Linways profile -> server-side community derivation
//   -> provision native Supabase Auth user -> profile/membership upsert
//   -> mint real Supabase Auth session -> hand { session, profile, community,
//   linways_session_cookies } to the app exactly once. Server retains nothing.
//
// Security invariants (locked decisions 1-10, JWT_AUTH_COMPATIBILITY.md u22):
//   - Password is used in-memory only; never stored or logged.
//   - Linways AUTH_SESSION / accessToken / refresh_token are never persisted
//     server-side and never logged.
//   - Community is derived server-side from authoritative Linways data only;
//     client-supplied course/year/semester/section/community_id are ignored.
//   - No credential, token, or cookie logging anywhere in this file.
//   - CORS is restricted to allowlisted origins and responses are no-store:
//     session tokens must not be readable by arbitrary browser origins.

import { createClient, SupabaseClient } from "@supabase/supabase-js";

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

const LINWAYS_BASE = "https://sfcv4.linways.com/academics/api/v1";
const LINWAYS_LOGIN_PATH = "/auth/student-login-credentials";
const LINWAYS_PROFILE_PATH = "/student/get-my-profile-details";
const SYNTHETIC_EMAIL_DOMAIN = "college-project.local";

const LINWAYS_TIMEOUT_MS = 15_000;

const RATE_LIMIT_MAX_FAILURES = 5;
const RATE_LIMIT_WINDOW_MINUTES = 15;
const RATE_LIMIT_RETENTION_HOURS = 24;

// Restricted CORS: responses carry session tokens, so no arbitrary browser
// origin may read them. Mobile/Flutter clients do not use CORS and are
// unaffected. Add future web frontend origins to ALLOWED_ORIGINS.
const ALLOWED_ORIGINS: readonly string[] = [];

function corsHeadersFor(req: Request): Record<string, string> {
  const headers: Record<string, string> = {
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Cache-Control": "no-store",
  };
  const origin = req.headers.get("origin");
  if (origin && ALLOWED_ORIGINS.includes(origin)) {
    headers["Access-Control-Allow-Origin"] = origin;
    headers["Vary"] = "Origin";
  }
  return headers;
}

const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY");

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

interface LinwaysProfile {
  name: string;
  registerNo: string;
  programme?: string;
  batchName?: string;
  currentSem?: string;
  email?: string;
}

interface DerivedCommunity {
  course_code: string;
  batch_year: number;
  semester: string;
  section: string;
}

// ---------------------------------------------------------------------------
// HTTP helpers
// ---------------------------------------------------------------------------

function jsonResponse(
  req: Request,
  body: Record<string, unknown>,
  status = 200,
  extraHeaders: Record<string, string> = {},
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...corsHeadersFor(req), ...extraHeaders },
  });
}

function isNonEmptyString(value: unknown, maxLength: number): value is string {
  return typeof value === "string" && value.length > 0 && value.length <= maxLength;
}

function pick(...values: unknown[]): string | undefined {
  for (const value of values) {
    if (typeof value === "string" && value.trim().length > 0) return value.trim();
  }
  return undefined;
}

function normalizeEmail(email: string): string | undefined {
  const cleaned = email.trim().toLowerCase();
  return cleaned.length > 0 ? cleaned : undefined;
}

// Returns the last valid X-Forwarded-For entry (the IP appended by the
// platform's proxy). X-Real-IP is client-controllable and never trusted.
// Returns undefined when no valid IP exists; callers then fail open.
function getClientIp(req: Request): string | undefined {
  const forwarded = req.headers.get("x-forwarded-for");
  if (!forwarded) return undefined;
  const entries = forwarded.split(",");
  for (let i = entries.length - 1; i >= 0; i -= 1) {
    const entry = entries[i].trim();
    if (/^[0-9a-fA-F:.]+$/.test(entry)) return entry;
  }
  return undefined;
}

// ---------------------------------------------------------------------------
// Rate limiting (server-side only; stores no credentials/tokens/cookies)
// ---------------------------------------------------------------------------

async function pruneOldAttempts(db: SupabaseClient): Promise<void> {
  const cutoff = new Date(Date.now() - RATE_LIMIT_RETENTION_HOURS * 3_600_000).toISOString();
  try {
    await db.from("login_attempts").delete().lt("attempted_at", cutoff);
  } catch {
    // The rate limiter must never break login; retention cleanup is best-effort.
  }
}

async function countRecentFailures(db: SupabaseClient, ip: string | undefined): Promise<number> {
  if (!ip) return 0; // Fail open: no IP to key on -> no IP-based limiting.
  const windowStart = new Date(Date.now() - RATE_LIMIT_WINDOW_MINUTES * 60_000).toISOString();
  try {
    const { count } = await db
      .from("login_attempts")
      .select("id", { count: "exact", head: true })
      .eq("ip_address", ip)
      .eq("outcome", "failure")
      .gte("attempted_at", windowStart);
    return count ?? 0;
  } catch {
    return 0;
  }
}

async function recordAttempt(db: SupabaseClient, ip: string | undefined, outcome: "success" | "failure"): Promise<void> {
  if (!ip) return; // Fail open: skip recording without an IP.
  try {
    await db.from("login_attempts").insert({ ip_address: ip, outcome });
  } catch {
    // Best-effort; never fail login because of the limiter.
  }
}

async function clearFailures(db: SupabaseClient, ip: string | undefined): Promise<void> {
  if (!ip) return; // Fail open: nothing to clear without an IP.
  try {
    await db.from("login_attempts").delete().eq("ip_address", ip).eq("outcome", "failure");
  } catch {
    // Best-effort.
  }
}

// ---------------------------------------------------------------------------
// Linways client (confirmed endpoints; defensive parsing, no logging)
// ---------------------------------------------------------------------------

interface LinwaysLoginResult {
  ok: boolean;
  status: number;
  cookies: string;
  accessToken: string | undefined;
}

async function linwaysLogin(username: string, password: string): Promise<LinwaysLoginResult> {
  const res = await fetch(`${LINWAYS_BASE}${LINWAYS_LOGIN_PATH}`, {
    method: "POST",
    headers: { "Content-Type": "application/json", Accept: "application/json" },
    body: JSON.stringify({ username, password, next: "", userType: "STUDENT" }),
    signal: AbortSignal.timeout(LINWAYS_TIMEOUT_MS),
  });

  const setCookies = res.headers.getSetCookie?.() ?? [];
  const cookies = setCookies
    .map((header) => header.split(";")[0].trim())
    .filter((part) => part.length > 0)
    .join("; ");

  let data: Record<string, unknown> | null = null;
  try {
    data = (await res.json()) as Record<string, unknown>;
  } catch {
    data = null;
  }

  const ok = data !== null && data.success === true;
  const inner = (data?.data ?? {}) as Record<string, unknown>;
  const accessToken = pick(inner.accessToken, inner.token);

  return { ok, status: res.status, cookies, accessToken };
}

async function linwaysProfile(
  cookies: string,
  accessToken: string | undefined,
): Promise<LinwaysProfile | null> {
  const headers: Record<string, string> = { Accept: "application/json" };
  if (cookies) headers["Cookie"] = cookies;
  if (accessToken) headers["Authorization"] = `Bearer ${accessToken}`;

  const res = await fetch(`${LINWAYS_BASE}${LINWAYS_PROFILE_PATH}`, {
    headers,
    signal: AbortSignal.timeout(LINWAYS_TIMEOUT_MS),
  });
  if (!res.ok) return null;

  let data: Record<string, unknown> | null = null;
  try {
    data = (await res.json()) as Record<string, unknown>;
  } catch {
    return null;
  }

  const profileData = (data?.data ?? data ?? {}) as Record<string, unknown>;
  const properties = (profileData.properties ?? {}) as Record<string, unknown>;
  const name = pick(profileData.name, profileData.studentName, profileData.student_name);
  const registerNo = pick(
    profileData.registerNo,
    profileData.registerNumber,
    profileData.register_number,
    properties.registerNumber,
    properties.register_number,
  );
  if (!name || !registerNo) return null;

  return {
    name,
    registerNo,
    programme: pick(profileData.programme),
    batchName: pick(profileData.batchName, profileData.batch_name, profileData.batch),
    currentSem: pick(profileData.currentSem, profileData.current_sem, profileData.academicTerm),
    email: pick(profileData.email),
  };
}

// ---------------------------------------------------------------------------
// Community derivation — server-side only, versioned rule set
// ---------------------------------------------------------------------------

function normalizeSemester(raw: string | undefined): string | null {
  if (!raw) return null;
  const match = raw.trim().match(/^S?([0-9]{1,2})$/i);
  if (!match) return null;
  return `S${match[1]}`;
}

function deriveCommunity(profile: LinwaysProfile): DerivedCommunity | null {
  const COURSE_RE = /^[A-Za-z]{2,6}$/;
  const YEAR_RE = /^[0-9]{4}$/;
  const SECTION_RE = /^[A-Za-z]{1,3}$/;

  const batchTokens = (profile.batchName ?? "").trim().split(/\s+/).filter(Boolean);

  let course: string | undefined;
  let batchYear: number | undefined;
  let section: string | undefined;

  if (batchTokens.length >= 3) {
    const first = batchTokens[0];
    const last = batchTokens[batchTokens.length - 1];
    const yearToken = batchTokens.find((token) => YEAR_RE.test(token));
    if (COURSE_RE.test(first) && yearToken && SECTION_RE.test(last)) {
      course = first.toUpperCase();
      batchYear = Number(yearToken);
      section = last.toUpperCase();
    }
  }

  if (!course && profile.programme) {
    const programmeTokens = profile.programme
      .split("-")
      .map((token) => token.trim())
      .filter((token) => COURSE_RE.test(token) && token.toUpperCase() !== "UG");
    if (programmeTokens.length > 0) course = programmeTokens[0].toUpperCase();
  }

  const semester = normalizeSemester(profile.currentSem);
  if (!course || !batchYear || !section || !semester) return null;

  return { course_code: course, batch_year: batchYear, semester, section };
}

// ---------------------------------------------------------------------------
// Supabase provisioning (service_role; idempotent)
// ---------------------------------------------------------------------------

async function findOrCreateAuthUser(
  db: SupabaseClient,
  profile: LinwaysProfile,
): Promise<{ userId: string; email: string }> {
  const registerNo = profile.registerNo;
  const email =
    normalizeEmail(profile.email ?? "") ?? `${registerNo.toLowerCase()}@${SYNTHETIC_EMAIL_DOMAIN}`;

  // Retry loop: handles the concurrent-first-login race, where two requests for
  // the same student both attempt createUser and one hits "email already
  // registered". The winner then writes profiles.student_id, so the loser finds
  // the identity on the next pass via the approved identity mapping.
  for (let attempt = 0; attempt < 3; attempt += 1) {
    // 1. Approved identity mapping: profiles.student_id is unique and 1:1 with
    //    auth.users.id (auth.users.id = profiles.id = auth.uid() by construction).
    const { data: existingProfile } = await db
      .from("profiles")
      .select("id")
      .eq("student_id", registerNo)
      .maybeSingle();
    if (existingProfile?.id) {
      const { data: authUser } = await db.auth.admin.getUserById(existingProfile.id);
      if (authUser?.user) {
        return { userId: authUser.user.id, email: authUser.user.email ?? email };
      }
    }

    // 2. First login: create the native Supabase Auth user (Approach A).
    const randomPassword = crypto.randomUUID().replaceAll("-", "") +
      crypto.randomUUID().replaceAll("-", "");
    const { data: created, error: createError } = await db.auth.admin.createUser({
      email,
      password: randomPassword,
      email_confirm: true,
      user_metadata: {
        full_name: profile.name,
        linways_register_no: registerNo,
      },
    });
    if (created?.user) {
      return { userId: created.user.id, email };
    }
    if (!createError) {
      throw new Error("auth user provisioning failed");
    }
    // Duplicate email (concurrent first login): loop and re-check profiles.
  }

  throw new Error("auth user provisioning failed");
}

// Department resolution: departments.code = course prefix (e.g. BCA), with a
// seeded GENERAL fallback so reports.department_id (NOT NULL) can always be
// satisfied. Admin can add departments anytime without code changes.
async function resolveDepartmentId(
  db: SupabaseClient,
  courseCode: string | null,
): Promise<string | null> {
  if (courseCode) {
    const { data: exact } = await db
      .from("departments")
      .select("id")
      .eq("code", courseCode)
      .maybeSingle();
    if (exact?.id) return exact.id as string;
  }
  const { data: general } = await db
    .from("departments")
    .select("id")
    .eq("code", "GENERAL")
    .maybeSingle();
  return (general?.id as string | undefined) ?? null;
}

async function upsertProfile(
  db: SupabaseClient,
  userId: string,
  profile: LinwaysProfile,
  community: DerivedCommunity | null,
  email: string,
  departmentId: string | null,
): Promise<void> {
  const semesterRaw = normalizeSemester(profile.currentSem);
  const { error } = await db.from("profiles").upsert(
    {
      id: userId,
      email,
      full_name: profile.name,
      role: "student",
      department_id: departmentId,
      semester: semesterRaw ? Number(semesterRaw.slice(1)) : null,
      section: community ? community.section : null,
      student_id: profile.registerNo,
    },
    { onConflict: "id" },
  );
  if (error) throw error;
}

async function getOrCreateCommunity(db: SupabaseClient, key: DerivedCommunity): Promise<string> {
  const { error: insertError } = await db.from("communities").upsert(
    {
      course_code: key.course_code,
      batch_year: key.batch_year,
      semester: key.semester,
      section: key.section,
      display_name: `${key.course_code} ${key.batch_year} ${key.semester} ${key.section}`,
    },
    {
      onConflict: "course_code,batch_year,semester,section",
      ignoreDuplicates: true,
    },
  );
  if (insertError) throw insertError;

  // Race-safe: the UNIQUE constraint guarantees a single row; concurrent
  // get-or-create calls converge on the same community id.
  const { data, error } = await db
    .from("communities")
    .select("id")
    .eq("course_code", key.course_code)
    .eq("batch_year", key.batch_year)
    .eq("semester", key.semester)
    .eq("section", key.section)
    .maybeSingle();
  if (error || !data) throw new Error("community lookup failed");
  return data.id as string;
}

async function activateMembership(
  db: SupabaseClient,
  profileId: string,
  communityId: string,
): Promise<void> {
  const { data: active } = await db
    .from("community_members")
    .select("community_id")
    .eq("profile_id", profileId)
    .eq("is_active", true)
    .maybeSingle();

  if (active?.community_id === communityId) {
    // Already the active membership — idempotent no-op (preserves joined_at).
    return;
  }

  // 1. Deactivate the previous active membership first (partial unique index
  //    community_members_one_active_per_profile: one active row per profile).
  const { error: deactivateError } = await db
    .from("community_members")
    .update({ is_active: false, left_at: new Date().toISOString() })
    .eq("profile_id", profileId)
    .eq("is_active", true);
  if (deactivateError) throw deactivateError;

  // 2. Activate the derived community row (UNIQUE(community_id, profile_id));
  //    joined_at is preserved on conflict (not in the payload).
  const { error: upsertError } = await db.from("community_members").upsert(
    {
      community_id: communityId,
      profile_id: profileId,
      is_active: true,
      left_at: null,
    },
    { onConflict: "community_id,profile_id" },
  );
  if (upsertError) throw upsertError;
}

async function activateMembershipWithRetry(
  db: SupabaseClient,
  profileId: string,
  communityId: string,
): Promise<void> {
  for (let attempt = 0; attempt < 2; attempt += 1) {
    try {
      await activateMembership(db, profileId, communityId);
      return;
    } catch (err) {
      const code = (err as { code?: string } | null)?.code;
      if (attempt === 0 && code === "23505") continue; // concurrent login race: retry once
      throw err;
    }
  }
}

async function mintSupabaseSession(
  serviceDb: SupabaseClient,
  anonDb: SupabaseClient,
  email: string,
): Promise<{ access_token: string; refresh_token: string }> {
  const { data: link, error: linkError } = await serviceDb.auth.admin.generateLink({
    type: "magiclink",
    email,
  });
  const otp = link?.properties?.email_otp;
  if (linkError || !otp) throw new Error("session link generation failed");

  const { data: verified, error: verifyError } = await anonDb.auth.verifyOtp({
    type: "email",
    email,
    token: otp,
  });
  if (verifyError || !verified?.session) throw new Error("session verification failed");

  return {
    access_token: verified.session.access_token,
    refresh_token: verified.session.refresh_token,
  };
}

// ---------------------------------------------------------------------------
// Handler
// ---------------------------------------------------------------------------

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { status: 200, headers: corsHeadersFor(req) });
  }
  if (req.method !== "POST") {
    return jsonResponse(req, { error: "method_not_allowed" }, 405);
  }

  const serviceDb = createClient(SUPABASE_URL ?? "", SERVICE_ROLE_KEY ?? "", {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const anonDb = createClient(SUPABASE_URL ?? "", ANON_KEY ?? "", {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const ip = getClientIp(req);

  await pruneOldAttempts(serviceDb);

  const recentFailures = await countRecentFailures(serviceDb, ip);
  if (recentFailures >= RATE_LIMIT_MAX_FAILURES) {
    return jsonResponse(
      req,
      {
        error: "rate_limited",
        message: "Too many login attempts. Try again later.",
        retry_after_seconds: RATE_LIMIT_WINDOW_MINUTES * 60,
      },
      429,
    );
  }

  let body: Record<string, unknown>;
  try {
    body = (await req.json()) as Record<string, unknown>;
  } catch {
    return jsonResponse(req, { error: "invalid_request" }, 400);
  }

  const username = body.username;
  const password = body.password;
  if (!isNonEmptyString(username, 64) || !isNonEmptyString(password, 128)) {
    return jsonResponse(req, { error: "invalid_request", message: "username and password are required" }, 400);
  }

  // --- 1. Staff login path (no Linways handshake) -----------------------------
  // Staff (hod/technician/operations/admin) are not Linways users. A matching
  // staff profile routes to a direct Supabase password check; the returned
  // profile keeps the staff role (the app renders the matching panel). The
  // single shared demo account (role admin) can open every panel through the
  // app's panel switcher; real per-role staff accounts work the same way.
  // Students always continue to the Linways handshake below (their Linways
  // usernames never match a staff profile email).
  const STAFF_ROLES = new Set(["hod", "technician", "operations", "admin"]);
  const { data: staffMatch } = await serviceDb
    .from("profiles")
    .select("id, email, full_name, role, department_id, semester, section")
    .eq("email", username.trim().toLowerCase())
    .maybeSingle();
  if (staffMatch && STAFF_ROLES.has(staffMatch.role as string)) {
    const { data: signIn, error: signInError } = await anonDb.auth.signInWithPassword({
      email: staffMatch.email as string,
      password,
    });
    if (signInError || !signIn.session) {
      await recordAttempt(serviceDb, ip, "failure");
      return jsonResponse(req, { error: "invalid_credentials", message: "Invalid username or password" }, 401);
    }
    await clearFailures(serviceDb, ip);
    await recordAttempt(serviceDb, ip, "success");
    return jsonResponse(req, {
      success: true,
      data: {
        supabase_session: {
          access_token: signIn.session.access_token,
          refresh_token: signIn.session.refresh_token,
        },
        profile: {
          id: staffMatch.id,
          full_name: staffMatch.full_name,
          email: staffMatch.email,
          role: staffMatch.role,
          department_id: staffMatch.department_id,
          semester: staffMatch.semester,
          section: staffMatch.section,
          student_id: null,
        },
        community: null,
        linways_session_cookies: [],
      },
    });
  }

  // --- 1. Linways handshake -------------------------------------------------
  let login: LinwaysLoginResult;
  try {
    login = await linwaysLogin(username, password);
  } catch {
    return jsonResponse(req, { error: "linways_unavailable", message: "Login service is temporarily unavailable" }, 502);
  }

  if (!login.ok) {
    // Only credential failures count toward the rate limit — Linways outages
    // and provisioning errors must never block legitimate students.
    await recordAttempt(serviceDb, ip, "failure");
    return jsonResponse(req, { error: "invalid_credentials", message: "Invalid username or password" }, 401);
  }

  // --- 2. Authoritative profile ----------------------------------------------
  let profile: LinwaysProfile | null;
  try {
    profile = await linwaysProfile(login.cookies, login.accessToken);
  } catch {
    return jsonResponse(req, { error: "profile_unavailable", message: "Could not load your profile" }, 502);
  }

  if (!profile) {
    return jsonResponse(req, { error: "profile_unavailable", message: "Could not load your profile" }, 502);
  }

  // --- 3. Server-side community derivation ------------------------------------
  const community = deriveCommunity(profile);

  try {
    // --- 4. Provision native Supabase Auth user (idempotent) ------------------
    const { userId, email } = await findOrCreateAuthUser(serviceDb, profile);

    // --- 5. Upsert profile -----------------------------------------------------
    const departmentId = await resolveDepartmentId(
      serviceDb,
      community ? community.course_code : null,
    );
    await upsertProfile(serviceDb, userId, profile, community, email, departmentId);

    // --- 6. Get-or-create community + activate membership ----------------------
    let communityRecord: DerivedCommunity | null = null;
    if (community) {
      const communityId = await getOrCreateCommunity(serviceDb, community);
      await activateMembershipWithRetry(serviceDb, userId, communityId);
      communityRecord = community;
    }

    // --- 7. Mint a real Supabase Auth session ----------------------------------
    const session = await mintSupabaseSession(serviceDb, anonDb, email);

    await clearFailures(serviceDb, ip);
    await recordAttempt(serviceDb, ip, "success");

    return jsonResponse(req, {
      success: true,
      data: {
        supabase_session: session,
        profile: {
          id: userId,
          full_name: profile.name,
          email,
          role: "student",
          department_id: departmentId,
          semester: normalizeSemester(profile.currentSem)
            ? Number(normalizeSemester(profile.currentSem)?.slice(1))
            : null,
          section: community ? community.section : null,
          student_id: profile.registerNo,
        },
        community: communityRecord,
        linways_session_cookies: login.cookies,
      },
    });
  } catch {
    return jsonResponse(req, { error: "provisioning_failed", message: "Account setup failed. Please try again." }, 500);
  }
});
