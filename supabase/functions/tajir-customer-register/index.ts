import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

function normalizePhone(value: string): string {
  const digits = value.replace(/[^0-9]/g, "");
  if (digits.startsWith("254") && digits.length === 12) return "+" + digits;
  if (digits.startsWith("0") && digits.length === 10) return "+254" + digits.slice(1);
  if (digits.length === 9) return "+254" + digits;
  return "";
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok");
  if (req.method !== "POST") return new Response("POST required", { status: 405 });
  let createdUserId: string | null = null;
  try {
    const b = await req.json();
    const pin = typeof b.pin === "string" ? b.pin.trim() : "";
    // Users may self-register as buyer OR seller. Only a Director may grant both.\n    const customerType = b.customer_type === "seller" ? "seller" : "buyer";
    const fullName = typeof b.full_name === "string" ? b.full_name.trim().replace(/\s+/g, " ") : "";
    const nationalId = typeof b.national_id === "string" ? b.national_id.replace(/[^0-9]/g, "") : "";
    if (typeof b.phone !== "string" || !/^\d{4}$/.test(pin) ||
        fullName.length < 2 || fullName.length > 120 ||
        !/^[0-9]{7,8}$/.test(nationalId)) {
      return Response.json({
        error: "Enter your full legal name as shown on your National ID, valid Kenyan phone number, National ID number, and four-digit PIN.",
      }, { status: 400 });
    }
    const phone = normalizePhone(b.phone);
    if (!phone) return Response.json({ error: "Invalid Kenyan phone number." }, { status: 400 });

    const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
    const ip = req.headers.get("cf-connecting-ip") || req.headers.get("x-real-ip") || "unknown";
    const { data: allowed, error: rateError } = await db.rpc("consume_tajir_registration_attempt", { p_phone: phone, p_ip: ip });
    if (rateError) throw rateError;
    if (allowed !== true) return Response.json({ error: "Too many attempts. Try later." }, { status: 429 });

    const { data: allCustomers, error: matchError } = await db.from("customers").select("id,profile_id,active,phone");
    if (matchError) throw matchError;
    const existing = (allCustomers || []).find((c: any) => normalizePhone(String(c.phone || "")) === phone);

    if (existing?.profile_id) {
      const { data: profile, error: profileReadError } = await db.from("profiles")
        .select("id,status").eq("id", existing.profile_id).maybeSingle();
      if (profileReadError) throw profileReadError;
      const { data: credential, error: credentialReadError } = await db.from("customer_pin_credentials")
        .select("profile_id").eq("profile_id", existing.profile_id).maybeSingle();
      if (credentialReadError) throw credentialReadError;

      if (existing.active === true && profile?.status === "pending" && !credential) {
        const { error: completionError } = await db.rpc("complete_tajir_customer_registration", {
          p_user_id: existing.profile_id,
          p_full_name: fullName,
          p_phone: phone,
          p_pin: pin,
          p_national_id: nationalId,
          p_customer_type: customerType,
        });
        if (completionError) throw completionError;
        return Response.json({ success: true, recovered: true });
      }
      return Response.json({
        error: existing.active === false
          ? "This phone number already belongs to an inactive TAJIR account. Contact the Director to restore access."
          : "A customer account already uses this phone number. Sign in or ask the Director to reset your PIN.",
      }, { status: 409 });
    }

    const email = "u" + phone.replace(/\D/g, "") + "@login.tajir.app";
    const { data, error } = await db.auth.admin.createUser({
      email, password: crypto.randomUUID() + crypto.randomUUID(), email_confirm: true,
      user_metadata: { display_name: fullName, full_name: fullName },
    });
    if (error) throw error;
    createdUserId = data.user.id;

    const { error: completionError } = await db.rpc("complete_tajir_customer_registration", {
      p_user_id: createdUserId,
      p_full_name: fullName,
      p_phone: phone,
      p_pin: pin,
      p_national_id: nationalId,
      p_customer_type: customerType,
    });
    if (completionError) throw completionError;

    return Response.json({ success: true });
  } catch (e) {
    if (createdUserId) {
      try {
        const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
        await db.auth.admin.deleteUser(createdUserId);
      } catch (_) { /* A failed cleanup is logged by the platform; no credentials are returned. */ }
    }
    return Response.json({ error: e instanceof Error ? e.message : "Registration failed." }, { status: 400 });
  }
});