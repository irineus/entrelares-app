import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { secretKey } from "../_shared/keys.ts";
import { internalCallHeaders, isSecretKeyCaller } from "../_shared/auth.ts";

// Scheduled (cron) Edge Function — F-70.
// Calls plan_end_reminders_due(), which finds every family whose LAST planned
// day is 30 or 7 days away (or already past), stamps the ledger and writes the
// in-app `plan_ending` rows (the push follows from the notifications trigger)
// in one transaction. This function only sends the e-mail twins, for the D-7
// and `ended` stages, through send-account-email — outside the family's F-38
// quota, like every other system message.
//
// Scheduled by the migration itself (pg_cron `plan-end-reminders-daily`,
// 12:00 UTC = 09:00 BRT) with the Vault secret key on `apikey`, so verify_jwt
// is off and the key is checked here — same shape as auto-approve-expired.
//
// The e-mail is best-effort, exactly like the billing grace warning: the stamp
// is NOT rolled back when Resend fails, because a second wave of in-app rows
// and pushes would be worse than one missing e-mail whose message already
// reached the app.

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

    const envName   = Deno.env.get("APP_ENVIRONMENT") ?? "Production";
    const envPrefix = envName.toLowerCase() === "production" ? "" : "[Dev] ";

    const { data, error } = await supabase.rpc("plan_end_reminders_due");
    if (error) {
      console.error(`[plan-end-reminders] rpc failed — ${error.message}`);
      return json({ error: error.message }, 500);
    }

    const rows = (data ?? []) as DueRow[];
    const mail = rows.filter((r) => r.send_email);
    // S-13: counts and stages only — never an address.
    console.log(`[plan-end-reminders] ${rows.length} recipient(s) told, ${mail.length} e-mail(s) due`);

    const results = await Promise.allSettled(
      mail.map(async (r) => {
        const res = await fetch(`${supabaseUrl}/functions/v1/send-account-email`, {
          method: "POST",
          headers: internalCallHeaders(serviceKey),
          body: JSON.stringify({
            emailType: "plan_ending",
            profileId: r.profile_id,
            planEnd: r.plan_end,
            planEnded: r.stage === "ended",
            environmentPrefix: envPrefix,
          }),
        });
        if (!res.ok) throw new Error(`send-account-email ${res.status}: ${await res.text()}`);
      }),
    );

    const failed = results.filter((x) => x.status === "rejected").length;
    for (const x of results) {
      if (x.status === "rejected") {
        console.error(`[plan-end-reminders] e-mail failed — ${x.reason instanceof Error ? x.reason.message : x.reason}`);
      }
    }
    console.log(`[plan-end-reminders] done — emails attempted=${mail.length} failed=${failed}`);

    return json({ told: rows.length, emailsAttempted: mail.length, emailsFailed: failed });
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
