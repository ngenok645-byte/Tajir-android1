import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

type ProviderRole = "tractor_owner" | "mechanic" | "auto_spares_owner";

function normalizePhone(value: string): string {
  const digits = value.replace(/[^0-9]/g, "");
  if (digits.startsWith("254") && digits.length === 12) return "+" + digits;
  if (digits.startsWith("0") && digits.length === 10) return "+254" + digits.slice(1);
  if (digits.length === 9) return "+254" + digits;
  return "";
}

function json(body: Record<string, unknown>, status = 200) {
  return Response.json(body, {
    status,
    headers: { "Cache-Control": "no-store" },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok");
  if (req.method !== "POST") return json({ error: "POST required." }, 405);

  let createdUserId: string | null = null;
  const db = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false, autoRefreshToken: false } },
  );

  try {
    const body = await req.json();
    const role = body.role as ProviderRole;
    const fullName = typeof body.full_name === "string" ? body.full_name.trim() : "";
    const phone = typeof body.phone === "string" ? normalizePhone(body.phone) : "";
    const pin = typeof body.pin === "string" ? body.pin.trim() : "";
    const verificationId = typeof body.verification_id === "string" ? body.verification_id : "";
    const businessName = typeof body.business_name === "string" ? body.business_name.trim() : "";
    const location = typeof body.location === "string" ? body.location.trim() : "";
    const services = Array.isArray(body.services)
      ? body.services.filter((v: unknown) => typeof v === "string").map((v: string) => v.trim()).filter(Boolean).slice(0, 20)
      : [];

    if (!["tractor_owner", "mechanic", "auto_spares_owner"].includes(role)) {
      return json({ error: "Choose a supported provider account type." }, 400);
    }
    if (fullName.length < 2 || fullName.length > 80 || !phone || !/^\d{4}$/.test(pin)) {
      return json({ error: "Enter your full name, valid Kenyan phone number and four-digit PIN." }, 400);
    }
    if (role !== "tractor_owner" && (businessName.length < 2 || businessName.length > 100 || location.length < 2 || location.length > 120)) {
      return json({ error: "Enter your business name and operating location." }, 400);
    }
    if (role === "mechanic" && services.length === 0) {
      return json({ error: "List at least one service you provide." }, 400);
    }

    const ip = req.headers.get("cf-connecting-ip") || req.headers.get("x-real-ip") || "unknown";
    const { data: allowed, error: rateError } = await db.rpc("consume_tajir_registration_attempt", {
      p_phone: phone,
      p_ip: ip,
    });
    if (rateError) throw rateError;
    if (allowed !== true) return json({ error: "Too many registration attempts. Please try again later." }, 429);

    // Consume a verified, unexpired phone challenge exactly once before creating an account.
    const { data: verification, error: verificationError } = await db.from("tajir_phone_verifications")
      .update({ consumed_at: new Date().toISOString() })
      .eq("id", verificationId)
      .eq("phone_e164", phone)
      .eq("purpose", "provider_registration")
      .not("verified_at", "is", null)
      .is("consumed_at", null)
      .gt("expires_at", new Date().toISOString())
      .select("id")
      .maybeSingle();
    if (verificationError) throw verificationError;
    if (!verification) return json({ error: "Verify control of this phone number before applying." }, 403);

    const { data: profiles, error: profileReadError } = await db.from("profiles").select("id,phone");
    if (profileReadError) throw profileReadError;
    const duplicate = (profiles || []).some((p: { id: string; phone: string | null }) =>
      p.phone && normalizePhone(p.phone) === phone
    );
    if (duplicate) {
      return json({ error: "This phone number already has a TAJIR account. Please sign in or contact a Director." }, 409);
    }

    const email = "u" + phone.replace(/\D/g, "") + "@login.tajir.app";
    const { data: authData, error: authError } = await db.auth.admin.createUser({
      email,
      password: `TAJIR-PIN-${pin}-Account#2026`,
      email_confirm: true,
      user_metadata: { display_name: fullName, full_name: fullName },
    });
    if (authError) {
      if (/already|registered|exists/i.test(authError.message)) {
        return json({ error: "This phone number already has a TAJIR account. Please sign in instead." }, 409);
      }
      throw authError;
    }
    createdUserId = authData.user.id;

    // Mark the base profile active so the pending-customer trigger does not
    // create a customer record for a service-provider account.
    const { error: baseProfileError } = await db.from("profiles").update({
      display_name: fullName,
      phone,
      status: "active",
    }).eq("id", createdUserId);
    if (baseProfileError) throw baseProfileError;

    const { data: roleRow, error: roleError } = await db.from("app_roles")
      .select("id").eq("code", role).single();
    if (roleError || !roleRow) throw roleError || new Error("Provider role is not configured.");

    const { error: assignmentError } = await db.from("user_role_assignments").insert({
      user_id: createdUserId,
      role_id: roleRow.id,
      assigned_by: null,
      is_active: false,
    });
    if (assignmentError) throw assignmentError;

    if (role === "tractor_owner") {
      const { error } = await db.from("tractor_owner_profiles").insert({
        profile_id: createdUserId,
        full_name: fullName,
        phone,
        company_name: businessName || null,
        status: "pending",
      });
      if (error) throw error;
    } else if (role === "mechanic") {
      const { error } = await db.from("mechanic_profiles").insert({
        profile_id: createdUserId,
        business_name: businessName,
        phone,
        location,
        services,
        status: "pending",
      });
      if (error) throw error;
    } else {
      const { error } = await db.from("auto_spares_profiles").insert({
        profile_id: createdUserId,
        shop_name: businessName,
        phone,
        location,
        status: "pending",
      });
      if (error) throw error;
    }

    return json({ success: true, pending_approval: true });
  } catch (error) {
    if (createdUserId) {
      // Remove the incomplete identity and its dependent rows if any step fails.
      await db.auth.admin.deleteUser(createdUserId).catch(() => undefined);
    }
    return json({
      error: error instanceof Error ? error.message : "Provider registration failed. Please try again.",
    }, 400);
  }
});
