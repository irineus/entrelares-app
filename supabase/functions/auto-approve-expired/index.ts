import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { secretKey } from "../_shared/keys.ts";
import { isSecretKeyCaller } from "../_shared/auth.ts";

// Scheduled (cron) Edge Function — F-24.
// Calls the auto_approve_expired() RPC, which sends the 24h reminders and
// auto-approves requests expired for 48h, applying the calendar change and
// writing the in-app notifications — the push follows from their trigger.
//
// F-59 (02/10/2026): it used to dispatch an e-mail twin of each through
// send-swap-email. The reminder and the auto-approval are push + in-app only
// now, so the rows the RPC returns are only counted.
//
// Not browser-invoked, so no CORS handling is needed. Trigger it on a schedule
// (pg_cron -> net.http_post, or the Supabase cron scheduler), e.g. hourly.
//
// S-16: the cron sends the SECRET key on `apikey` (the new keys are not JWTs and
// are rejected on `Authorization`), so the platform's verify_jwt gate cannot
// authorize this function any more — it runs with verify_jwt = false and checks
// the key here. Only a holder of the secret key gets past this point.

serve(async (req: Request) => {
  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceKey  = secretKey();
    if (!isSecretKeyCaller(req, serviceKey)) {
      console.warn("[auto-approve-expired] refused — caller did not present the secret key");
      return json({ error: "Não autorizado." }, 401);
    }
    const supabase    = createClient(supabaseUrl, serviceKey);

    const envName   = Deno.env.get("APP_ENVIRONMENT") ?? "Production";
    const envPrefix = envName.toLowerCase() === "production" ? "" : "[Dev] ";

    const { data, error } = await supabase.rpc("auto_approve_expired", { p_env_prefix: envPrefix });
    if (error) {
      console.error(`[auto-approve-expired] rpc failed — ${error.message}`);
      return json({ error: error.message }, 500);
    }

    const rows = (data ?? []) as { swap_request_id: number; email_type: string }[];
    console.log(`[auto-approve-expired] rpc processed ${rows.length} request(s)`);

    return json({ processed: rows.length });
  } catch (err) {
    console.error("[auto-approve-expired] unhandled error:", err);
    return json({ error: String(err) }, 500);
  }
});

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
