// T-39 (PR2) — checkout + subscription management (Asaas, hosted).
//
// The app calls this with the USER's JWT (verify_jwt stays ON). Three actions:
//
//   { action: "checkout", cycle: "monthly" | "annual" }
//     → creates a RECURRENT Asaas Payment Link for the caller's family and
//       returns { url } to redirect to. The payer fills name/CPF/e-mail on
//       Asaas's own PCI-scoped page — nothing sensitive touches our domain.
//       The link carries externalReference `family:<id>`; the webhook adopts
//       the subscription the gateway creates from it on the first payment.
//
//   { action: "cancel" }
//     → stops future charges: deletes the Asaas subscription (when it already
//       exists) or the pending payment link (when nobody paid yet). The plan
//       itself is NOT touched here — premium runs until current_period_end and
//       the grace cron (PR3) flips it on lapse; a mere click can't nuke an
//       already-paid period.
//
//   { action: "reactivate" }                                          [F-42]
//     → for a family that CANCELED but still has paid time: recreates the
//       gateway subscription with NO charge today, the first invoice falling
//       due exactly at current_period_end. No payment link, no redirect —
//       nothing to pay right now, so the caller gets { ok, scheduled: true }
//       and the row moves to 'scheduled'.
//       Only for invoice-style methods (Pix/boleto): resuming a card auto-debit
//       needs the card token, which our hosted/no-PCI model never touches, so
//       card families are told to use the normal checkout (whose paid time is
//       ADDITIVE — they lose nothing either way). The gateway customer comes
//       from `external_customer_id`, stored by the webhook on the first
//       confirmed payment, so no payer data is re-collected.
//
// Guard order (each check returns a distinct status so the UI can speak PT-BR):
//   401 no/invalid JWT → 403 caller is not a family admin → 409 billing
//   disabled (billing.enabled) → 503 gateway key not configured → gateway work.
//
// Secrets/env: ASAAS_API_KEY (full-access, per environment), ASAAS_API_URL
// (defaults to the SANDBOX — production must set it explicitly, so a
// misconfigured environment can never charge real money by accident), APP_URL
// (redirect target after payment, same convention as send-swap-email).

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { publishableKey, secretKey } from "../_shared/keys.ts";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}

interface CheckoutPayload {
  // "avulso" (F-48): a single NON-RECURRING Pix charge for one period — no
  // card on file, no auto-renew. Same price settings as the subscription.
  action?: "checkout" | "avulso" | "cancel" | "reactivate";
  cycle?: "monthly" | "annual";
}

// F-42: methods that bill by invoice, i.e. that need no stored instrument to
// charge later. Anything else (card, or a value we don't recognise) cannot be
// resumed without the payer's token — the safe default is "not reactivatable".
const RESCHEDULABLE_METHODS = new Set(["PIX", "BOLETO"]);

// Asaas subscription cycles, by ours.
const ASAAS_CYCLE: Record<string, string> = { monthly: "MONTHLY", annual: "YEARLY" };

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceKey = secretKey();
    const service = createClient(supabaseUrl, serviceKey);

    // ── Caller: resolved from the user's JWT (RLS applies on this client) ────
    const authHeader = req.headers.get("Authorization") ?? "";
    const userClient = createClient(supabaseUrl, publishableKey(), {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: userData } = await userClient.auth.getUser();
    if (!userData?.user) {
      return jsonResponse({ error: "Sessão inválida. Entre novamente." }, 401);
    }
    const { data: me } = await service
      .from("profiles")
      .select("id, family_id, full_name, email, is_admin")
      .eq("user_id", userData.user.id)
      .maybeSingle();
    if (!me) {
      return jsonResponse({ error: "Perfil não encontrado." }, 401);
    }
    if (!me.is_admin) {
      return jsonResponse(
        { error: "Somente administradores da família podem gerenciar a assinatura." }, 403);
    }

    const { action, cycle }: CheckoutPayload = await req.json();

    // ── Master switch (same row the UI mirrors) ──────────────────────────────
    const { data: enabled } = await service.rpc("setting_bool", {
      p_key: "billing.enabled",
      p_default: false,
    });
    if (!enabled) {
      return jsonResponse(
        { error: "As assinaturas ainda não estão abertas. Registre seu interesse!" }, 409);
    }

    const asaasKey = Deno.env.get("ASAAS_API_KEY");
    // Sandbox by default: production must OPT IN via ASAAS_API_URL — a
    // misconfigured environment can never charge real money by accident.
    const asaasUrl = (Deno.env.get("ASAAS_API_URL") ?? "https://api-sandbox.asaas.com/v3")
      .replace(/\/$/, "");
    if (!asaasKey) {
      return jsonResponse(
        { error: "Pagamentos indisponíveis no momento. Tente novamente mais tarde." }, 503);
    }

    const asaas = (path: string, init: RequestInit = {}) =>
      fetch(`${asaasUrl}${path}`, {
        ...init,
        headers: {
          "Content-Type": "application/json",
          "access_token": asaasKey,
          ...(init.headers ?? {}),
        },
      });

    const { data: existing } = await service
      .from("subscriptions")
      .select("*")
      .eq("family_id", me.family_id)
      .maybeSingle();

    const nowUtc = new Date().toISOString();

    // ── action: cancel ───────────────────────────────────────────────────────
    if (action === "cancel") {
      if (!existing || existing.status === "canceled") {
        return jsonResponse({ error: "Não há assinatura ativa para cancelar." }, 404);
      }

      if (existing.external_subscription_id) {
        const del = await asaas(`/subscriptions/${existing.external_subscription_id}`,
          { method: "DELETE" });
        if (!del.ok && del.status !== 404) {
          const detail = await del.text();
          console.error("Asaas subscription delete failed:", del.status, detail);
          await service.from("billing_events").insert({
            event_id: `checkout_error_${crypto.randomUUID()}`,
            event_type: "CHECKOUT_ERROR",
            family_id: me.family_id,
            payload: { status: del.status, body: detail.slice(0, 4000), action: "cancel" },
          });
          return jsonResponse(
            { error: "O cancelamento falhou no provedor de pagamento. Tente novamente." }, 502);
        }
      } else if (existing.external_payment_link_id) {
        // Nobody paid yet — remove the pending link so it can't be paid later.
        await asaas(`/paymentLinks/${existing.external_payment_link_id}`, { method: "DELETE" });
      }

      await service
        .from("subscriptions")
        .update({ status: "canceled", canceled_at: nowUtc, updated_at: nowUtc })
        .eq("id", existing.id);

      // Paid time is honored: the plan stays premium until current_period_end
      // (grace cron flips it). A never-paid pending subscription has no period
      // to honor — drop the plan is wrong too (they may be on trial); leave
      // entitlement to the F-32 rule untouched either way.
      return jsonResponse({ ok: true, canceled: true });
    }

    // ── action: reactivate (F-42) ────────────────────────────────────────────
    // Come back with NO charge today: the gateway subscription is recreated for
    // the stored customer and its first invoice falls due when the already-paid
    // period ends. Guards are ordered cheapest-first and each returns its own
    // message, because the UI shows them verbatim.
    if (action === "reactivate") {
      if (!existing) {
        return jsonResponse({ error: "Não há assinatura para reativar." }, 404);
      }
      if (existing.status !== "canceled") {
        return jsonResponse(
          { error: "Sua família já tem uma assinatura. Gerencie-a na página da família." }, 409);
      }

      // Reactivation only makes sense while paid time is still running — that
      // remaining period IS what the family keeps while no new money moves. Once
      // it lapsed there is nothing to schedule against: that is a plain checkout.
      const paidUntil = existing.current_period_end
        ? new Date(existing.current_period_end) : null;
      if (!paidUntil || paidUntil <= new Date(nowUtc)) {
        return jsonResponse(
          { error: "O período já pago terminou. Assine novamente para voltar ao Premium." }, 409);
      }

      // F-48: an avulso row never had a gateway subscription — there is
      // nothing to "reactivate". The way back is another avulso or a real
      // subscription (both additive). Mirrored client-side in CanReactivate.
      if (existing.single_charge) {
        return jsonResponse(
          {
            error: "Seu último pagamento foi um Pix avulso, sem assinatura. " +
              "Para continuar no Premium, faça um novo Pix avulso ou assine — o tempo já pago é somado.",
          },
          409);
      }

      if (!existing.external_customer_id) {
        return jsonResponse(
          { error: "Não encontramos seu cadastro de pagamento. Assine novamente para voltar ao Premium." },
          409);
      }

      const method = (existing.billing_type ?? "").toUpperCase();
      if (!RESCHEDULABLE_METHODS.has(method)) {
        // Card (or an unknown method): resuming auto-debit needs the card
        // token, which never touches our side. Nothing is lost by paying now —
        // the webhook ADDS the remaining time to the new period.
        return jsonResponse(
          {
            error: "A reativação sem cobrança agora vale para Pix e boleto. " +
              "Para retomar no cartão, assine novamente — o tempo já pago é somado ao novo período.",
          },
          409);
      }

      // Asaas bills on the Brazilian calendar; deriving the due date in UTC
      // could land it a day off the period the family actually sees.
      const nextDueDate = new Intl.DateTimeFormat("en-CA", {
        timeZone: "America/Sao_Paulo",
        year: "numeric", month: "2-digit", day: "2-digit",
      }).format(paidUntil);

      // Current configured price, not the one stored on the canceled row: the
      // acquired-price guarantee in the Terms protects ACTIVE accounts, and the
      // UI must never schedule a charge different from the one it displayed.
      const rPriceKey = existing.cycle === "annual"
        ? "billing.price_annual_cents" : "billing.price_monthly_cents";
      const { data: rPriceCents } = await service.rpc("setting_int", {
        p_key: rPriceKey,
        // F-48: promotional launch price (Aug 2026) — defaults mirror the seeds
        // (549, not 490: Asaas refuses Pix/boleto charges under R$ 5,00).
        p_default: existing.cycle === "annual" ? 5490 : 549,
      });

      const created = await asaas("/subscriptions", {
        method: "POST",
        body: JSON.stringify({
          customer: existing.external_customer_id,
          billingType: method,
          value: (rPriceCents as number) / 100,
          nextDueDate,
          cycle: ASAAS_CYCLE[existing.cycle] ?? "MONTHLY",
          description: `Entrelares Premium (${existing.cycle === "annual" ? "anual" : "mensal"})`,
          externalReference: `family:${me.family_id}`,
        }),
      });
      if (!created.ok) {
        const detail = await created.text();
        console.error("Asaas subscription reactivate failed:", created.status, detail);
        await service.from("billing_events").insert({
          event_id: `checkout_error_${crypto.randomUUID()}`,
          event_type: "CHECKOUT_ERROR",
          family_id: me.family_id,
          payload: { status: created.status, body: detail.slice(0, 4000), action: "reactivate" },
        });
        return jsonResponse(
          { error: "Não foi possível reativar a assinatura. Tente novamente em instantes." }, 502);
      }
      const newSub: { id: string } = await created.json();

      // 'scheduled', not 'active': no money moved yet. The plan itself needs no
      // touch — the family is premium until current_period_end either way, and
      // the grace cron lapses a scheduled-unpaid row exactly like a canceled one.
      const { error: schedError } = await service
        .from("subscriptions")
        .update({
          status: "scheduled",
          price_cents: rPriceCents as number,
          external_subscription_id: newSub.id,
          external_payment_link_id: null,
          canceled_at: null,
          overdue_since: null,
          updated_at: nowUtc,
        })
        .eq("id", existing.id);
      if (schedError) throw schedError;

      return jsonResponse({ ok: true, scheduled: true, nextDueDate });
    }

    // ── action: checkout | avulso ────────────────────────────────────────────
    // Same flow, two charge shapes: "checkout" creates the RECURRENT payment
    // link (subscription); "avulso" (F-48) a DETACHED one — a single Pix charge
    // for one period, adopted by the webhook via externalReference/payment link
    // (a detached payment carries no subscription id).
    if ((action !== "checkout" && action !== "avulso")
      || (cycle !== "monthly" && cycle !== "annual")) {
      return jsonResponse({ error: "Requisição inválida." }, 400);
    }
    const isAvulso = action === "avulso";
    // 'scheduled' (F-42) blocks a new checkout too: a gateway subscription
    // already exists for this family and a second one would double-charge.
    if (existing && ["active", "overdue", "scheduled"].includes(existing.status)) {
      return jsonResponse(
        { error: "Sua família já tem uma assinatura. Gerencie-a na página da família." }, 409);
    }

    const priceKey = cycle === "monthly" ? "billing.price_monthly_cents" : "billing.price_annual_cents";
    // F-48: promotional launch price (Aug 2026) — defaults mirror the seeds
    // (549, not 490: Asaas refuses Pix/boleto charges under R$ 5,00).
    const priceDefault = cycle === "monthly" ? 549 : 5490;
    const { data: dueDaysSetting } = await service.rpc("setting_int", {
      p_key: "billing.asaas_due_days",
      p_default: 5,
    });
    const dueDays = Number.isInteger(dueDaysSetting) ? (dueDaysSetting as number) : 5;

    const { data: priceCents } = await service.rpc("setting_int", {
      p_key: priceKey,
      p_default: priceDefault,
    });

    const appUrl = (Deno.env.get("APP_URL") ?? "https://web.entrelares.app")
      .replace(/\/$/, "");

    const periodLabel = cycle === "monthly" ? "1 mês" : "12 meses";
    const linkBody = {
      name: isAvulso
        ? `Entrelares Premium — Pix avulso (${periodLabel})`
        : `Entrelares Premium (${cycle === "monthly" ? "mensal" : "anual"})`,
      description: isAvulso
        ? `Pagamento único de ${periodLabel} de Premium — sem assinatura e sem renovação ` +
          "automática. O essencial continua gratuito."
        : "Assinatura Premium do Entrelares — recursos avançados para a sua família. " +
          "O essencial continua gratuito.",
      // Avulso is the "no card data" rail — Pix only, one DETACHED charge;
      // the subscription link keeps letting the payer choose on the Asaas page.
      billingType: isAvulso ? "PIX" : "UNDEFINED",
      chargeType: isAvulso ? "DETACHED" : "RECURRENT",
      ...(isAvulso ? {} : { subscriptionCycle: cycle === "monthly" ? "MONTHLY" : "YEARLY" }),
      // Business days for each generated charge to fall due — REQUIRED by the
      // payment-link API (the sandbox 400s without it). Pix/card settle
      // instantly; this only bounds how long an unpaid invoice stays open.
      // T-82: `billing.asaas_due_days` (default 5, range 1–30 business days —
      // the Asaas docs set no limit, the range is the owner's).
      dueDateLimitDays: dueDays,
      value: (priceCents as number) / 100,
      externalReference: `family:${me.family_id}`,
      notificationEnabled: true,
      callback: { successUrl: `${appUrl}/premium/retorno`, autoRedirect: true },
    };

    const created = await asaas("/paymentLinks", {
      method: "POST",
      body: JSON.stringify(linkBody),
    });
    if (!created.ok) {
      // Observability: the gateway's exact answer goes to the service-role-only
      // ledger (console output is not queryable via the management API).
      const detail = await created.text();
      console.error("Asaas payment link failed:", created.status, detail);
      await service.from("billing_events").insert({
        event_id: `checkout_error_${crypto.randomUUID()}`,
        event_type: "CHECKOUT_ERROR",
        family_id: me.family_id,
        payload: { status: created.status, body: detail.slice(0, 4000), action: "checkout", cycle },
      });
      return jsonResponse(
        { error: "Não foi possível iniciar o pagamento. Tente novamente em instantes." }, 502);
    }
    const link: { id: string; url: string } = await created.json();

    // One row per family: refresh the pending/canceled row or create the first.
    // single_charge is set BOTH ways — switching between avulso and recurring
    // reuses the same row, so the flag must follow the latest checkout.
    const rowPatch = {
      family_id: me.family_id,
      status: "pending",
      cycle,
      price_cents: priceCents as number,
      single_charge: isAvulso,
      external_payment_link_id: link.id,
      external_subscription_id: null,
      canceled_at: null,
      overdue_since: null,
      updated_at: nowUtc,
    };
    const { error: upsertError } = existing
      ? await service.from("subscriptions").update(rowPatch).eq("id", existing.id)
      : await service.from("subscriptions").insert(rowPatch);
    if (upsertError) throw upsertError;

    return jsonResponse({ ok: true, url: link.url });
  } catch (err) {
    console.error("billing-checkout error:", err);
    return jsonResponse(
      { error: "Erro inesperado ao preparar o pagamento. Tente novamente." }, 500);
  }
});
