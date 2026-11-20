import { HttpError } from "./http.js";

export async function verifyTurnstile(token, ip) {
  if (!token) throw new HttpError(400, "captcha_missing");

  const body = new FormData();
  body.set("secret", Deno.env.get("TURNSTILE_SECRET"));
  body.set("response", token);
  if (ip) body.set("remoteip", ip);

  const response = await fetch("https://challenges.cloudflare.com/turnstile/v0/siteverify", { method: "POST", body });
  const result = await response.json();
  if (!result.success) throw new HttpError(400, "captcha_failed");
}
