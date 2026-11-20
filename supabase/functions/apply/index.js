import { clientIp, HttpError, json, route, serve, unwrap } from "../_shared/http.js";
import { db, proofs } from "../_shared/db.js";
import { verifyTurnstile } from "../_shared/turnstile.js";
import { hashToken, newToken } from "../_shared/tokens.js";

const MAX_PROOF_BYTES = 5 * 1024 * 1024;
const INVITE_DAYS = 7;

const proofTypes = [
  { type: "application/pdf", ext: "pdf", magic: [0x25, 0x50, 0x44, 0x46] },
  { type: "image/png", ext: "png", magic: [0x89, 0x50, 0x4e, 0x47] },
  { type: "image/jpeg", ext: "jpg", magic: [0xff, 0xd8, 0xff] },
];

function isOpen(opensAt, closesAt, now) {
  return Boolean(opensAt) && new Date(opensAt) <= now && (!closesAt || new Date(closesAt) > now);
}

const OPTIONS_TTL_MS = 10 * 60 * 1000;
let cachedOptions = null;

async function helpAreaOptions() {
  if (cachedOptions && cachedOptions.at > Date.now() - OPTIONS_TTL_MS) return cachedOptions.value;
  const rows = await unwrap(db.from("help_area_options").select("track, area, label").order("track").order("position"));
  const value = {};
  for (const { track, area, label } of rows) (value[track] ??= []).push({ area, label });
  cachedOptions = { at: Date.now(), value };
  return value;
}

async function overview() {
  const [cohort, helpAreas] = await Promise.all([
    unwrap(
      db.from("cohorts")
        .select("name, mentee_opens_at, mentee_closes_at, mentor_opens_at, mentor_closes_at")
        .order("id", { ascending: false })
        .limit(1)
        .maybeSingle(),
    ),
    helpAreaOptions(),
  ]);

  const now = new Date();
  const response = json({
    cohort: cohort && {
      name: cohort.name,
      mentee: { opens_at: cohort.mentee_opens_at, closes_at: cohort.mentee_closes_at, open: isOpen(cohort.mentee_opens_at, cohort.mentee_closes_at, now) },
      mentor: { opens_at: cohort.mentor_opens_at, closes_at: cohort.mentor_closes_at, open: isOpen(cohort.mentor_opens_at, cohort.mentor_closes_at, now) },
    },
    help_areas: helpAreas,
  });
  response.headers.set("cache-control", "public, max-age=60");
  return response;
}

function normalise(application) {
  if (!application || typeof application !== "object" || Array.isArray(application)) {
    throw new HttpError(400, "invalid_input");
  }
  const clean = {};
  for (const [key, value] of Object.entries(application)) {
    clean[key] = typeof value === "string" ? value.trim() : value;
  }
  clean.email = String(clean.email ?? "").toLowerCase();
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(clean.email) || clean.email.length > 254) {
    throw new HttpError(400, "invalid_email");
  }
  clean.discord_username = String(clean.discord_username ?? "").replace(/^@/, "");
  return clean;
}

async function readApplication(req) {
  if (!req.headers.get("content-type")?.startsWith("multipart/form-data")) {
    throw new HttpError(415, "multipart_required");
  }
  const form = await req.formData();
  let application;
  try {
    application = JSON.parse(form.get("application") ?? "");
  } catch {
    throw new HttpError(400, "invalid_json");
  }
  await verifyTurnstile(form.get("cf-turnstile-response"), clientIp(req));
  return { application: normalise(application), proof: form.get("proof") };
}

async function readProof(file) {
  if (!(file instanceof File) || file.size === 0) throw new HttpError(400, "proof_missing");
  if (file.size > MAX_PROOF_BYTES) throw new HttpError(413, "proof_too_large");
  const bytes = new Uint8Array(await file.arrayBuffer());
  const kind = proofTypes.find(({ magic }) => magic.every((byte, i) => bytes[i] === byte));
  if (!kind) throw new HttpError(415, "proof_type");
  return { bytes, ...kind };
}

async function applyMentee({ req }) {
  const { application } = await readApplication(req);
  await unwrap(db.rpc("submit_mentee", { application }));
  return json({ status: "received" }, 201);
}

async function applyMentor({ req }) {
  const { application, proof } = await readApplication(req);
  const file = await readProof(proof);

  const path = `${crypto.randomUUID()}.${file.ext}`;
  const { error: uploadError } = await proofs.upload(path, file.bytes, { contentType: file.type });
  if (uploadError) {
    console.error(uploadError);
    throw new HttpError(500, "proof_upload_failed");
  }

  const token = newToken();
  try {
    await unwrap(db.rpc("submit_mentor", { application, proof: path, invite_hash: await hashToken(token) }));
  } catch (error) {
    await proofs.remove([path]);
    throw error;
  }

  const expiresAt = new Date(Date.now() + INVITE_DAYS * 86_400_000).toISOString();
  return json({ status: "received", questionnaire_token: token, questionnaire_expires_at: expiresAt }, 201);
}

serve("apply", [
  route("GET", "/", overview),
  route("POST", "/mentee", applyMentee),
  route("POST", "/mentor", applyMentor),
]);
