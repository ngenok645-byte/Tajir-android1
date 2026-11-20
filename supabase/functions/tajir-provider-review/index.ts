import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

type ProviderRole = "tractor_owner" | "mechanic" | "auto_spares_owner";

const tableForRole: Record<ProviderRole, string> = {
  tractor_owner: "tractor_owner_profiles",
  mechanic: "mechanic_profiles",
  auto_spares_owner: "auto_spares_profiles",
};

function json(body: Record<string, unknown>, status = 200) {
  return Response.json(body, { status, headers: { "Cache-Control": "no-store" } });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok");
  if (req.method !== "POST") return json({ error: "POST required." }, 405);

  try {
    const authorization = req.headers.get("Authorization") || "";
    const token = authorization.replace(/^Bearer\s+/i, "").trim();
    if (!token) return json({ error: "Sign in as a Director to review applications." }, 401);

    const db = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
      { auth: { persistSession: false, autoRefreshToken: false } },
    );
    const { data: authData, error: authError } = await db.auth.getUser(token);
    if (authError || !authData.user) return json({ error: "Your session is invalid. Please sign in again." }, 401);
    const directorId = authData.user.id;

    const { data: directorRole, error: directorRoleError } = await db.from("app_roles")
      .select("id").eq("code", "director").single();
    if (directorRoleError || !directorRole) throw new Error("Director role is not configured.");
    const { data: directorAssignment, error: directorAssignmentError } = await db.from("user_role_assignments")
      .select("id").eq("user_id", directorId).eq("role_id", directorRole.id).eq("is_active", true).maybeSingle();
    if (directorAssignmentError) throw directorAssignmentError;
    if (!directorAssignment) return json({ error: "Only an active Director can approve provider applications." }, 403);

    const body = await req.json();
    const profileId = typeof body.profile_id === "string" ? body.profile_id : "";
    const role = body.role as ProviderRole;
    const decision = body.decision;
    if (!profileId || !Object.hasOwn(tableForRole, role) || !["approved", "rejected"].includes(decision)) {
      return json({ error: "Invalid provider review request." }, 400);
    }

    const table = tableForRole[role];
    const { data: application, error: applicationError } = await db.from(table)
      .select("id,profile_id,status").eq("profile_id", profileId).maybeSingle();
    if (applicationError) throw applicationError;
    if (!application) return json({ error: "Provider application was not found." }, 404);
    if (application.status === "suspended") return json({ error: "Suspended providers must be reinstated through the Director account controls." }, 409);

    const { data: roleRow, error: roleError } = await db.from("app_roles")
      .select("id").eq("code", role).single();
    if (roleError || !roleRow) throw new Error("Provider role is not configured.");

    if (decision === "approved") {
      const { data: assignment, error: assignmentReadError } = await db.from("user_role_assignments")
        .select("id").eq("user_id", profileId).eq("role_id", roleRow.id).maybeSingle();
      if (assignmentReadError) throw assignmentReadError;
      if (assignment) {
        const { error } = await db.from("user_role_assignments").update({
          is_active: true, assigned_by: directorId,
        }).eq("id", assignment.id);
        if (error) throw error;
      } else {
        const { error } = await db.from("user_role_assignments").insert({
          user_id: profileId, role_id: roleRow.id, assigned_by: directorId, is_active: true,
        });
        if (error) throw error;
      }
    } else {
      const { error } = await db.from("user_role_assignments").update({ is_active: false })
        .eq("user_id", profileId).eq("role_id", roleRow.id);
      if (error) throw error;
    }

    // Tractor-owner records use "verified" as their approved state; the
    // mechanic and auto-spares tables use "approved".
    const persistedStatus = role === "tractor_owner" && decision === "approved"
      ? "verified"
      : decision;
    const { error: updateError } = await db.from(table).update({
      status: persistedStatus, updated_at: new Date().toISOString(),
    }).eq("id", application.id);
    if (updateError) throw updateError;

    return json({ success: true, decision });
  } catch (error) {
    return json({ error: error instanceof Error ? error.message : "Provider review failed." }, 400);
  }
});
