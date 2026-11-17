import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok");
  if (req.method !== "POST") return new Response("POST required", { status: 405 });
  try {
    const b = await req.json();
    if (typeof b.phone !== "string" || typeof b.pin !== "string" || !/^\\d{4}$/.test(b.pin)) {
      return Response.json({ error: "Enter your phone number and four-digit PIN." }, { status: 400 });
    }
    const digits = b.phone.replace(/[^0-9]/g, "");
    const phone = digits.startsWith("254") ? "+" + digits : digits.startsWith("0") ? "+254" + digits.slice(1) : "+254" + digits;
    if (!/^\\+254\\d{9}$/.test(phone)) return Response.json({ error: "Invalid Kenyan phone number." }, { status: 400 });

    const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
    const { data: authResult, error: authError } = await db.rpc("authenticate_tajir_customer_pin", { p_phone: phone, p_pin: b.pin });
    if (authError) throw authError;

    if (!authResult?.success) {
      const seconds = Number(authResult?.retry_after_seconds || 0);
      if (authResult?.locked && seconds > 0) {
        const wait = seconds >= 60 ? `${Math.ceil(seconds / 60)} minute(s)` : `${seconds} second(s)`;
        return Response.json({ error: `Too many incorrect PIN attempts. Try again in ${wait}.`, retry_after_seconds: seconds }, { status: 429 });
      }
      return Response.json({ error: "Phone number or PIN is incorrect.", remaining_attempts: authResult?.remaining_attempts ?? 0 }, { status: 401 });
    }

    const email = "u" + phone.replace(/\\D/g, "") + "@login.tajir.app";
    const { data, error } = await db.auth.admin.generateLink({ type: "magiclink", email });
    if (error) throw error;
    const tokenHash = data.properties?.hashed_token;
    if (!tokenHash) throw new Error("Could not create a secure customer session.");
    return Response.json({ success: true, token_hash: tokenHash });
  } catch (e) {
    return Response.json({ error: e instanceof Error ? e.message : "Sign-in failed." }, { status: 400 });
  }
});