import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const allowedRoles = new Set(["worker", "tractor_owner", "driver", "mechanic", "auto_spares_owner"]);
const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function normalizePhone(value: string): string {
  const digits = value.replace(/[^0-9]/g, "");
  if (digits.startsWith("254") && digits.length === 12) return "+" + digits;
  if (digits.startsWith("0") && digits.length === 10) return "+254" + digits.slice(1);
  if (digits.length === 9) return "+254" + digits;
  return "";
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "POST required." }, 405);

  let createdUserId: string | null = null;
  let db: ReturnType<typeof createClient> | null = null;
  try {
    const body = await req.json();
    const roleCode = typeof body.role_code === "string" ? body.role_code : "";
    const fullName = typeof body.full_name === "string" ? body.full_name.trim().replace(/\s+/g, " ") : "";
    const phone = typeof body.phone === "string" ? normalizePhone(body.phone) : "";
    const pin = typeof body.pin === "string" ? body.pin.trim() : "";
    const businessName = typeof body.business_name === "string" ? body.business_name.trim() : "";
    const location = typeof body.location === "string" ? body.location.trim() : "";
    const services = Array.isArray(body.services)
      ? body.services.filter((v: unknown): v is string => typeof v === "string")
          .map((v: string) => v.trim()).filter((v: string) => v.length > 0 && v.length <= 60).slice(0, 8)
      : [];

    if (!allowedRoles.has(roleCode)) return json({ error: "Choose a supported service-provider account." }, 400);
    if (fullName.length < 2 || fullName.length > 120) return json({ error: "Enter your full name." }, 400);
    if (!phone) return json({ error: "Enter a valid Kenyan phone number." }, 400);
    if (!/^\d{4}$/.test(pin)) return json({ error: "PIN must contain exactly four digits." }, 400);
    if (roleCode !== "driver" && roleCode !== "worker" && (businessName.length < 2 || businessName.length > 120)) {
      return json({ error: "Enter a valid business or shop name." }, 400);
    }
    if (["mechanic", "auto_spares_owner"].includes(roleCode) && (location.length < 2 || location.length > 160)) {
      return json({ error: "Enter your business location." }, 400);
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!supabaseUrl || !serviceKey) throw new Error("Registration service is not configured.");
    db = createClient(supabaseUrl, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });

    const ip = req.headers.get("cf-connecting-ip") || "unknown";
    const { data: allowed, error: rateError } = await db.rpc("consume_tajir_registration_attempt", {
      p_phone: phone,
      p_ip: ip,
    });
    if (rateError) throw rateError;
    if (allowed !== true) return json({ error: "Too many registration attempts. Please try again later." }, 429);

    const { data: existingProfiles, error: profileLookupError } = await db
      .from("profiles").select("id,phone").not("phone", "is", null);
    if (profileLookupError) throw profileLookupError;
    const duplicate = (existingProfiles || []).some((p: { phone?: string | null }) =>
      p.phone && normalizePhone(p.phone) === phone);
    if (duplicate) return json({ error: "This phone number already has a TAJIR account. Please sign in instead." }, 409);

    const email = "u" + phone.replace(/[^0-9]/g, "") + "@login.tajir.app";
    const password = "TAJIR-PIN-" + pin + "-Account#2026";
    const { data: created, error: createError } = await db.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
      user_metadata: { display_name: fullName, full_name: fullName },
    });
    if (createError) {
      if (createError.message.toLowerCase().includes("already")) {
        return json({ error: "This phone number already has a TAJIR account. Please sign in instead." }, 409);
      }
      throw createError;
    }
    createdUserId = created.user.id;

    const { error: profileError } = await db.from("profiles").update({
      display_name: fullName,
      phone,
      status: "active",
      updated_at: new Date().toISOString(),
    }).eq("id", createdUserId);
    if (profileError) throw profileError;

    const { data: role, error: roleError } = await db.from("app_roles")
      .select("id").eq("code", roleCode).single();
    if (roleError || !role) throw roleError || new Error("Selected account role is unavailable.");

    const { error: assignmentError } = await db.from("user_role_assignments").insert({
      user_id: createdUserId,
      role_id: role.id,
      assigned_by: null,
      is_active: true,
    });
    if (assignmentError) throw assignmentError;

    if (roleCode === "tractor_owner") {
      const { error } = await db.from("tractor_owner_profiles").insert({
        profile_id: createdUserId,
        full_name: fullName,
        phone,
        company_name: businessName || null,
        status: "pending",
      });
      if (error) throw error;
    } else if (roleCode === "mechanic") {
      const { error } = await db.from("mechanic_profiles").insert({
        profile_id: createdUserId,
        business_name: businessName,
        phone,
        location,
        services,
        status: "pending",
      });
      if (error) throw error;
    } else if (roleCode === "auto_spares_owner") {
      const { error } = await db.from("auto_spares_profiles").insert({
        profile_id: createdUserId,
        shop_name: businessName,
        phone,
        location,
        status: "pending",
      });
      if (error) throw error;
    }

    return json({
      success: true,
      role: roleCode,
      verification_required: roleCode !== "driver" && roleCode !== "worker",
    });
  } catch (error) {
    if (createdUserId && db) {
      try {
        await db.auth.admin.deleteUser(createdUserId);
      } catch (_) {
        // Cleanup is best-effort; no credentials or internal errors are returned.
      }
    }
    return json({
      error: error instanceof Error ? error.message : "Registration failed. Please try again.",
    }, 400);
  }
});
