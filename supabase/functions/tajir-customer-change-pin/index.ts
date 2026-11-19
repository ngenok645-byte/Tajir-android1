import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (status: number, value: Record<string, unknown>) =>
  new Response(JSON.stringify(value), { status, headers: { ...cors, "Content-Type": "application/json" } });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json(405, { error: "POST required." });
  try {
    const token = (req.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "");
    if (!token) return json(401, { error: "Sign in before changing your PIN." });
    const body = await req.json();
    if (typeof body.current_pin !== "string" || !/^[0-9]{4}$/.test(body.current_pin) ||
        typeof body.new_pin !== "string" || !/^[0-9]{4}$/.test(body.new_pin)) {
      return json(400, { error: "Enter your current PIN and a new four-digit PIN." });
    }
    if (body.current_pin === body.new_pin) return json(400, { error: "Choose a new PIN different from your current PIN." });

    const url = Deno.env.get("SUPABASE_URL")!;
    const anon = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, { auth: { persistSession: false, autoRefreshToken: false } });
    const { data: authData, error: authError } = await anon.auth.getUser(token);
    if (authError || !authData.user) return json(401, { error: "Your session has expired. Sign in again." });

    const db = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false, autoRefreshToken: false } });
    const { data: profile, error: profileError } = await db.from("profiles").select("id,phone,status").eq("id", authData.user.id).maybeSingle();
    if (profileError) throw profileError;
    if (!profile || profile.status !== "active" || !profile.phone) return json(403, { error: "An active customer account is required to change this PIN." });

    const { data: customer, error: customerError } = await db.from("customers").select("id,active").eq("profile_id", authData.user.id).maybeSingle();
    if (customerError) throw customerError;
    if (!customer || customer.active !== true) return json(403, { error: "An active customer account is required to change this PIN." });

    const { data: verified, error: verifyError } = await db.rpc("authenticate_tajir_customer_pin", { p_phone: profile.phone, p_pin: body.current_pin });
    if (verifyError) throw verifyError;
    if (!verified?.success || verified.user_id !== authData.user.id) {
      const seconds = Number(verified?.retry_after_seconds || 0);
      return json(verified?.locked ? 429 : 401, {
        error: verified?.locked ? "Too many incorrect PIN attempts. Please wait before trying again." : "Your current PIN is incorrect.",
        retry_after_seconds: seconds,
        remaining_attempts: verified?.remaining_attempts ?? 0,
      });
    }

    const { error: updateError } = await db.rpc("set_tajir_customer_pin", { p_user_id: authData.user.id, p_pin: body.new_pin });
    if (updateError) throw updateError;
    return json(200, { success: true });
  } catch (e) {
    return json(400, { error: e instanceof Error ? e.message : "Could not change PIN." });
  }
});