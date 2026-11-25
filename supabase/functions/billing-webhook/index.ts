// T-39 (PR1) — Asaas billing webhook: gateway events → family entitlement.
//
// Asaas POSTs payment/subscription events here. This function is the ONLY
// bridge between the gateway and `families.plan`: it authenticates the call,
// records the event in the `billing_events` ledger (idempotency + audit) and
// applies the effect through the F-32 `set_family_plan` RPC — entitlement
// logic itself lives in the database and is not re-implemented here.
//
// Event → effect map (v1, PR1):
//   PAYMENT_CONFIRMED / PAYMENT_RECEIVED
//       → subscription active, plan = premium, period end = one cycle counted
//         from max(dueDate, paid period end, running trial end) — paid time
//         and trial days are ADDITIVE, never forfeited (F-46: the trial is a
//         first payment of R$ 0; a consumed trial is cleared afterwards).
//         (Pix settles as RECEIVED; card pre-authorizes as CONFIRMED — either
//         one is "the money is good" for entitlement purposes.)
//         Also stores `payment.billingType` on the row (F-42): the method of
//         the last confirmed payment is what decides whether the family can
//         later reactivate WITHOUT paying today. Same branch covers a
//         'scheduled' row whose first invoice was paid — it becomes active and
//         its period extends, exactly like any renewal.
//         F-48: a payment WITHOUT a subscription id that matches a
//         single_charge row is the AVULSO settlement — same additive period,
//         but the row rests at 'canceled' (paid until X, no recurrence).
//   PAYMENT_OVERDUE
//       → subscription overdue (stamped overdue_since). The plan is NOT
//         touched here: the grace-period cron (PR3, billing.grace_days)
//         downgrades after the grace window. Data is never deleted.
//   PAYMENT_REFUNDED
//       → subscription canceled, plan = free immediately (money returned).
//   SUBSCRIPTION_DELETED / SUBSCRIPTION_INACTIVATED
//       → subscription canceled (no further charges). Premium survives until
//         current_period_end; the PR3 cron flips the plan when it lapses.
//   anything else → recorded in the ledger, acknowledged, no effect.
//
// Security:
//   · Deployed with --no-verify-jwt (also config.toml): Asaas cannot send a
//     Supabase JWT. The SHARED TOKEN below is the real authentication.
//   · Auth: Asaas sends the configured `asaas-access-token` header on every
//     webhook call; it must equal the ASAAS_WEBHOOK_TOKEN secret. No token,
//     no processing (401). The service-role key never leaves the server.
//   · Idempotency: INSERT the gateway event id into billing_events with
//     ON CONFLICT DO NOTHING; when the row already existed the event was
//     already applied — return 200 without reapplying (Asaas redelivers).
//   · Unknown subscriptions/events return 200: a non-2xx makes Asaas pause
//     the whole webhook queue, which would silence every OTHER family's
//     events — never fail for content we simply don't care about.

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { secretKey } from "../_shared/keys.ts";
import { notifySale, type SaleCycle } from "../_shared/sale_alert.ts";

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

interface AsaasEvent {
  id?: string;
  event?: string;
  payment?: {
    id?: string;
    customer?: string;
    subscription?: string;
    value?: number;
    dueDate?: string;
    billingType?: string;
    status?: string;
    externalReference?: string;
    paymentLink?: string;
  };
  subscription?: {
    id?: string;
    customer?: string;
    status?: string;
  };
}

// Months a paid invoice buys, by our subscription cycle.
const CYCLE_MONTHS: Record<string, number> = { monthly: 1, annual: 12 };

const ACTIVATING = new Set(["PAYMENT_CONFIRMED", "PAYMENT_RECEIVED"]);
const CANCELING  = new Set(["SUBSCRIPTION_DELETED", "SUBSCRIPTION_INACTIVATED"]);

serve(async (req: Request) => {
  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed." }, 405);
  }

  const expectedToken = Deno.env.get("ASAAS_WEBHOOK_TOKEN");
  const gotToken = req.headers.get("asaas-access-token");
  if (!expectedToken || !gotToken || gotToken !== expectedToken) {
    return jsonResponse({ error: "Unauthorized." }, 401);
  }

  try {
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      secretKey(),
    );

    const event: AsaasEvent = await req.json();
    const eventId = event.id;
    const eventType = event.event;
    if (!eventId || !eventType) {
      return jsonResponse({ error: "Malformed event." }, 400);
    }

    // The subscription reference lives on payment events as payment.subscription
    // and on subscription events as subscription.id.
    const externalSubscriptionId =
      event.payment?.subscription ?? event.subscription?.id ?? null;

    // Resolve our subscription row (may be null for foreign/test events).
    interface SubscriptionRow {
      id: number;
      family_id: number;
      cycle: string;
      status: string;
      current_period_end: string | null;
      single_charge: boolean;
    }
    const ROW_COLUMNS = "id, family_id, cycle, status, current_period_end, single_charge";
    let subscription: SubscriptionRow | null = null;
    if (externalSubscriptionId) {
      const { data } = await supabase
        .from("subscriptions")
        .select(ROW_COLUMNS)
        .eq("external_subscription_id", externalSubscriptionId)
        .maybeSingle();
      subscription = data;
    }

    // Payment-link flow (PR2): the FIRST event of a gateway-created
    // subscription references a sub id we don't know yet. Adopt it into the
    // family's pending row — matched by externalReference `family:<id>`
    // (primary) or by the stored payment link id (fallback).
    // F-48: an AVULSO payment (DETACHED charge) carries NO subscription id —
    // ever — so the same match now also runs for subscription-less payment
    // events; only the external_subscription_id write is conditional.
    if (!subscription && event.payment) {
      let pending: SubscriptionRow | null = null;

      const familyMatch = /^family:(\d+)$/.exec(event.payment?.externalReference ?? "");
      if (familyMatch) {
        const { data } = await supabase
          .from("subscriptions")
          .select(ROW_COLUMNS)
          .eq("family_id", Number(familyMatch[1]))
          .maybeSingle();
        pending = data;
      }
      if (!pending && event.payment?.paymentLink) {
        const { data } = await supabase
          .from("subscriptions")
          .select(ROW_COLUMNS)
          .eq("external_payment_link_id", event.payment.paymentLink)
          .maybeSingle();
        pending = data;
      }

      if (pending) {
        if (externalSubscriptionId) {
          const { error } = await supabase
            .from("subscriptions")
            .update({
              external_subscription_id: externalSubscriptionId,
              external_customer_id: event.payment?.customer ?? null,
              updated_at: new Date().toISOString(),
            })
            .eq("id", pending.id);
          if (error) throw error;
        }
        subscription = pending;
      }
    }

    // Idempotency gate: first write wins; a redelivery finds the row and stops.
    const { data: inserted, error: ledgerError } = await supabase
      .from("billing_events")
      .upsert(
        {
          event_id: eventId,
          event_type: eventType,
          subscription_id: subscription?.id ?? null,
          family_id: subscription?.family_id ?? null,
          payload: event,
        },
        { onConflict: "event_id", ignoreDuplicates: true },
      )
      .select("id");
    if (ledgerError) throw ledgerError;
    if (!inserted || inserted.length === 0) {
      return jsonResponse({ ok: true, duplicate: true });
    }

    // Foreign subscription (or none referenced): recorded, acknowledged, done.
    if (!subscription) {
      return jsonResponse({ ok: true, ignored: true });
    }

    const nowUtc = new Date().toISOString();

    // T-111: what the operator's alert says about this row. Never a family id.
    const paymentId = event.payment?.id ?? null;
    const amountCents = typeof event.payment?.value === "number"
      ? Math.round(event.payment.value * 100) : null;
    const cycleOf = (single: boolean): SaleCycle =>
      single ? "single"
      : subscription!.cycle === "monthly" || subscription!.cycle === "annual"
      ? subscription!.cycle : "unknown";

    if (ACTIVATING.has(eventType)) {
      // The paid invoice covers one cycle counted from whichever is LATEST:
      // its due date, the end of the already-paid period, or the end of a
      // still-running trial. Re-subscribing before a canceled-but-paid period
      // lapses therefore ADDS the remaining time instead of discarding it (an
      // early renewal charge never shortens the running period either), and a
      // family paying DURING its 30-day trial keeps the remaining trial days
      // (F-46: the trial is a first payment of R$ 0 — the paid cycle starts
      // at the trial end, never at the payment date). All candidates compare
      // as plain UTC instants (dueDate parses as UTC midnight).
      const due = event.payment?.dueDate ? new Date(event.payment.dueDate) : new Date();
      const paidUntil = subscription.current_period_end
        ? new Date(subscription.current_period_end) : null;

      const { data: family, error: familyError } = await supabase
        .from("families")
        .select("trial_ends_at")
        .eq("id", subscription.family_id)
        .maybeSingle();
      // A failed read must retry (500), not silently forfeit the trial days.
      if (familyError) throw familyError;
      // Only a STILL-RUNNING trial counts; an expired one is history.
      const trialEnd =
        family?.trial_ends_at && new Date(family.trial_ends_at).getTime() > Date.now()
          ? new Date(family.trial_ends_at)
          : null;

      let base = paidUntil && paidUntil > due ? paidUntil : due;
      if (trialEnd && trialEnd > base) base = trialEnd;
      const periodEnd = new Date(base);
      periodEnd.setUTCMonth(periodEnd.getUTCMonth() + (CYCLE_MONTHS[subscription.cycle] ?? 1));

      // F-42: remember HOW they paid. Only invoice-style methods (Pix/boleto)
      // can later be rescheduled without charging today — resuming a card
      // auto-debit would need the token we deliberately never touch. Written
      // only when the gateway actually told us (an absent billingType must not
      // erase a known one).
      const billingType = event.payment?.billingType ?? null;

      // F-48: a settled AVULSO charge buys the period but no recurrence — the
      // row rests at 'canceled' (the canceled-with-paid-time state the F-42/
      // grace machinery already understands: premium until period end, offer
      // shows "ativo até X", renewals are additive, the cron lapses it).
      // Guarded on !externalSubscriptionId so a row raced back into a RECURRING
      // checkout can never be parked 'canceled' while a live gateway
      // subscription keeps charging it.
      const isSingle = subscription.single_charge && !externalSubscriptionId;

      const { error } = await supabase
        .from("subscriptions")
        .update(isSingle
          ? {
            status: "canceled",
            canceled_at: nowUtc,
            current_period_end: periodEnd.toISOString(),
            overdue_since: null,
            updated_at: nowUtc,
            ...(event.payment?.customer ? { external_customer_id: event.payment.customer } : {}),
            ...(billingType ? { billing_type: billingType } : {}),
          }
          : {
            status: "active",
            current_period_end: periodEnd.toISOString(),
            overdue_since: null,
            updated_at: nowUtc,
            ...(billingType ? { billing_type: billingType } : {}),
          })
        .eq("id", subscription.id);
      if (error) throw error;

      const { error: planError } = await supabase.rpc("set_family_plan", {
        p_family_id: subscription.family_id,
        p_plan: "premium",
      });
      if (planError) throw planError;

      // F-46: the trial was folded into the paid period above — clear it so
      // the period is the single source of the entitlement window. Cleared
      // only AFTER the plan flip succeeded: a family must never lose its
      // running trial to a half-applied event.
      if (trialEnd) {
        const { error: trialError } = await supabase
          .from("families")
          .update({ trial_ends_at: null })
          .eq("id", subscription.family_id);
        if (trialError) throw trialError;
      }

      // T-111: a renewal is a paid invoice of a gateway subscription that
      // already had an EARLIER paid invoice; the first one (and an avulso Pix)
      // is a purchase. Keyed by the payment, so the CONFIRMED and the RECEIVED
      // of one card charge tell the operator once.
      let kind: "purchase" | "renewal" = "purchase";
      if (externalSubscriptionId && paymentId) {
        const { data: earlier } = await supabase
          .from("billing_events")
          .select("id")
          .eq("subscription_id", subscription.id)
          .in("event_type", [...ACTIVATING])
          .eq("payload->payment->>subscription", externalSubscriptionId)
          .neq("payload->payment->>id", paymentId)
          .limit(1);
        if (earlier && earlier.length > 0) kind = "renewal";
      }
      await notifySale(supabase, {
        saleKey: `asaas:pay:${paymentId ?? eventId}`,
        rail: "asaas",
        kind,
        cycle: cycleOf(isSingle),
        amountCents,
        currency: "BRL",
        isTest: false,
      });
    } else if (eventType === "PAYMENT_OVERDUE") {
      // F-48: never for an avulso row — an unpaid single Pix charge is simply
      // an abandoned checkout, and an expired paid one is a lapse the grace
      // cron owns; the overdue/dunning surfaces are about failed RENEWALS.
      if (!subscription.single_charge) {
        const { error } = await supabase
          .from("subscriptions")
          .update({ status: "overdue", overdue_since: nowUtc, updated_at: nowUtc })
          .eq("id", subscription.id);
        if (error) throw error;
      }
      // Plan untouched: the grace cron (PR3) downgrades after billing.grace_days.
    } else if (eventType === "PAYMENT_REFUNDED") {
      const { error } = await supabase
        .from("subscriptions")
        .update({ status: "canceled", canceled_at: nowUtc, updated_at: nowUtc })
        .eq("id", subscription.id);
      if (error) throw error;

      const { error: planError } = await supabase.rpc("set_family_plan", {
        p_family_id: subscription.family_id,
        p_plan: "free",
      });
      if (planError) throw planError;

      await notifySale(supabase, {
        saleKey: `asaas:refund:${paymentId ?? eventId}`,
        rail: "asaas",
        kind: "refund",
        cycle: cycleOf(subscription.single_charge),
        amountCents,
        currency: "BRL",
        isTest: false,
      });
    } else if (CANCELING.has(eventType)) {
      const { error } = await supabase
        .from("subscriptions")
        .update({ status: "canceled", canceled_at: nowUtc, updated_at: nowUtc })
        .eq("id", subscription.id);
      if (error) throw error;
      // Premium runs until current_period_end; the PR3 cron flips it on lapse.

      // T-111: DELETED and INACTIVATED both arrive for one cancellation —
      // keyed by the gateway subscription, the operator hears it once.
      await notifySale(supabase, {
        saleKey: `asaas:cancel:${externalSubscriptionId ?? eventId}`,
        rail: "asaas",
        kind: "canceled",
        cycle: cycleOf(false),
        amountCents: null,
        currency: null,
        isTest: false,
      });
    }
    // Unknown event types: ledger row already written above — acknowledged.

    return jsonResponse({ ok: true });
  } catch (err) {
    console.error("billing-webhook error:", err);
    // Signal Asaas to retry later — genuine processing failures only.
    return jsonResponse({ error: "Internal error." }, 500);
  }
});
