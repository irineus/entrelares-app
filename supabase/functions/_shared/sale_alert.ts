// T-111 — one e-mail to the operator per sale event, on both rails.
//
// Google Play sends no per-sale notification and Asaas is a second console, so
// the three billing functions tell the operator themselves, right after they
// applied the event: `billing-webhook` (Asaas), `billing-store-webhook` (Play
// RTDN) and `billing-store-verify` (the app's own purchase). Owner, 25/11/2026:
// first purchase, renewal, cancellation and refund each alert; a license-tester
// purchase alerts tagged "[teste]"; one e-mail per event, no digest.
//
// WHAT LEAVES. Rail, kind, cycle, amount and the time — never a family, member,
// e-mail or order id (F-69 / T-99). There is no user data in the message, so
// nothing here needs escaping.
//
// ONCE PER EVENT. `claim_sale_alert` (service role) inserts the dedupe key into
// `sale_alerts` and answers whether THIS caller sends: the Play verification
// and the RTDN of the same period share the Google order id, Asaas sends
// CONFIRMED then RECEIVED for one card payment and DELETED + INACTIVATED for
// one cancellation. The key `ops.sale_alert.enabled` off claims nothing.
//
// NEVER IN THE WAY. `notifySale` never throws and is called only AFTER the
// money and the plan were applied: a failed alert is a warning in the log and
// a row without `sent_at`, never a non-2xx that would make Pub/Sub or Asaas
// redeliver (and pause every other family's events).

import type { SupabaseClient } from "npm:@supabase/supabase-js@2";
import { isTestRecipient } from "./mail.ts";
import type { StorePurchase } from "./play.ts";
import { emailDocument, heading, list, paragraph, small, smallLink } from "./email_layout.ts";

const RESEND_API_URL = "https://api.resend.com/emails";
const OPERATOR_INBOX = "contato@entrelares.app";
const SWITCH_KEY = "ops.sale_alert.enabled";
const SEND_TIMEOUT_MS = 8000;

export type SaleRail = "play" | "asaas";
export type SaleKind = "purchase" | "renewal" | "canceled" | "refund";
export type SaleCycle = "monthly" | "annual" | "single" | "unknown";

export interface SaleAlert {
  /** The dedupe key — see the header. Never shown in the message. */
  saleKey: string;
  rail: SaleRail;
  kind: SaleKind;
  cycle: SaleCycle;
  /** Null when the event does not carry an amount (a cancellation). */
  amountCents: number | null;
  currency: string | null;
  isTest: boolean;
  /** When it happened; defaults to now. */
  at?: Date;
}

// ── Play: what a purchase says about itself ──────────────────────────────────

/** `premium_monthly` / `premium_annual` (pinned by test on the app side). */
export function playCycle(productId: string | null | undefined): SaleCycle {
  if (productId === "premium_monthly") return "monthly";
  if (productId === "premium_annual") return "annual";
  return "unknown";
}

/**
 * A Google order id is `GPA.1234-5678-9012-34567` for the first charge and
 * gains `..0`, `..1`, … on each renewal (F-107's dedupe key reads the same).
 */
export function playOrderKind(orderId: string | null | undefined): "purchase" | "renewal" {
  return /\.\.\d+$/.test(orderId ?? "") ? "renewal" : "purchase";
}

/** `purchaseType` 0 = a license-tester (test card) purchase; absent = real. */
export function isTestPurchase(purchase: StorePurchase | null | undefined): boolean {
  return purchase?.purchaseType === 0;
}

/** Only a PAID charge is a sale: `paymentState` 1, or absent (F-107's rule). 2 = free trial. */
export function isPaidPurchase(purchase: StorePurchase): boolean {
  return purchase.paymentState === undefined || purchase.paymentState === 1;
}

export function playAmountCents(purchase: StorePurchase | null | undefined): number | null {
  const micros = Number(purchase?.priceAmountMicros);
  return Number.isFinite(micros) && micros >= 0 ? Math.round(micros / 10_000) : null;
}

export function playCurrency(purchase: StorePurchase | null | undefined): string | null {
  const c = purchase?.priceCurrencyCode;
  return c && /^[A-Z]{3}$/.test(c) ? c : null;
}

// ── The message ──────────────────────────────────────────────────────────────

const KIND_TITLE: Record<SaleKind, string> = {
  purchase: "Nova assinatura",
  renewal: "Renovação",
  canceled: "Cancelamento",
  refund: "Reembolso",
};

const KIND_SENTENCE: Record<SaleKind, string> = {
  purchase: "Uma família assinou o Premium.",
  renewal: "Uma assinatura do Premium foi cobrada de novo.",
  canceled: "Uma família desligou a renovação do Premium. O acesso continua até o fim do período já pago.",
  refund: "Um pagamento do Premium foi devolvido. A família voltou ao plano Gratuito.",
};

const KIND_TONE = {
  purchase: "success",
  renewal: "success",
  canceled: "warning",
  refund: "danger",
} as const;

const RAIL_LABEL: Record<SaleRail, string> = {
  play: "Google Play",
  asaas: "web (Asaas)",
};

const CYCLE_LABEL: Record<SaleCycle, string> = {
  monthly: "Premium mensal",
  annual: "Premium anual",
  single: "Premium (Pix avulso)",
  unknown: "Premium",
};

/** Where to read the money on each rail (the console table of CLAUDE.md). */
const RAIL_CONSOLE: Record<SaleRail, { url: string; label: string }> = {
  play: {
    url: "https://play.google.com/console/u/0/developers/5188946194088545235/paymentssettings",
    label: "Play Console — perfil de pagamentos",
  },
  asaas: { url: "https://www.asaas.com", label: "Asaas" },
};

export function formatAmount(cents: number | null, currency: string | null): string | null {
  if (cents === null) return null;
  const code = currency ?? "BRL";
  try {
    return new Intl.NumberFormat("pt-BR", { style: "currency", currency: code }).format(cents / 100)
      .replace(/ /g, " ");
  } catch {
    return `${code} ${(cents / 100).toFixed(2)}`;
  }
}

/** "25/11/2026 às 14:03" in Brasília. */
export function formatBrasilia(at: Date): string {
  const parts = new Intl.DateTimeFormat("pt-BR", {
    timeZone: "America/Sao_Paulo",
    day: "2-digit",
    month: "2-digit",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
  }).formatToParts(at);
  const get = (t: string) => parts.find((p) => p.type === t)?.value ?? "";
  return `${get("day")}/${get("month")}/${get("year")} às ${get("hour")}:${get("minute")}`;
}

export function saleSubject(a: SaleAlert, envPrefix: string): string {
  const amount = formatAmount(a.amountCents, a.currency);
  const test = a.isTest ? "[teste] " : "";
  return `${envPrefix}${test}${KIND_TITLE[a.kind]}: ${CYCLE_LABEL[a.cycle]} · ${RAIL_LABEL[a.rail]}` +
    (amount ? ` · ${amount}` : "");
}

export function saleHtml(a: SaleAlert): string {
  const at = a.at ?? new Date();
  const amount = formatAmount(a.amountCents, a.currency);
  const rows = [
    `Acontecimento: <strong>${KIND_TITLE[a.kind]}</strong>`,
    `Canal: <strong>${RAIL_LABEL[a.rail]}</strong>`,
    `Plano: <strong>${CYCLE_LABEL[a.cycle]}</strong>`,
    ...(amount ? [`Valor: <strong>${amount}</strong>`] : []),
    `Quando: ${formatBrasilia(at)} (horário de Brasília)`,
    ...(a.isTest ? ["Compra de teste: nenhum dinheiro foi cobrado."] : []),
  ];
  const where = RAIL_CONSOLE[a.rail];
  return emailDocument({
    htmlLang: "pt-BR",
    title: KIND_TITLE[a.kind],
    body: `${heading(KIND_TITLE[a.kind], KIND_TONE[a.kind])}
      ${paragraph(KIND_SENTENCE[a.kind])}
      ${list(rows)}
      ${paragraph(smallLink(where.url, where.label))}
      ${small("Só o acontecimento: nenhum nome, e-mail, identificador de família ou de pedido.", true)}`,
    footer: [
      "Enviado ao operador do Entrelares a cada evento de cobrança.",
      `Para parar: chave ${SWITCH_KEY} no console de operação.`,
    ],
  });
}

// ── Claim and send ───────────────────────────────────────────────────────────

/** Never throws. Call it only after the event was applied. */
export async function notifySale(admin: SupabaseClient, a: SaleAlert): Promise<void> {
  const tag = `${a.rail}/${a.kind}${a.isTest ? "/test" : ""}`;
  try {
    const { data: claimed, error } = await admin.rpc("claim_sale_alert", {
      p_sale_key: a.saleKey,
      p_rail: a.rail,
      p_kind: a.kind,
      p_cycle: a.cycle,
      p_amount_cents: a.amountCents,
      p_currency: a.currency,
      p_is_test: a.isTest,
    });
    if (error) {
      console.warn(`[sale-alert] ${tag} claim failed — ${error.message}`);
      return;
    }
    if (claimed !== true) return; // switched off, or already told

    const envName = Deno.env.get("APP_ENVIRONMENT") ?? "Production";
    const envPrefix = envName.toLowerCase() === "production" ? "" : "[Dev] ";
    const to = Deno.env.get("OPERATOR_INBOX") ?? OPERATOR_INBOX;

    if (!isTestRecipient(to)) {
      const resendKey = Deno.env.get("RESEND_API_KEY");
      if (!resendKey) throw new Error("RESEND_API_KEY secret is not configured.");
      const fromEmail = Deno.env.get("RESEND_FROM_EMAIL") ?? "noreply@entrelares.app";
      const fromName = Deno.env.get("RESEND_FROM_NAME") ?? "Entrelares";
      const res = await fetch(RESEND_API_URL, {
        method: "POST",
        headers: { "Authorization": `Bearer ${resendKey}`, "Content-Type": "application/json" },
        body: JSON.stringify({
          from: `${fromName} <${fromEmail}>`,
          to: [to],
          subject: saleSubject(a, envPrefix),
          html: saleHtml(a),
        }),
        signal: AbortSignal.timeout(SEND_TIMEOUT_MS),
      });
      if (!res.ok) throw new Error(`Resend error ${res.status}: ${await res.text()}`);
    }

    await admin.from("sale_alerts")
      .update({ sent_at: new Date().toISOString() })
      .eq("sale_key", a.saleKey);
    // S-13: the kind and the rail, never an address or a key.
    console.log(`[sale-alert] ${tag} sent`);
  } catch (err) {
    console.warn(`[sale-alert] ${tag} not sent — ${err instanceof Error ? err.message : err}`);
  }
}
