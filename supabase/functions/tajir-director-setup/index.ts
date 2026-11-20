import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (status: number, value: Record<string, unknown>) =>
  new Response(JSON.stringify(value), { status, headers: { ...cors, "Content-Type": "application/json", "Cache-Control": "no-store" } });

function normalizePhone(value: string): string {
  const digits = value.replace(/[^0-9]/g, "");
  if (digits.startsWith("254") && digits.length === 12) return "+" + digits;
  if (digits.startsWith("0") && digits.length === 10) return "+254" + digits.slice(1);
  if (digits.length === 9) return "+254" + digits;
  throw new Error("Enter a valid Kenyan phone number.");
}
const loginEmail = (phone: string) => "u" + phone.replace(/[^0-9]/g, "") + "@login.tajir.app";

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json(405, { error: "POST required." });
  try {
    const body = await req.json();
    if (typeof body.phone !== "string" || typeof body.pin !== "string" ||
        !/^[0-9]{4}$/.test(body.pin) ||
        typeof body.verification_id !== "string" ||
        !/^[0-9a-f-]{36}$/i.test(body.verification_id)) {
      return json(400, { error: "Verify your registered Director phone and enter a four-digit PIN." });
    }

    const phone = normalizePhone(body.phone);
    const localPhone = "0" + phone.slice(4);
    const url = Deno.env.get("SUPABASE_URL");
    const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!url || !key) return json(500, { error: "Authentication service is not configured." });
    const db = createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });

    const { data: profiles, error } = await db.from("profiles")
      .select("id,status,director_bootstrap_claimed_at")
      .in("phone", [body.phone.trim(), localPhone, phone])
      .limit(2);
    if (error) throw error;
    if (!profiles || profiles.length !== 1) return json(403, { error: "No unique Director account matches this phone." });

    const profile = profiles[0];
    if (profile.status !== "active" || !profile.director_bootstrap_claimed_at) {
      return json(403, { error: "Director account has not completed its approved setup." });
    }
    const { data: roles, error: roleError } = await db.from("user_role_assignments")
      .select("app_roles!inner(code)")
      .eq("user_id", profile.id)
      .eq("is_active", true);
    if (roleError) throw roleError;
    if (!roles?.some((row: any) => row.app_roles?.code === "director")) {
      return json(403, { error: "This account is not assigned the Director role." });
    }

    const { data: verification, error: verificationError } = await db.from("tajir_phone_verifications")
      .update({ consumed_at: new Date().toISOString() })
      .eq("id", body.verification_id)
      .eq("phone_e164", phone)
      .eq("purpose", "director_setup")
      .not("verified_at", "is", null)
      .is("consumed_at", null)
      .gt("expires_at", new Date().toISOString())
      .select("id")
      .maybeSingle();
    if (verificationError) throw verificationError;
    if (!verification) return json(403, { error: "Verify control of the registered Director phone before setting a PIN." });

    const { error: updateError } = await db.auth.admin.updateUserById(profile.id, {
      email: loginEmail(phone),
      password: "TAJIR-PIN-" + body.pin + "-Account#2026",
      email_confirm: true,
    });
    if (updateError) throw updateError;
    return json(200, { success: true, message: "Director phone login has been prepared. Sign in using your PIN." });
  } catch (error) {
    return json(400, { error: error instanceof Error ? error.message : "Director login setup failed." });
  }
});
