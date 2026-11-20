import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const reply = (status: number, body: Record<string, unknown>) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json", "Cache-Control": "no-store" } });

type Purpose = "customer_registration" | "provider_registration" | "director_setup";
const purposes = new Set<Purpose>(["customer_registration", "provider_registration", "director_setup"]);

function normalizePhone(input: string): string | null {
  let digits = input.replace(/[^0-9]/g, "");
  if (digits.startsWith("0") && digits.length === 10) digits = "254" + digits.slice(1);
  else if ((digits.startsWith("7") || digits.startsWith("1")) && digits.length === 9) digits = "254" + digits;
  if (!/^254[17]\d{8}$/.test(digits)) return null;
  return "+" + digits;
}
function randomCode(): string {
  const bytes = new Uint32Array(1);
  crypto.getRandomValues(bytes);
  return String(bytes[0] % 1_000_000).padStart(6, "0");
}
async function digest(secret: string, value: string): Promise<string> {
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const signed = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(value));
  return Array.from(new Uint8Array(signed)).map(v => v.toString(16).padStart(2, "0")).join("");
}
function equal(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let mismatch = 0;
  for (let i = 0; i < a.length; i++) mismatch |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return mismatch === 0;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return reply(405, { error: "POST required." });

  try {
    const body = await req.json();
    const action = body?.action;
    const phone = typeof body?.phone === "string" ? normalizePhone(body.phone) : null;
    const purpose = body?.purpose as Purpose;
    if (!phone || !purposes.has(purpose)) return reply(400, { error: "Enter a valid Kenyan mobile number and account purpose." });

    const url = Deno.env.get("SUPABASE_URL");
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const atUsername = Deno.env.get("AFRICASTALKING_USERNAME");
    const atApiKey = Deno.env.get("AFRICASTALKING_API_KEY");
    if (!url || !serviceKey || !atUsername || !atApiKey) return reply(503, { error: "Phone verification SMS is not configured. Contact TAJIR support." });

    const db = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });

    if (action === "request") {
      const now = new Date();
      const { data: recent, error: recentError } = await db.from("tajir_phone_verifications")
        .select("id,created_at")
        .eq("phone_e164", phone)
        .eq("purpose", purpose)
        .gte("created_at", new Date(now.getTime() - 60 * 60_000).toISOString())
        .order("created_at", { ascending: false })
        .limit(5);
      if (recentError) throw recentError;
      if ((recent || []).length >= 5) return reply(429, { error: "Too many verification requests. Try again later." });
      if ((recent || []).length > 0 && now.getTime() - new Date(recent![0].created_at).getTime() < 60_000) {
        return reply(429, { error: "Please wait one minute before requesting another code." });
      }

      const rawIp = req.headers.get("cf-connecting-ip") || req.headers.get("x-real-ip") || "";
      const ipHash = rawIp ? await digest(atApiKey, rawIp) : null;
      if (ipHash) {
        const { data: recentIp, error: ipError } = await db.from("tajir_phone_verifications")
          .select("id")
          .eq("request_ip_hash", ipHash)
          .gte("created_at", new Date(now.getTime() - 60 * 60_000).toISOString())
          .limit(20);
        if (ipError) throw ipError;
        if ((recentIp || []).length >= 20) return reply(429, { error: "Too many verification requests from this connection. Try again later." });
      }

      const challengeId = crypto.randomUUID();
      const code = randomCode();
      const codeHash = await digest(atApiKey, challengeId + ":" + phone + ":" + purpose + ":" + code);
      await db.from("tajir_phone_verifications").update({ consumed_at: now.toISOString() })
        .eq("phone_e164", phone).eq("purpose", purpose).is("consumed_at", null);

      const { error: insertError } = await db.from("tajir_phone_verifications").insert({
        id: challengeId,
        phone_e164: phone,
        purpose,
        code_hash: codeHash,
        request_ip_hash: ipHash,
        expires_at: new Date(now.getTime() + 5 * 60_000).toISOString(),
      });
      if (insertError) throw insertError;

      const form = new URLSearchParams({
        username: atUsername,
        to: phone,
        message: "Your TAJIR verification code is " + code + ". It expires in 5 minutes. Do not share it.",
      });
      const sms = await fetch("https://api.africastalking.com/version1/messaging", {
        method: "POST",
        headers: { apiKey: atApiKey, Accept: "application/json", "Content-Type": "application/x-www-form-urlencoded" },
        body: form.toString(),
      });
      if (!sms.ok) {
        await db.from("tajir_phone_verifications").update({ consumed_at: new Date().toISOString() }).eq("id", challengeId);
        const responseText = await sms.text();
        console.error("TAJIR verification SMS failed", sms.status, responseText.slice(0, 300));
        return reply(503, { error: "TAJIR could not send the SMS. Please try again later." });
      }
      return reply(200, { success: true, challenge_id: challengeId, expires_in_seconds: 300 });
    }

    if (action === "verify") {
      const challengeId = typeof body?.challenge_id === "string" ? body.challenge_id : "";
      const code = typeof body?.code === "string" ? body.code.trim() : "";
      if (!/^[0-9a-f-]{36}$/i.test(challengeId) || !/^\d{6}$/.test(code)) {
        return reply(400, { error: "Enter the six-digit code sent to your phone." });
      }
      const { data: challenge, error: readError } = await db.from("tajir_phone_verifications")
        .select("id,phone_e164,purpose,code_hash,attempts,expires_at,verified_at,consumed_at")
        .eq("id", challengeId).eq("phone_e164", phone).eq("purpose", purpose).maybeSingle();
      if (readError) throw readError;
      if (!challenge || challenge.consumed_at || challenge.verified_at ||
          new Date(challenge.expires_at).getTime() <= Date.now() || challenge.attempts >= 6) {
        return reply(400, { error: "The verification code is invalid or expired. Request a new code." });
      }

      const candidate = await digest(atApiKey, challengeId + ":" + phone + ":" + purpose + ":" + code);
      if (!equal(candidate, challenge.code_hash)) {
        const nextAttempts = Number(challenge.attempts) + 1;
        await db.from("tajir_phone_verifications").update({
          attempts: nextAttempts,
          consumed_at: nextAttempts >= 6 ? new Date().toISOString() : null,
        }).eq("id", challengeId).eq("attempts", challenge.attempts).is("verified_at", null).is("consumed_at", null);
        return reply(400, { error: "The code is incorrect. Check the SMS and try again." });
      }

      const { data: updated, error: updateError } = await db.from("tajir_phone_verifications")
        .update({ verified_at: new Date().toISOString() })
        .eq("id", challengeId).eq("attempts", challenge.attempts)
        .is("verified_at", null).is("consumed_at", null)
        .gt("expires_at", new Date().toISOString())
        .select("id").maybeSingle();
      if (updateError) throw updateError;
      if (!updated) return reply(409, { error: "The verification code was already used or expired. Request a new code." });
      return reply(200, { success: true, verified: true });
    }

    return reply(400, { error: "Choose request or verify." });
  } catch (error) {
    console.error("TAJIR phone verification failed", error);
    return reply(500, { error: "TAJIR could not verify this phone number. Please try again." });
  }
});
