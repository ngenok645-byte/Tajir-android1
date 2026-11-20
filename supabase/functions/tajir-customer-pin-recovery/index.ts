import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (status: number, value: Record<string, unknown>) =>
  new Response(JSON.stringify(value), { status, headers: { ...cors, "Content-Type": "application/json" } });
const generic = () => json(200, {
  success: true,
  message: "If an active TAJIR customer account matches that number, a verification code will be sent.",
});

function normalizeKenyanPhone(input: unknown): string | null {
  if (typeof input !== "string") return null;
  let digits = input.replace(/[^0-9]/g, "");
  if (digits.startsWith("0") && digits.length === 10) digits = "254" + digits.slice(1);
  else if ((digits.startsWith("7") || digits.startsWith("1")) && digits.length === 9) digits = "254" + digits;
  return /^254[17][0-9]{8}$/.test(digits) ? digits : null;
}
function randomCode(): string {
  const bytes = new Uint32Array(1);
  crypto.getRandomValues(bytes);
  return String(bytes[0] % 1_000_000).padStart(6, "0");
}
async function hashCode(secret: string, profileId: string, code: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "HMAC", key, new TextEncoder().encode("tajir-pin-reset:" + profileId + ":" + code),
  );
  return Array.from(new Uint8Array(signature), b => b.toString(16).padStart(2, "0")).join("");
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json(405, { error: "POST required." });

  try {
    const body = await req.json();
    const action = body?.action;
    const phone = normalizeKenyanPhone(body?.phone);
    if (!phone || !["request", "verify"].includes(action)) {
      return json(400, { error: "Enter a valid Kenyan mobile number and try again." });
    }

    const url = Deno.env.get("SUPABASE_URL");
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const atUsername = Deno.env.get("AFRICASTALKING_USERNAME");
    const atApiKey = Deno.env.get("AFRICASTALKING_API_KEY");
    if (!url || !serviceKey || !atUsername || !atApiKey) {
      console.error("PIN recovery server configuration is incomplete.");
      return json(503, { error: "PIN recovery is temporarily unavailable. Please try again later." });
    }

    const db = createClient(url, serviceKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: matches, error: lookupError } = await db.rpc("tajir_find_customer_for_pin_reset", {
      p_phone_digits: phone,
    });
    if (lookupError) throw lookupError;
    if (!Array.isArray(matches) || matches.length !== 1) return generic();
    const profileId = matches[0].profile_id as string;
    const registeredPhone = matches[0].registered_phone as string;

    if (action === "request") {
      const sinceMinute = new Date(Date.now() - 60_000).toISOString();
      const sinceDay = new Date(Date.now() - 24 * 60 * 60_000).toISOString();
      const [recent, daily] = await Promise.all([
        db.from("tajir_pin_reset_otps").select("id", { count: "exact", head: true })
          .eq("profile_id", profileId).is("consumed_at", null).gt("created_at", sinceMinute),
        db.from("tajir_pin_reset_otps").select("id", { count: "exact", head: true })
          .eq("profile_id", profileId).gt("created_at", sinceDay),
      ]);
      if (recent.error) throw recent.error;
      if (daily.error) throw daily.error;
      if ((recent.count ?? 0) > 0 || (daily.count ?? 0) >= 5) return generic();

      const code = randomCode();
      const codeHash = await hashCode(atApiKey, profileId, code);
      const expiresAt = new Date(Date.now() + 5 * 60_000).toISOString();
      const { error: insertError } = await db.from("tajir_pin_reset_otps").insert({
        profile_id: profileId,
        phone_digits: phone,
        code_hash: codeHash,
        expires_at: expiresAt,
      });
      if (insertError) throw insertError;

      const form = new URLSearchParams({
        username: atUsername,
        to: "+" + phone,
        message: "Your TAJIR PIN reset code is " + code + ". It expires in 5 minutes. Do not share it.",
      });
      const senderId = Deno.env.get("AFRICASTALKING_SENDER_ID");
      if (senderId) form.set("from", senderId);
      const sms = await fetch("https://api.africastalking.com/version1/messaging", {
        method: "POST",
        headers: { apiKey: atApiKey, Accept: "application/json", "Content-Type": "application/x-www-form-urlencoded" },
        body: form.toString(),
      });
      const smsText = await sms.text();
      if (!sms.ok) {
        console.error("Africa's Talking SMS request failed:", sms.status, smsText.slice(0, 500));
        await db.from("tajir_pin_reset_otps").delete().eq("profile_id", profileId).eq("code_hash", codeHash);
        return json(503, { error: "We could not send the verification SMS. Check SMS credits and sender approval, then try again." });
      }
      let accepted = true;
      try {
        const parsed = JSON.parse(smsText);
        const recipients = parsed?.SMSMessageData?.Recipients;
        if (Array.isArray(recipients) && recipients.length > 0) {
          accepted = recipients.some((r: { status?: string; statusCode?: number }) =>
            r.statusCode === 101 || r.status === "Success");
        }
      } catch { /* Some gateways return an empty success response. */ }
      if (!accepted) {
        console.error("Africa's Talking did not accept the SMS:", smsText.slice(0, 500));
        return json(503, { error: "The SMS provider did not accept the message. Check credits and sender approval." });
      }
      return json(200, { success: true, message: "A verification code has been sent if the number is registered." });
    }

    if (typeof body.code !== "string" || !/^[0-9]{6}$/.test(body.code) ||
        typeof body.new_pin !== "string" || !/^[0-9]{4}$/.test(body.new_pin)) {
      return json(400, { error: "Enter the six-digit code and a new four-digit PIN." });
    }

    const { data: otp, error: otpError } = await db.from("tajir_pin_reset_otps")
      .select("id,code_hash,expires_at,attempts,consumed_at")
      .eq("profile_id", profileId).eq("phone_digits", phone)
      .is("consumed_at", null).order("created_at", { ascending: false }).limit(1).maybeSingle();
    if (otpError) throw otpError;
    if (!otp || new Date(otp.expires_at).getTime() <= Date.now() || otp.attempts >= 5) {
      return json(400, { error: "The code is invalid or expired. Request a new code." });
    }

    const suppliedHash = await hashCode(atApiKey, profileId, body.code);
    if (suppliedHash !== otp.code_hash) {
      await db.from("tajir_pin_reset_otps").update({ attempts: otp.attempts + 1 })
        .eq("id", otp.id).is("consumed_at", null).lt("attempts", 5);
      return json(400, { error: "The verification code is incorrect." });
    }

    const { data: consumed, error: consumeError } = await db.from("tajir_pin_reset_otps")
      .update({ consumed_at: new Date().toISOString() })
      .eq("id", otp.id).eq("code_hash", suppliedHash)
      .is("consumed_at", null).gt("expires_at", new Date().toISOString())
      .lt("attempts", 5).select("id").maybeSingle();
    if (consumeError) throw consumeError;
    if (!consumed) return json(400, { error: "The code is invalid, expired, or already used. Request a new code." });

    const { error: pinError } = await db.rpc("set_tajir_customer_pin", {
      p_user_id: profileId,
      p_pin: body.new_pin,
    });
    if (pinError) {
      console.error("PIN update failed after OTP verification:", pinError.message);
      return json(500, { error: "The code was verified but the PIN could not be updated. Request a new code and try again." });
    }
    return json(200, { success: true, message: "Your PIN has been reset. You can now sign in with the new PIN." });
  } catch (error) {
    console.error("TAJIR customer PIN recovery error:", error instanceof Error ? error.message : error);
    return json(500, { error: "PIN recovery could not be completed. Please try again later." });
  }
});