import "jsr:@supabase/functions-js/edge-runtime.d.ts";

// Permanent customer deletion is intentionally disabled for TAJIR.
// Customer records must remain recoverable and linked to their financial history.
Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok");
  return Response.json(
    {
      success: false,
      error: "Permanent customer deletion is disabled. Archive the account instead; TAJIR retains customer, order, payment and audit history.",
      permanent_deletion_disabled: true,
    },
    { status: 410 },
  );
});
