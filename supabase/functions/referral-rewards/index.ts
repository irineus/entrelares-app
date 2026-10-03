import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { secretKey } from "../_shared/keys.ts";
import { isSecretKeyCaller } from "../_shared/auth.ts";
import { deferStorePurchase, fetchStorePurchase } from "../_shared/play.ts";

// Scheduled (cron) Edge Function — F-80 PR 3.
//
// The referral job is SQL (`referral_rewards_due`, 12:00 UTC). Everything it
// can deliver by itself (the trial and the paid period) it delivers; a referrer
// whose next charge belongs to GOOGLE is left `pending_rail` / `play_queued`,
// because only the Play Developer API can move that charge. This function is
// that one HTTP step, run by pg_cron at 12:15 UTC (`referral-rewards-play-daily`)
// with the Vault secret key on `apikey` — verify_jwt is off and the key is
// checked here, the shape of plan-end-reminders.
//
// Per pending Play reward of a referrer family:
//   1. read the purchase (its current expiry) — the truth, never our row;
//   2. stamp the row `play_in_flight` with {expected_ms, desired_ms} BEFORE
//      calling Google, desired = expiry + one calendar month (UTC);
//   3. `purchases.subscriptions.defer`:
//        ok        → our `current_period_end` = Play's new expiry, then
//                    `referral_reward_delivered()` (status rewarded + notice);
//        401/403   → `play_permission_denied` (the service account lacks
//                    "Manage orders and subscriptions"); retried every day;
//        404/410   → `play_not_found`; other 4xx → `play_error` (operator);
//        5xx / network failure → stays `play_in_flight`: the outcome is
//                    UNKNOWN, so the next run reconciles instead of resending —
//                    expiry ≥ desired means it was applied (deliver), expiry =
//                    expected means it was not (retry), anything else is
//                    `play_error` for the operator. Google's own
//                    `expectedExpiryTimeMillis` lock refuses a deferral built on
//                    a stale expiry, so a month is never deferred twice.
//
// No PLAY_SERVICE_ACCOUNT in the environment → every queued row is marked
// `play_not_configured` and nothing is called. While `feature.referral` is off
// the function answers `skipped` and reads nothing else.
//
// Body (optional): { "family_id": <referrer family> } — the DB gate scopes a
// run to its own throwaway family; the cron sends `{}`.
// S-13: logs carry counts and closed reason codes only — never a family id.

interface PendingRow {
  referred_family_id: number;
  referrer_family_id: number;
  reward_pending_reason: string;
  reward_detail: { expected_ms?: string; desired_ms?: string } | null;
}

/** The reasons a run picks up again; `play_error` waits for the operator. */
const RETRIED = [
  "play_queued",
  "play_in_flight",
  "play_not_configured",
  "play_permission_denied",
  "play_no_subscription",
  "play_not_found",
];

function plusOneMonth(ms: string): string {
  const d = new Date(Number(ms));
  d.setUTCMonth(d.getUTCMonth() + 1);
  return String(d.getTime());
}

serve(async (req: Request) => {
  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceKey = secretKey();
    if (!isSecretKeyCaller(req, serviceKey)) {
      console.warn("[referral-rewards] refused — caller did not present the secret key");
      return json({ error: "Não autorizado." }, 401);
    }
    const admin = createClient(supabaseUrl, serviceKey, { auth: { persistSession: false } });

    const { data: enabled, error: flagError } = await admin.rpc("setting_bool", {
      p_key: "feature.referral",
      p_default: false,
    });
    if (flagError) throw flagError;
    if (enabled !== true) return json({ skipped: "dark" });

    const body = await req.json().catch(() => ({})) as { family_id?: number };
    const scope = Number.isInteger(body.family_id) ? body.family_id! : null;

    let query = admin
      .from("family_referrals")
      .select("referred_family_id, referrer_family_id, reward_pending_reason, reward_detail")
      .eq("status", "pending_rail")
      .eq("reward_rail", "play")
      .in("reward_pending_reason", RETRIED)
      .order("referred_family_id", { ascending: true });
    if (scope !== null) query = query.eq("referrer_family_id", scope);
    const { data: rows, error: readError } = await query;
    if (readError) throw readError;

    const counts: Record<string, number> = {};
    const tally = (k: string) => (counts[k] = (counts[k] ?? 0) + 1);

    const mark = async (row: PendingRow, reason: string, detail: unknown, count = true) => {
      const { error } = await admin
        .from("family_referrals")
        .update({ reward_pending_reason: reason, reward_detail: detail })
        .eq("referred_family_id", row.referred_family_id)
        .eq("status", "pending_rail");
      if (error) throw error;
      if (count) tally(reason);
    };

    const deliver = async (row: PendingRow, subscriptionId: number, expiryMs: string) => {
      const { error: periodError } = await admin
        .from("subscriptions")
        .update({
          current_period_end: new Date(Number(expiryMs)).toISOString(),
          updated_at: new Date().toISOString(),
        })
        .eq("id", subscriptionId);
      if (periodError) throw periodError;
      const { error } = await admin.rpc("referral_reward_delivered", {
        p_referred_family_id: row.referred_family_id,
      });
      if (error) throw error;
      tally("delivered");
    };

    const configured = !!Deno.env.get("PLAY_SERVICE_ACCOUNT");
    const packageName = Deno.env.get("PLAY_PACKAGE_NAME") ?? "com.entrelares.app";

    for (const row of (rows ?? []) as PendingRow[]) {
      if (!configured) {
        // An attempt whose answer was never seen keeps its evidence.
        if (row.reward_pending_reason !== "play_in_flight") {
          await mark(row, "play_not_configured", null);
        }
        continue;
      }

      const { data: sub, error: subError } = await admin
        .from("subscriptions")
        .select("id, gateway, store_purchase_token, store_product_id")
        .eq("family_id", row.referrer_family_id)
        .maybeSingle();
      if (subError) throw subError;
      if (!sub || sub.gateway !== "play" || !sub.store_purchase_token || !sub.store_product_id) {
        await mark(row, "play_no_subscription", row.reward_detail);
        continue;
      }

      try {
        const purchase = await fetchStorePurchase(
          packageName, sub.store_product_id, sub.store_purchase_token);
        const expiry = purchase?.expiryTimeMillis;
        if (!purchase || !expiry) {
          await mark(row, "play_not_found", row.reward_detail);
          continue;
        }

        // Reconcile an attempt whose answer never arrived.
        const sent = row.reward_pending_reason === "play_in_flight" ? row.reward_detail : null;
        if (sent?.desired_ms && sent.expected_ms) {
          if (Number(expiry) >= Number(sent.desired_ms)) {
            await deliver(row, sub.id, expiry);
            continue;
          }
          if (expiry !== sent.expected_ms) {
            await mark(row, "play_error", { ...sent, seen_ms: expiry });
            continue;
          }
          // expiry === expected: Google never applied it — send again below.
        }

        const detail = { expected_ms: expiry, desired_ms: plusOneMonth(expiry) };
        await mark(row, "play_in_flight", detail, false);

        const outcome = await deferStorePurchase(
          packageName, sub.store_product_id, sub.store_purchase_token,
          detail.expected_ms, detail.desired_ms);
        if (outcome.ok) {
          await deliver(row, sub.id, outcome.newExpiryTimeMillis);
        } else if (outcome.status === 401 || outcome.status === 403) {
          await mark(row, "play_permission_denied", { status: outcome.status });
        } else if (outcome.status === 404 || outcome.status === 410) {
          await mark(row, "play_not_found", { status: outcome.status });
        } else if (outcome.status >= 500) {
          // Unknown outcome: leave it in flight for the next run to reconcile.
          tally("play_in_flight");
        } else {
          await mark(row, "play_error", { ...detail, status: outcome.status });
        }
      } catch (err) {
        // Reading the purchase or reaching Google failed: if the row is in
        // flight it stays so (reconciled tomorrow); otherwise it simply waits.
        console.error(`[referral-rewards] play call failed — ${String(err).slice(0, 300)}`);
        tally("unreachable");
      }
    }

    console.log(`[referral-rewards] ${JSON.stringify(counts)}`);
    return json({ ok: true, counts });
  } catch (err) {
    console.error("[referral-rewards] unhandled error:", err);
    return json({ error: "internal" }, 500);
  }
});

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
