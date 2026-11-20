import { clientIp, HttpError, json, readJson, route, serve, unwrap } from "../_shared/http.js";
import { db } from "../_shared/db.js";
import { hashToken, newToken } from "../_shared/tokens.js";
import { questionnaireMail, sendMail } from "../_shared/mail.js";
import { verifyTurnstile } from "../_shared/turnstile.js";

const MAX_EMAILS = 3;
const questionnaireUrl = Deno.env.get("QUESTIONNAIRE_URL") ?? "https://peerproject.in/questionnaire";

async function findInvite(token) {
  if (typeof token !== "string" || !token || token.length > 100) throw new HttpError(404, "invite_invalid");
  const invite = await unwrap(
    db.from("questionnaire_invites")
      .select("id, expires_at, email_sends, started_at, submitted_at, mentors (display_name, email, cohort_id, cohorts (name))")
      .eq("token_hash", await hashToken(token))
      .maybeSingle(),
  );
  if (!invite) throw new HttpError(404, "invite_invalid");
  return invite;
}

function assertOpen(invite) {
  if (invite.submitted_at) throw new HttpError(409, "questionnaire_submitted");
  if (new Date(invite.expires_at) <= new Date()) throw new HttpError(410, "invite_expired");
}

async function show({ req }) {
  const invite = await findInvite(req.headers.get("x-questionnaire-token"));
  if (invite.submitted_at) return json({ submitted: true });
  assertOpen(invite);

  const questions = await unwrap(
    db.from("questionnaire_questions")
      .select("id, prompt")
      .eq("cohort_id", invite.mentors.cohort_id)
      .eq("is_active", true)
      .order("position"),
  );

  if (!invite.started_at) {
    await unwrap(db.from("questionnaire_invites").update({ started_at: new Date().toISOString() }).eq("id", invite.id));
  }

  return json({
    submitted: false,
    display_name: invite.mentors.display_name,
    expires_at: invite.expires_at,
    questions,
  });
}

async function email({ req }) {
  const { token } = await readJson(req);
  const invite = await findInvite(token);
  assertOpen(invite);
  if (invite.email_sends >= MAX_EMAILS) throw new HttpError(429, "email_limit");

  const person = { ...invite.mentors, cohort: invite.mentors.cohorts.name };
  await sendMail(questionnaireMail(person, `${questionnaireUrl}#${token}`, invite.expires_at));
  await unwrap(
    db.from("questionnaire_invites")
      .update({ email_sends: invite.email_sends + 1, last_emailed_at: new Date().toISOString() })
      .eq("id", invite.id),
  );

  return json({ status: "sent", emails_left: MAX_EMAILS - invite.email_sends - 1 });
}

async function reissue(address) {
  const invite = await unwrap(
    db.from("questionnaire_invites")
      .select("id, expires_at, email_sends, mentors!inner (display_name, email, cohorts (name))")
      .eq("mentors.email", address)
      .is("submitted_at", null)
      .gt("expires_at", new Date().toISOString())
      .order("created_at", { ascending: false })
      .limit(1)
      .maybeSingle(),
  );
  if (!invite || invite.email_sends >= MAX_EMAILS) return;

  const token = newToken();
  const person = { ...invite.mentors, cohort: invite.mentors.cohorts.name };
  await sendMail(questionnaireMail(person, `${questionnaireUrl}#${token}`, invite.expires_at));
  await unwrap(
    db.from("questionnaire_invites")
      .update({
        token_hash: await hashToken(token),
        email_sends: invite.email_sends + 1,
        last_emailed_at: new Date().toISOString(),
      })
      .eq("id", invite.id),
  );
}

async function recover({ req }) {
  const body = await readJson(req);
  await verifyTurnstile(body["cf-turnstile-response"], clientIp(req));
  const address = typeof body.email === "string" ? body.email.trim().toLowerCase() : "";
  if (!address || address.length > 254) throw new HttpError(400, "invalid_email");

  EdgeRuntime.waitUntil(reissue(address).catch((error) => console.error("recover", error)));
  return json({ status: "requested" }, 202);
}

async function submit({ req }) {
  const { token, answers } = await readJson(req);
  if (!Array.isArray(answers)) throw new HttpError(400, "invalid_input");
  if (typeof token !== "string" || !token || token.length > 100) throw new HttpError(404, "invite_invalid");
  await unwrap(db.rpc("submit_questionnaire", { invite_hash: await hashToken(token), answers }));
  return json({ status: "submitted" });
}

serve("questionnaire", [
  route("GET", "/", show),
  route("POST", "/", submit),
  route("POST", "/email", email),
  route("POST", "/recover", recover),
]);
