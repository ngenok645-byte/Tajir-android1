import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

function normalizePhone(value: string): string {
  const digits = value.replace(/[^0-9]/g, "");
  if (digits.startsWith("254") && digits.length === 12) return "+" + digits;
  if (digits.startsWith("0") && digits.length === 10) return "+254" + digits.slice(1);
  if (digits.length === 9) return "+254" + digits;
  return "";
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok");
  if (req.method !== "POST") return new Response("POST required", { status: 405 });
  let createdUserId: string | null = null;
  const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
  try {
    const b = await req.json();
    const pin = typeof b.pin === "string" ? b.pin.trim() : "";
    const customerType = b.customer_type ?? "buyer";
    if (typeof b.phone !== "string" || typeof b.full_name !== "string" ||
        !/^\d{4}$/.test(pin) || b.full_name.trim().length < 2 ||
        !["buyer", "seller"].includes(customerType)) {
      return Response.json({ error: "Enter your full name, Kenyan phone number, four-digit PIN and choose buyer or seller." }, { status: 400 });
    }
    const phone = normalizePhone(b.phone);
    if (!phone) return Response.json({ error: "Invalid Kenyan phone number." }, { status: 400 });

    const ip = req.headers.get("cf-connecting-ip") || req.headers.get("x-real-ip") || "unknown";
    const { data: allowed, error: rateError } = await db.rpc("consume_tajir_registration_attempt", { p_phone: phone, p_ip: ip });
    if (rateError) throw rateError;
    if (allowed !== true) return Response.json({ error: "Too many attempts. Try later." }, { status: 429 });

    const { data: allCustomers, error: matchError } = await db.from("customers").select("id,profile_id,active,phone");
    if (matchError) throw matchError;
    const matches = (allCustomers || []).filter((c: any) => normalizePhone(String(c.phone || "")) === phone);
    if (matches.length > 1) return Response.json({ error: "More than one customer record uses this phone number. Contact the Director so the records can be checked safely." }, { status: 409 });
    const existing = matches[0] as any;

    if (existing?.profile_id) {
      const { data: profile, error: profileError } = await db.from("profiles").select("id,status").eq("id", existing.profile_id).maybeSingle();
      if (profileError) throw profileError;
      const { data: credential, error: credentialError } = await db.from("customer_pin_credentials").select("profile_id").eq("profile_id", existing.profile_id).maybeSingle();
      if (credentialError) throw credentialError;
      if (existing.active === true && profile?.status === "pending" && !credential) {
        const { error } = await db.rpc("set_tajir_customer_pin", { p_user_id: existing.profile_id, p_pin: pin });
        if (error) throw error;
        const { error: customerError } = await db.from("customers").update({
          full_name: b.full_name.trim(), phone, customer_type: customerType, active: true,
          marketplace_can_buy: customerType === "buyer", marketplace_can_sell: customerType === "seller",
        }).eq("id", existing.id);
        if (customerError) throw customerError;
        const { error: activateError } = await db.from("profiles").update({ display_name: b.full_name.trim(), phone, status: "active" }).eq("id", existing.profile_id);
        if (activateError) throw activateError;
        return Response.json({ success: true, recovered: true });
      }
      return Response.json({ error: existing.active === false
        ? "This phone number already belongs to an inactive TAJIR account. Contact the Director to restore access."
        : "A customer account already uses this phone number. Sign in or ask the Director to reset your PIN." }, { status: 409 });
    }
    if (existing && existing.active === false) return Response.json({ error: "This phone number belongs to an inactive customer record. Contact the Director to restore access." }, { status: 409 });

    // Strip all non-digits when generating the internal login email.
    const email = "u" + phone.replace(/\D/g, "") + "@login.tajir.app";
    const { data, error } = await db.auth.admin.createUser({
      email, password: crypto.randomUUID() + crypto.randomUUID(), email_confirm: true,
      user_metadata: { display_name: b.full_name.trim(), full_name: b.full_name.trim() },
    });
    if (error) throw error;
    createdUserId = data.user.id;
    const { error: profileError } = await db.from("profiles").update({ phone, display_name: b.full_name.trim(), status: "pending" }).eq("id", createdUserId);
    if (profileError) throw profileError;
    const { error: pinError } = await db.rpc("set_tajir_customer_pin", { p_user_id: createdUserId, p_pin: pin });
    if (pinError) throw pinError;

    if (existing) {
      // Preserve the legacy customer ID and all historical transaction links.
      const { error: customerError } = await db.from("customers").update({
        profile_id: createdUserId, customer_type: customerType, full_name: b.full_name.trim(),
        phone, active: true, marketplace_can_buy: customerType === "buyer", marketplace_can_sell: customerType === "seller",
      }).eq("id", existing.id).is("profile_id", null);
      if (customerError) throw customerError;
    } else {
      const { error: customerError } = await db.from("customers").insert({
        profile_id: createdUserId, customer_type: customerType, full_name: b.full_name.trim(),
        phone, active: true, marketplace_can_buy: customerType === "buyer", marketplace_can_sell: customerType === "seller",
      });
      if (customerError) throw customerError;
    }
    const { error: activateError } = await db.from("profiles").update({ status: "active" }).eq("id", createdUserId);
    if (activateError) throw activateError;
    return Response.json({ success: true, linked_existing_record: Boolean(existing) });
  } catch (e) {
    if (createdUserId) {
      try { await db.auth.admin.deleteUser(createdUserId); } catch (_) { /* preserve original failure */ }
    }
    return Response.json({ error: e instanceof Error ? e.message : "Registration failed." }, { status: 400 });
  }
});