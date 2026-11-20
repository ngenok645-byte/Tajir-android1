import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

function normalizePhone(value: string): string {
  const digits = value.replace(/[^0-9]/g, "");
  if (digits.startsWith("254") && digits.length === 12) return "+" + digits;
  if (digits.startsWith("0") && digits.length === 10) return "+254" + digits.slice(1);
  if (digits.length === 9) return "+254" + digits;
  return "";
}
const json = (status: number, body: Record<string, unknown>) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json", "Cache-Control": "no-store" } });

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok");
  if (req.method !== "POST") return json(405, { error: "POST required." });

  let createdUserId: string | null = null;
  try {
    const body = await req.json();
    const pin = typeof body.pin === "string" ? body.pin.trim() : "";
    const customerType = body.customer_type ?? "buyer";
    const phone = typeof body.phone === "string" ? normalizePhone(body.phone) : "";
    const verificationId = typeof body.verification_id === "string" ? body.verification_id : "";
    const fullName = typeof body.full_name === "string" ? body.full_name.trim() : "";

    if (!phone || !/^\d{4}$/.test(pin) || fullName.length < 2 || fullName.length > 80 ||
        !["buyer", "seller"].includes(customerType) || !/^[0-9a-f-]{36}$/i.test(verificationId)) {
      return json(400, { error: "Enter your full name, valid phone number, four-digit PIN, account type and verified phone." });
    }

    const url = Deno.env.get("SUPABASE_URL");
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!url || !serviceKey) return json(500, { error: "Registration service is not configured." });
    const db = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });

    const ip = req.headers.get("cf-connecting-ip") || req.headers.get("x-real-ip") || "unknown";
    const { data: allowed, error: rateError } = await db.rpc("consume_tajir_registration_attempt", {
      p_phone: phone, p_ip: ip,
    });
    if (rateError) throw rateError;
    if (allowed !== true) return json(429, { error: "Too many registration attempts. Try again later." });

    const { data: verification, error: verificationError } = await db.from("tajir_phone_verifications")
      .update({ consumed_at: new Date().toISOString() })
      .eq("id", verificationId)
      .eq("phone_e164", phone)
      .eq("purpose", "customer_registration")
      .not("verified_at", "is", null)
      .is("consumed_at", null)
      .gt("expires_at", new Date().toISOString())
      .select("id")
      .maybeSingle();
    if (verificationError) throw verificationError;
    if (!verification) return json(403, { error: "Verify control of this phone number before creating an account." });

    const { data: allCustomers, error: customerReadError } = await db.from("customers")
      .select("id,profile_id,active,phone");
    if (customerReadError) throw customerReadError;
    const existing = (allCustomers || []).find((row: any) => normalizePhone(String(row.phone || "")) === phone);

    if (existing?.profile_id) {
      const { data: profile, error: profileError } = await db.from("profiles")
        .select("id,status").eq("id", existing.profile_id).maybeSingle();
      if (profileError) throw profileError;
      const { data: credential, error: credentialError } = await db.from("customer_pin_credentials")
        .select("profile_id").eq("profile_id", existing.profile_id).maybeSingle();
      if (credentialError) throw credentialError;

      if (existing.active === true && profile?.status === "pending" && !credential) {
        const { error: pinError } = await db.rpc("set_tajir_customer_pin", {
          p_user_id: existing.profile_id, p_pin: pin,
        });
        if (pinError) throw pinError;
        const { error: customerUpdateError } = await db.from("customers").update({
          full_name: fullName, phone, customer_type: customerType, active: true,
          marketplace_can_buy: customerType === "buyer",
          marketplace_can_sell: customerType === "seller",
        }).eq("id", existing.id);
        if (customerUpdateError) throw customerUpdateError;
        const { error: profileUpdateError } = await db.from("profiles").update({
          display_name: fullName, phone, status: "active",
        }).eq("id", existing.profile_id);
        if (profileUpdateError) throw profileUpdateError;
        return json(200, { success: true, recovered: true });
      }
      return json(409, {
        error: existing.active === false
          ? "This phone number belongs to an inactive TAJIR account. Contact the Director to restore access."
          : "A customer account already uses this phone number. Sign in or request a PIN reset.",
      });
    }

    const { data: profiles, error: profileReadError } = await db.from("profiles").select("id,phone");
    if (profileReadError) throw profileReadError;
    const duplicateProfile = (profiles || []).some((row: any) =>
      row.phone && normalizePhone(String(row.phone)) === phone
    );
    if (duplicateProfile) return json(409, { error: "This phone number already has a TAJIR account. Please sign in instead." });

    const email = "u" + phone.replace(/\D/g, "") + "@login.tajir.app";
    const { data: authData, error: authError } = await db.auth.admin.createUser({
      email,
      password: crypto.randomUUID() + crypto.randomUUID(),
      email_confirm: true,
      user_metadata: { display_name: fullName, full_name: fullName },
    });
    if (authError) {
      if (/already|registered|exists/i.test(authError.message)) {
        return json(409, { error: "This phone number is already registered. Please sign in instead." });
      }
      throw authError;
    }
    createdUserId = authData.user.id;

    const { error: profileUpdateError } = await db.from("profiles").update({
      phone, display_name: fullName, status: "pending",
    }).eq("id", createdUserId);
    if (profileUpdateError) throw profileUpdateError;

    const { error: pinError } = await db.rpc("set_tajir_customer_pin", {
      p_user_id: createdUserId, p_pin: pin,
    });
    if (pinError) throw pinError;

    const { error: insertCustomerError } = await db.from("customers").insert({
      profile_id: createdUserId,
      customer_type: customerType,
      full_name: fullName,
      phone,
      active: true,
      marketplace_can_buy: customerType === "buyer",
      marketplace_can_sell: customerType === "seller",
    });
    if (insertCustomerError) throw insertCustomerError;

    const { error: activateError } = await db.from("profiles").update({ status: "active" }).eq("id", createdUserId);
    if (activateError) throw activateError;
    return json(200, { success: true });
  } catch (error) {
    if (createdUserId) {
      await createClient(
        Deno.env.get("SUPABASE_URL")!,
        Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
        { auth: { persistSession: false, autoRefreshToken: false } },
      ).auth.admin.deleteUser(createdUserId).catch(() => undefined);
    }
    console.error("TAJIR customer registration failed", error);
    return json(400, { error: error instanceof Error ? error.message : "Registration failed. Please try again." });
  }
});
