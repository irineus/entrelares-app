import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { secretKey } from "../_shared/keys.ts";
import { isSecretKeyCaller } from "../_shared/auth.ts";

// Scheduled (cron) Edge Function — F-70.
// Calls plan_end_reminders_due(), which finds every family whose LAST planned
// day is 30 or 7 days away (or already past), stamps the ledger and writes the
// in-app `plan_ending` rows (the push follows from the notifications trigger)
// in one transaction. F-59 (02/10/2026): it used to send e-mail twins for the
// D-7 and `ended` stages; the plan's end is push + in-app only now, so this
// function only runs the RPC and counts.
//
// Scheduled by the migration itself (pg_cron `plan-end-reminders-daily`,
// 12:00 UTC = 09:00 BRT) with the Vault secret key on `apikey`, so verify_jwt
// is off and the key is checked here — same shape as auto-approve-expired.

interface DueRow {
  profile_id: number;
  stage: "d30" | "d7" | "ended";
  plan_end: string;
  send_email: boolean;
}

serve(async (req: Request) => {
  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceKey  = secretKey();
    if (!isSecretKeyCaller(req, serviceKey)) {
      console.warn("[plan-end-reminders] refused — caller did not present the secret key");
      return json({ error: "Não autorizado." }, 401);
    }
    const supabase = createClient(supabaseUrl, serviceKey);

    const { data, error } = await supabase.rpc("plan_end_reminders_due");
    if (error) {
      console.error(`[plan-end-reminders] rpc failed — ${error.message}`);
      return json({ error: error.message }, 500);
    }

    const rows = (data ?? []) as DueRow[];
    // S-13: counts only — never an address.
    console.log(`[plan-end-reminders] ${rows.length} recipient(s) told`);

    return json({ told: rows.length });
  } catch (err) {
    console.error("[plan-end-reminders] unhandled error:", err);
    return json({ error: String(err) }, 500);
  }
});

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
