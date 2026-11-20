import { db, proofs } from "../_shared/db.js";

const RETENTION_DAYS = 30;
const BATCH = 500;

Deno.serve(async (req) => {
  const secret = Deno.env.get("PURGE_SECRET");
  if (!secret || req.headers.get("x-purge-secret") !== secret) {
    return new Response("forbidden", { status: 403 });
  }

  const cutoff = new Date(Date.now() - RETENTION_DAYS * 86_400_000).toISOString();
  const { data: rows, error } = await db
    .from("mentors")
    .select("id, proof_path")
    .not("proof_path", "is", null)
    .is("proof_deleted_at", null)
    .lt("proof_uploaded_at", cutoff)
    .limit(BATCH);
  if (error) return new Response(error.message, { status: 500 });
  if (rows.length === 0) return Response.json({ deleted: 0 });

  const { error: removeError } = await proofs.remove(rows.map((row) => row.proof_path));
  if (removeError) return new Response(removeError.message, { status: 500 });

  const { error: updateError } = await db
    .from("mentors")
    .update({ proof_deleted_at: new Date().toISOString() })
    .in("id", rows.map((row) => row.id));
  if (updateError) return new Response(updateError.message, { status: 500 });

  return Response.json({ deleted: rows.length });
});
