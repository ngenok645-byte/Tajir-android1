import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const response = (status: number, body: Record<string, unknown>) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

function normalizePhone(input: unknown): { e164: string; variants: string[] } | null {
  if (typeof input !== "string") return null;
  let digits = input.replace(/[^0-9]/g, "");
  if (digits.startsWith("0") && digits.length === 10) digits = "254" + digits.slice(1);
  else if ((digits.startsWith("7") || digits.startsWith("1")) && digits.length === 9) digits = "254" + digits;
  if (!/^254[17][0-9]{8}$/.test(digits)) return null;
  return { e164: "+" + digits, variants: ["+" + digits, digits, "0" + digits.slice(3), digits.slice(3)] };
}
function generateCode(): string {
  const bytes = new Uint32Array(1);
  crypto.getRandomValues(bytes);
  return String(bytes[0] % 1_000_000).padStart(6, "0");
}
async function hmac(secret: string, value: string): Promise<string> {
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const signed = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(value));
  return Array.from(new Uint8Array(signed), b => b.toString(16).padStart(2, "0")).join("");
}
function constantTimeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let mismatch = 0;
  for (let i = 0; i < a.length; i++) mismatch |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return mismatch === 0;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return response(405, { error: "POST required." });
  try {
    const body = await req.json();
    const phone = normalizePhone(body?.phone);
    if (!phone || !["request", "verify"].includes(body?.action)) {
      return response(400, { error: "Enter a valid Kenyan staff phone number." });
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const atUsername = Deno.env.get("AFRICASTALKING_USERNAME");
    const atApiKey = Deno.env.get("AFRICASTALKING_API_KEY");
    if (!supabaseUrl || !serviceKey || !atUsername || !atApiKey) {
      return response(503, { error: "Staff PIN recovery is temporarily unavailable." });
    }
    const db = createClient(supabaseUrl, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });

    const { data: profiles, error: profileError } = await db.from("profiles")
      .select("id,phone,status").in("phone", phone.variants).eq("status", "active").limit(2);
    if (profileError) throw profileError;
    if (!profiles || profiles.length !== 1) {
      return response(200, { success: true, message: "If an active staff account matches this number, a verification code will be sent." });
    }
    const profile = profiles[0];

    const allowedRoles = ["director", "accountant", "branch_manager", "worker", "supplier", "tractor_owner", "driver", "mechanic", "auto_spares_owner"];
    const { data: assignments, error: roleError } = await db.from("user_role_assignments")
      .select("id,app_roles!inner(code)").eq("user_id", profile.id).eq("is_active", true)
      .in("app_roles.code", allowedRoles);
    if (roleError) throw roleError;
    if (!assignments || assignments.length === 0) {
      return response(200, { success: true, message: "If an active staff account matches this number, a verification code will be sent." });
    }

    if (body.action === "request") {
      const now = new Date();
      const { data: recent, error: recentError } = await db.from("tajir_staff_pin_resets")
        .select("created_at").eq("profile_id", profile.id)
        .gte("created_at", new Date(now.getTime() - 24 * 60 * 60_000).toISOString())
        .order("created_at", { ascending: false }).limit(5);
      if (recentError) throw recentError;
      if (recent?.length && now.getTime() - new Date(recent[0].created_at).getTime() < 60_000) {
        return response(429, { error: "Please wait one minute before requesting another code." });
      }
      if ((recent?.length ?? 0) >= 5) return response(429, { error: "Too many recovery requests. Try again later." });

      const otp = generateCode();
      const codeHash = await hmac(atApiKey, profile.id + ":" + phone.e164 + ":" + otp);
      await db.from("tajir_staff_pin_resets").update({ consumed_at: now.toISOString() })
        .eq("profile_id", profile.id).is("consumed_at", null);
      const { error: insertError } = await db.from("tajir_staff_pin_resets").insert({
        profile_id: profile.id, phone_e164: phone.e164, code_hash: codeHash,
        expires_at: new Date(now.getTime() + 5 * 60_000).toISOString(),
      });
      if (insertError) throw insertError;

      const form = new URLSearchParams({
        username: atUsername,
        to: phone.e164,
        message: "Your TAJIR staff PIN reset code is " + otp + ". It expires in 5 minutes. Do not share it.",
      });
      const sms = await fetch("https://api.africastalking.com/version1/messaging", {
        method: "POST",
        headers: { apiKey: atApiKey, Accept: "application/json", "Content-Type": "application/x-www-form-urlencoded" },
        body: form.toString(),
      });
      const smsText = await sms.text();
      if (!sms.ok) {
        await db.from("tajir_staff_pin_resets").update({ consumed_at: new Date().toISOString() })
          .eq("profile_id", profile.id).is("consumed_at", null);
        console.error("Africa's Talking staff recovery SMS failed", sms.status, smsText.slice(0, 400));
        return response(503, { error: "TAJIR could not send the SMS. Check SMS credits and sender approval." });
      }
      try {
        const parsed = JSON.parse(smsText);
        const recipients = parsed?.SMSMessageData?.Recipients;
        if (Array.isArray(recipients) && recipients.length && !recipients.some((r: { statusCode?: number }) => r.statusCode === 101)) {
          return response(503, { error: "The SMS provider did not accept the message. Check credits and sender approval." });
        }
      } catch { /* provider may return an empty successful response */ }
      return response(200, { success: true, message: "A verification code has been sent if the account is eligible." });
    }

    if (typeof body.code !== "string" || !/^[0-9]{6}$/.test(body.code) ||
        typeof body.new_pin !== "string" || !/^[0-9]{4}$/.test(body.new_pin)) {
      return response(400, { error: "Enter the six-digit SMS code and a new four-digit PIN." });
    }
    const { data: reset, error: resetError } = await db.from("tajir_staff_pin_resets")
      .select("id,code_hash,expires_at,attempts").eq("profile_id", profile.id)
      .eq("phone_e164", phone.e164).is("consumed_at", null)
      .order("created_at", { ascending: false }).limit(1).maybeSingle();
    if (resetError) throw resetError;
    if (!reset || new Date(reset.expires_at).getTime() <= Date.now() || reset.attempts >= 6) {
      return response(400, { error: "The code is invalid or expired. Request a new code." });
    }
    const candidate = await hmac(atApiKey, profile.id + ":" + phone.e164 + ":" + body.code);
    if (!constantTimeEqual(candidate, reset.code_hash)) {
      const attempts = reset.attempts + 1;
      await db.from("tajir_staff_pin_resets").update({
        attempts, consumed_at: attempts >= 6 ? new Date().toISOString() : null,
      }).eq("id", reset.id);
      return response(400, { error: "Incorrect code. Check the SMS and try again." });
    }

    const loginEmail = "u" + phone.e164.replace(/[^0-9]/g, "") + "@login.tajir.app";
    const loginPassword = "TAJIR-PIN-" + body.new_pin + "-Account#2026";
    const { error: authError } = await db.auth.admin.updateUserById(profile.id, { password: loginPassword });
    if (authError) throw authError;
    await db.from("tajir_staff_pin_resets").update({ consumed_at: new Date().toISOString() }).eq("id", reset.id);
    return response(200, { success: true, message: "Your staff PIN has been reset. Sign in using your new PIN.", login_email: loginEmail });
  } catch (error) {
    console.error("TAJIR staff PIN recovery error", error instanceof Error ? error.message : error);
    return response(500, { error: "TAJIR could not complete staff PIN recovery. Please try again later." });
  }
});