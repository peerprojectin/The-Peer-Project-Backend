import { clientIp, HttpError, json, readJson, route, serve, unwrap } from "../_shared/http.js";
import { db, proofs } from "../_shared/db.js";
import { decisionMail, lockoutMail, probeMail, sendMail } from "../_shared/mail.js";

const PROOF_LINK_SECONDS = 60;

const kinds = {
  mentee: {
    table: "mentees",
    summary: "id, cohort_id, status, display_name, age, class_level, tracks, is_verified, decided_at, created_at",
    detail: "*, mentee_help_areas (track, area, area_other), assignments (id, mentor_id, status)",
    statuses: ["pending", "accepted", "waitlisted", "rejected", "withdrawn"],
  },
  mentor: {
    table: "mentors",
    summary: "id, cohort_id, status, display_name, current_status, tracks, mentee_levels, mentor_capacity, is_verified, decided_at, created_at, questionnaire_invites (started_at, submitted_at, expires_at)",
    detail: "*, mentor_help_areas (track, area, area_other), questionnaire_invites (started_at, submitted_at, expires_at, email_sends), questionnaire_answers (answer, questionnaire_questions (position, prompt)), mentor_reviews (reviewer_id, empathy, boundaries, practicality, honesty, notes, decision, created_at, admins (display_name)), assignments (id, mentee_id, status)",
    statuses: ["pending", "shortlisted", "accepted", "rejected", "withdrawn"],
  },
};

const closingStatuses = new Set(["accepted", "rejected", "withdrawn"]);
const scoreFields = ["empathy", "boundaries", "practicality", "honesty"];
const cohortFields = ["mentee_opens_at", "mentee_closes_at", "mentor_opens_at", "mentor_closes_at", "ends_at"];

async function authenticate(req, matched) {
  const jwt = req.headers.get("authorization")?.replace(/^Bearer\s+/i, "");
  if (!jwt) throw new HttpError(401, "unauthenticated");

  const { data, error } = await db.auth.getUser(jwt);
  if (error || !data.user) throw new HttpError(401, "unauthenticated");

  const admin = await unwrap(
    db.from("admins").select("id, role, display_name").eq("user_id", data.user.id).maybeSingle(),
  );
  if (!admin) throw new HttpError(403, "not_an_admin");
  if (matched.role === "admin" && admin.role !== "admin") throw new HttpError(403, "admins_only");
  return { admin };
}

function kindOf(params) {
  const kind = { mentees: kinds.mentee, mentors: kinds.mentor }[params.kind];
  if (!kind) throw new HttpError(404, "not_found");
  return kind;
}

function idOf(params) {
  const id = Number(params.id);
  if (!Number.isSafeInteger(id) || id <= 0) throw new HttpError(404, "not_found");
  return id;
}

function pick(body, fields) {
  return Object.fromEntries(fields.filter((field) => field in body).map((field) => [field, body[field]]));
}

const ALERT_ADDRESS = "administrator@peerproject.in";

async function alertAdmins(address, ip, lockedUntil) {
  const admins = await unwrap(db.from("admins").select("email"));
  const adminEmails = new Set(admins.map((admin) => admin.email.toLowerCase()));
  const to = [...new Set([ALERT_ADDRESS, ...adminEmails])];

  if (adminEmails.has(address)) {
    await sendMail(lockoutMail(to, address, ip, lockedUntil));
    return;
  }

  const claimed = await unwrap(db.rpc("claim_alert", { alert_kind: "login_probe", cooldown: "24 hours" }));
  if (!claimed) return;
  const since = new Date(Date.now() - 86_400_000).toISOString();
  const locks = await unwrap(
    db.from("login_attempts").select("email, last_ip").not("locked_until", "is", null).gte("updated_at", since),
  );
  const probes = locks.filter((lock) => !adminEmails.has(lock.email));
  const ips = [...new Set(probes.map((lock) => lock.last_ip ?? "unknown"))];
  await sendMail(probeMail(to, probes.length, ips));
}

async function login({ req }) {
  const { email, password, captcha } = await readJson(req, 4000);
  const address = typeof email === "string" ? email.trim().toLowerCase() : "";
  if (!address || typeof password !== "string" || !password) throw new HttpError(400, "invalid_input");

  const existing = await unwrap(db.from("login_attempts").select("locked_until").eq("email", address).maybeSingle());
  if (existing?.locked_until && new Date(existing.locked_until) > new Date()) {
    return json({ error: "locked", locked_until: existing.locked_until }, 429);
  }

  const response = await fetch(`${Deno.env.get("SUPABASE_URL")}/auth/v1/token?grant_type=password`, {
    method: "POST",
    headers: { apikey: Deno.env.get("SUPABASE_ANON_KEY"), "content-type": "application/json" },
    body: JSON.stringify({
      email: address,
      password,
      ...(typeof captcha === "string" && captcha ? { gotrue_meta_security: { captcha_token: captcha } } : {}),
    }),
  });
  const data = await response.json().catch(() => ({}));

  if (response.ok) {
    await unwrap(db.from("login_attempts").delete().eq("email", address));
    return json({ access_token: data.access_token, refresh_token: data.refresh_token, expires_at: data.expires_at });
  }
  if (`${data.error_code ?? ""} ${data.msg ?? ""}`.toLowerCase().includes("captcha")) {
    throw new HttpError(400, "captcha_failed");
  }
  if (response.status !== 400) {
    console.error("auth", response.status, data);
    throw new HttpError(502, "auth_unavailable");
  }

  const ip = clientIp(req);
  const [result] = await unwrap(db.rpc("record_login_failure", { attempt_email: address, attempt_ip: ip }));
  if (result.just_locked) await alertAdmins(address, ip, result.lock_expires_at).catch((error) => console.error("alert", error));
  if (result.lock_expires_at) return json({ error: "locked", locked_until: result.lock_expires_at }, 429);
  return json({ error: "invalid_credentials", attempts_left: Math.max(0, 3 - result.attempt_count) }, 401);
}

async function me({ admin }) {
  return json(admin);
}

async function listCohorts() {
  return json(await unwrap(db.from("cohorts").select("*").order("id", { ascending: false })));
}

async function updateCohort({ req, params }) {
  const changes = pick(await readJson(req), cohortFields);
  if (Object.keys(changes).length === 0) throw new HttpError(400, "invalid_input");
  return json(await unwrap(db.from("cohorts").update(changes).eq("id", idOf(params)).select().single()));
}

async function listApplicants({ params, url }) {
  const kind = kindOf(params);
  let query = db.from(kind.table).select(kind.summary).order("created_at");
  const cohort = url.searchParams.get("cohort_id");
  const status = url.searchParams.get("status");
  if (cohort) query = query.eq("cohort_id", cohort);
  if (status) query = query.eq("status", status);
  return json(await unwrap(query));
}

async function getApplicant({ params }) {
  const kind = kindOf(params);
  const row = await unwrap(db.from(kind.table).select(kind.detail).eq("id", idOf(params)).maybeSingle());
  if (!row) throw new HttpError(404, "not_found");

  if (kind.table === "mentors") {
    row.has_proof = Boolean(row.proof_path && !row.proof_deleted_at);
    delete row.proof_path;
    row.questionnaire_answers?.sort((a, b) => a.questionnaire_questions.position - b.questionnaire_questions.position);
  }
  return json(row);
}

async function setVerified({ req, params }) {
  const kind = kindOf(params);
  const { is_verified } = await readJson(req);
  if (typeof is_verified !== "boolean") throw new HttpError(400, "invalid_input");
  await unwrap(db.from(kind.table).update({ is_verified }).eq("id", idOf(params)));
  return json({ is_verified });
}

async function deleteProof(mentor) {
  if (!mentor.proof_path || mentor.proof_deleted_at) return;
  const { error } = await proofs.remove([mentor.proof_path]);
  if (error) {
    console.error(error);
    throw new HttpError(500, "proof_delete_failed");
  }
  await unwrap(db.from("mentors").update({ proof_deleted_at: new Date().toISOString() }).eq("id", mentor.id));
}

async function decide({ req, params }) {
  const kind = kindOf(params);
  const { status } = await readJson(req);
  if (!kind.statuses.includes(status)) throw new HttpError(400, "invalid_status");

  const columns = kind.table === "mentors"
    ? "id, display_name, email, status, decided_at, proof_path, proof_deleted_at, cohorts (name)"
    : "id, display_name, email, status, decided_at, cohorts (name)";
  const person = await unwrap(db.from(kind.table).select(columns).eq("id", idOf(params)).maybeSingle());
  if (!person) throw new HttpError(404, "not_found");
  if (person.status === status) throw new HttpError(409, "status_unchanged");

  const kindName = kind.table.slice(0, -1);
  if (kindName === "mentor" && closingStatuses.has(status)) await deleteProof(person);

  const mail = decisionMail(kindName, status, { ...person, cohort: person.cohorts.name });
  if (mail) await sendMail(mail);

  const changes = { status, decided_at: mail ? new Date().toISOString() : person.decided_at };
  await unwrap(db.from(kind.table).update(changes).eq("id", person.id));
  return json({ status, emailed: Boolean(mail) });
}

async function viewProof({ params, admin }) {
  const id = idOf(params);
  const mentor = await unwrap(db.from("mentors").select("proof_path, proof_deleted_at").eq("id", id).maybeSingle());
  if (!mentor?.proof_path || mentor.proof_deleted_at) throw new HttpError(404, "proof_unavailable");

  const { data, error } = await proofs.createSignedUrl(mentor.proof_path, PROOF_LINK_SECONDS);
  if (error) {
    console.error(error);
    throw new HttpError(500, "proof_link_failed");
  }
  await unwrap(db.from("proof_access_log").insert({ mentor_id: id, admin_id: admin.id }));
  return json({ url: data.signedUrl, expires_in: PROOF_LINK_SECONDS });
}

async function review({ req, params, admin }) {
  const body = await readJson(req);
  const row = {
    mentor_id: idOf(params),
    reviewer_id: admin.id,
    ...pick(body, [...scoreFields, "notes", "decision"]),
  };
  const saved = await unwrap(
    db.from("mentor_reviews").upsert(row, { onConflict: "mentor_id,reviewer_id" }).select().single(),
  );
  return json(saved);
}

async function listAssignments({ url }) {
  let query = db.from("assignments")
    .select("*, mentees (display_name), mentors (display_name)")
    .order("created_at");
  const cohort = url.searchParams.get("cohort_id");
  if (cohort) query = query.eq("cohort_id", cohort);
  return json(await unwrap(query));
}

async function createAssignment({ req }) {
  const { mentee_id, mentor_id } = await readJson(req);
  const [mentee, mentor] = await Promise.all([
    unwrap(db.from("mentees").select("cohort_id, status").eq("id", mentee_id).maybeSingle()),
    unwrap(db.from("mentors").select("cohort_id, status, mentor_capacity").eq("id", mentor_id).maybeSingle()),
  ]);
  if (!mentee || !mentor) throw new HttpError(404, "not_found");
  if (mentee.status !== "accepted" || mentor.status !== "accepted") throw new HttpError(409, "not_accepted");
  if (mentee.cohort_id !== mentor.cohort_id) throw new HttpError(409, "different_cohorts");

  const { count, error } = await db.from("assignments")
    .select("id", { count: "exact", head: true })
    .eq("mentor_id", mentor_id)
    .in("status", ["pending", "active"]);
  if (error) throw new HttpError(500, "database_error");
  if (count >= mentor.mentor_capacity) throw new HttpError(409, "mentor_full");

  const created = await unwrap(
    db.from("assignments").insert({ cohort_id: mentee.cohort_id, mentee_id, mentor_id }).select().single(),
  );
  return json(created, 201);
}

async function updateAssignment({ req, params }) {
  const { status } = await readJson(req);
  if (!["pending", "active", "completed", "cancelled"].includes(status)) throw new HttpError(400, "invalid_status");
  return json(await unwrap(db.from("assignments").update({ status }).eq("id", idOf(params)).select().single()));
}

serve("admin", [
  route("POST", "/login", login, { public: true }),
  route("GET", "/me", me),
  route("GET", "/cohorts", listCohorts),
  route("PATCH", "/cohorts/:id", updateCohort, { role: "admin" }),
  route("GET", "/assignments", listAssignments),
  route("POST", "/assignments", createAssignment, { role: "admin" }),
  route("PATCH", "/assignments/:id", updateAssignment, { role: "admin" }),
  route("GET", "/mentors/:id/proof", viewProof, { role: "admin" }),
  route("PUT", "/mentors/:id/review", review),
  route("GET", "/:kind", listApplicants),
  route("GET", "/:kind/:id", getApplicant),
  route("POST", "/:kind/:id/verified", setVerified, { role: "admin" }),
  route("POST", "/:kind/:id/status", decide, { role: "admin" }),
], { before: authenticate });
