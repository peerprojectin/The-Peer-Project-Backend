const allowedOrigins = new Set(
  (Deno.env.get("ALLOWED_ORIGINS") ?? "https://peerproject.in")
    .split(",")
    .map((origin) => origin.trim())
    .filter(Boolean),
);

const raisedCodes = {
  applications_closed: 403,
  help_area_track: 400,
  invite_invalid: 404,
  invite_expired: 410,
  questionnaire_submitted: 409,
  answers_incomplete: 400,
};

const invalidInputCodes = new Set(["22P02", "22003", "22001", "22007", "22008", "23502", "23503", "23514"]);

export class HttpError extends Error {
  constructor(status, code) {
    super(code);
    this.status = status;
    this.code = code;
  }
}

export function json(body, status = 200) {
  return Response.json(body, { status });
}

export function fromDatabase(error) {
  if (error.code === "P0001" && raisedCodes[error.message]) {
    return new HttpError(raisedCodes[error.message], error.message);
  }
  if (error.code === "23505") return new HttpError(409, "already_exists");
  if (invalidInputCodes.has(error.code)) return new HttpError(400, "invalid_input");
  console.error(error);
  return new HttpError(500, "database_error");
}

export async function unwrap(query) {
  const { data, error } = await query;
  if (error) throw fromDatabase(error);
  return data;
}

export async function readJson(req, limit = 100_000) {
  const text = await req.text();
  if (text.length > limit) throw new HttpError(413, "too_large");
  try {
    return JSON.parse(text || "{}");
  } catch {
    throw new HttpError(400, "invalid_json");
  }
}

export function clientIp(req) {
  return req.headers.get("x-forwarded-for")?.split(",")[0].trim() ?? null;
}

function corsHeaders(origin) {
  return {
    "access-control-allow-origin": origin,
    "access-control-allow-methods": "GET, POST, PUT, PATCH, OPTIONS",
    "access-control-allow-headers": "authorization, content-type, x-questionnaire-token",
    "access-control-max-age": "600",
    vary: "origin",
  };
}

function matchRoute(routes, method, parts) {
  for (const route of routes) {
    if (route.method !== method || route.path.length !== parts.length) continue;
    const params = {};
    const matched = route.path.every((segment, i) => {
      if (segment.startsWith(":")) {
        params[segment.slice(1)] = parts[i];
        return true;
      }
      return segment === parts[i];
    });
    if (matched) return { route, params };
  }
  return null;
}

export function route(method, path, handler, options = {}) {
  return { method, path: path.split("/").filter(Boolean), handler, ...options };
}

export function serve(name, routes, { before } = {}) {
  Deno.serve(async (req) => {
    const origin = req.headers.get("origin");
    if (origin && !allowedOrigins.has(origin)) return new Response(null, { status: 403 });
    const cors = origin ? corsHeaders(origin) : {};

    if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: cors });

    let response;
    try {
      const url = new URL(req.url);
      const segments = url.pathname.split("/").filter(Boolean);
      const parts = segments.slice(segments.indexOf(name) + 1);
      const found = matchRoute(routes, req.method, parts);
      if (!found) throw new HttpError(404, "not_found");
      const context = { req, url, params: found.params };
      if (before && !found.route.public) Object.assign(context, await before(req, found.route));
      response = await found.route.handler(context);
    } catch (error) {
      if (!(error instanceof HttpError)) console.error(error);
      const status = error instanceof HttpError ? error.status : 500;
      response = json({ error: error instanceof HttpError ? error.code : "internal_error" }, status);
    }

    for (const [key, value] of Object.entries(cors)) response.headers.set(key, value);
    return response;
  });
}
