import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (status: number, value: Record<string, unknown>) =>
  new Response(JSON.stringify(value), { status, headers: { ...cors, "Content-Type": "application/json" } });

function normalizePhone(value: string) {
  const d = value.replace(/[^0-9]/g, "");
  if (d.startsWith("254") && d.length === 12) return `+${d}`;
  if (d.startsWith("0") && d.length === 10) return `+254${d.slice(1)}`;
  if (d.length === 9) return `+254${d}`;
  throw new Error("Enter a valid Kenyan phone number.");
}
const loginEmail = (phone: string) => `u${phone.replace(/[^0-9]/g, "")}@login.tajir.app`;
const authPassword = (pin: string) => `TAJIR-PIN-${pin}-Account#2026`;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json(405, { error: "POST required." });
  try {
    const body = await req.json();
    if (typeof body.phone !== "string" || typeof body.pin !== "string" || !/^\d{4}$/.test(body.pin))
      return json(400, { error: "Enter a valid phone number and four-digit PIN." });
    const phone = normalizePhone(body.phone);
    const localPhone = `0${phone.slice(4)}`;
    const url = Deno.env.get("SUPABASE_URL");
    const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!url || !key) return json(500, { error: "Authentication service is not configured." });
    const db = createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });

    const { data: profiles, error: pErr } = await db.from("profiles")
      .select("id,phone,status,director_bootstrap_claimed_at")
      .in("phone", [body.phone.trim(), localPhone, phone]).limit(2);
    if (pErr) throw pErr;
    if (!profiles || profiles.length !== 1) return json(403, { error: "No unique pre-registered Director profile matches this phone." });
    const p = profiles[0];
    if (p.status !== "active" || p.director_bootstrap_claimed_at)
      return json(409, { error: "Director setup has already been completed. Please sign in." });

    const { data: roles, error: rErr } = await db.from("user_role_assignments")
      .select("app_roles!inner(code)").eq("user_id", p.id).eq("is_active", true);
    if (rErr) throw rErr;
    if (!roles?.some((r: any) => r.app_roles?.code === "director"))
      return json(403, { error: "This account is not assigned the Director role." });

    const claimedAt = new Date().toISOString();
    const { data: claim, error: cErr } = await db.from("profiles")
      .update({ director_bootstrap_claimed_at: claimedAt }).eq("id", p.id)
      .is("director_bootstrap_claimed_at", null).select("id");
    if (cErr) throw cErr;
    if (!claim?.length) return json(409, { error: "Director setup has already been claimed." });

    const { error: authErr } = await db.auth.admin.updateUserById(p.id, {
      email: loginEmail(phone), email_confirm: true, password: authPassword(body.pin),
    });
    if (authErr) {
      await db.from("profiles").update({ director_bootstrap_claimed_at: null })
        .eq("id", p.id).eq("director_bootstrap_claimed_at", claimedAt);
      throw authErr;
    }
    return json(200, { success: true, message: "Director account is ready. Sign in with phone and PIN." });
  } catch (e) {
    return json(400, { error: e instanceof Error ? e.message : "Setup failed." });
  }
});
