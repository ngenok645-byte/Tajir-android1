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
  try {
    const b = await req.json();
    const pin = typeof b.pin === "string" ? b.pin.trim() : "";
    const customerType = b.customer_type ?? "buyer";
    if (typeof b.phone !== "string" || typeof b.pin !== "string" ||
        typeof b.full_name !== "string" || !/^\d{4}$/.test(pin) ||
        b.full_name.trim().length < 2 ||
        !["buyer", "seller"].includes(customerType)) {
      return Response.json({ error: "Enter your full name, Kenyan phone number, four-digit PIN and choose buyer or seller." }, { status: 400 });
    }
    const phone = normalizePhone(b.phone);
    if (!phone) return Response.json({ error: "Invalid Kenyan phone number." }, { status: 400 });

    const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
    const ip = req.headers.get("cf-connecting-ip") || req.headers.get("x-real-ip") || "unknown";
    const { data: allowed, error: rateError } = await db.rpc("consume_tajir_registration_attempt", { p_phone: phone, p_ip: ip });
    if (rateError) throw rateError;
    if (allowed !== true) return Response.json({ error: "Too many attempts. Try later." }, { status: 429 });

    // Normalize every stored phone representation before creating an Auth user.
    // This blocks duplicates even if an old record used 07..., 254..., or +254... formatting.
    const { data: allCustomers, error: matchError } = await db.from("customers")
      .select("id,profile_id,active,phone");
    if (matchError) throw matchError;
    const existing = (allCustomers || []).find((c: any) => normalizePhone(String(c.phone || "")) === phone);

    // Recover an interrupted first registration only when this exact pending account has no PIN.
    if (existing?.profile_id) {
      const { data: profile, error: profileReadError } = await db.from("profiles")
        .select("id,status").eq("id", existing.profile_id).maybeSingle();
      if (profileReadError) throw profileReadError;
      const { data: credential, error: credentialReadError } = await db.from("customer_pin_credentials")
        .select("profile_id").eq("profile_id", existing.profile_id).maybeSingle();
      if (credentialReadError) throw credentialReadError;

      if (existing.active === true && profile?.status === "pending" && !credential) {
        const { error: pinError } = await db.rpc("set_tajir_customer_pin", {
          p_user_id: existing.profile_id, p_pin: pin,
        });
        if (pinError) throw pinError;
        const { error: customerError } = await db.from("customers").update({
          full_name: b.full_name.trim(), phone, customer_type: customerType, active: true,
        }).eq("id", existing.id);
        if (customerError) throw customerError;
        const { error: activateError } = await db.from("profiles").update({
          display_name: b.full_name.trim(), phone, status: "active",
        }).eq("id", existing.profile_id);
        if (activateError) throw activateError;
        return Response.json({ success: true, recovered: true });
      }
      return Response.json({
        error: existing.active === false
          ? "This phone number already belongs to an inactive TAJIR account. Contact the Director to restore access."
          : "A customer account already uses this phone number. Sign in or ask the Director to reset your PIN."
      }, { status: 409 });
    }

    const email = "u" + phone.replace(/\\D/g, "") + "@login.tajir.app";
    const { data, error } = await db.auth.admin.createUser({
      email, password: crypto.randomUUID() + crypto.randomUUID(), email_confirm: true,
      user_metadata: { display_name: b.full_name.trim(), full_name: b.full_name.trim() },
    });
    if (error) throw error;
    const userId = data.user.id;

    const { error: profileError } = await db.from("profiles").update({
      phone, display_name: b.full_name.trim(), status: "pending",
    }).eq("id", userId);
    if (profileError) throw profileError;
    const { error: pinError } = await db.rpc("set_tajir_customer_pin", { p_user_id: userId, p_pin: pin });
    if (pinError) throw pinError;

    const { error: customerError } = await db.from("customers").insert({
      profile_id: userId, customer_type: customerType, full_name: b.full_name.trim(),
      phone, active: true, marketplace_can_buy: customerType === "buyer",
      marketplace_can_sell: customerType === "seller",
    });
    if (customerError) {
      await db.auth.admin.deleteUser(userId);
      if (customerError.code === "23505") {
        return Response.json({ error: "This phone number is already registered. Please sign in instead." }, { status: 409 });
      }
      throw customerError;
    }
    const { error: activateError } = await db.from("profiles").update({ status: "active" }).eq("id", userId);
    if (activateError) throw activateError;
    return Response.json({ success: true });
  } catch (e) {
    return Response.json({ error: e instanceof Error ? e.message : "Registration failed." }, { status: 400 });
  }
});