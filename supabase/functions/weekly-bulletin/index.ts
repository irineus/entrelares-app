// T-99 — the weekly sales bulletin, e-mailed to the OPERATOR.
//
// WHY. The acquisition chain of October (F-77, F-78, F-80) needs a number to
// move, and every reading so far was hand-written SQL in production. Once a
// week this function reads ONE aggregate (`admin_weekly_sales_bulletin`, the
// week that just ended vs the one before, a 4-week trend and a snapshot) and
// e-mails it to the operator's address. It is about the business, never sent
// to a user — outside F-59's scope.
//
// WHAT LEAVES. Counts, dates and closed enums only (F-69's rule, owner
// 02/10/2026): no family or member name, no e-mail, no note, no family id. The
// aggregate is held to that by the DB gate (closed key list + a free-text
// marker), and this file only formats numbers into the shared layout (U-26) —
// there is no user data to escape. The footer names the three readings no API
// gives us (Play acquisition, Search Console, Umami), with their direct URLs.
//
// WHEN. pg_cron `weekly-bulletin`, Monday 12:00 UTC = 09:00 in Brasília, with
// the Vault secret key on `apikey` — so verify_jwt is off and the key is checked
// here (S-16), the F-70 shape. Body (all optional):
//   · `week_start` "YYYY-MM-DD" — another week (normalised to its Monday);
//   · `dry_run` true — build and RETURN the subject and HTML, send nothing and
//     stamp nothing. The DB gate uses it: the gate's dummy Resend key and the
//     real operator inbox must never meet.
//
// ONCE PER WEEK. The week is claimed in `weekly_bulletin_sends` before the
// send and released if Resend refuses, so a re-run of the same week sends
// nothing. The kill switch `ops.weekly_bulletin.enabled` (operator console)
// makes a real run exit quietly; a dry run ignores it.

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { secretKey } from "../_shared/keys.ts";
import { isSecretKeyCaller } from "../_shared/auth.ts";
import { isTestRecipient } from "../_shared/mail.ts";
import { emailDocument, heading, list, paragraph, small, smallLink } from "../_shared/email_layout.ts";

const RESEND_API_URL = "https://api.resend.com/emails";
const OPERATOR_INBOX = "contato@entrelares.app";
const SWITCH_KEY = "ops.weekly_bulletin.enabled";

/** The three readings only a person can take — copied from CLAUDE.md's console table. */
const MANUAL_READINGS: Array<{ label: string; url: string; what: string }> = [
  {
    label: "Play Console — ficha da loja e aquisição",
    url: "https://play.google.com/console/u/0/developers/5188946194088545235/app/4976020657794164634/store-listings?metric=METRIC_ACQUISITION",
    what: "visitas à ficha e instalações da semana",
  },
  {
    label: "Google Search Console — desempenho",
    url: "https://search.google.com/search-console/performance/search-analytics?resource_id=sc-domain%3Aentrelares.app",
    what: "cliques e impressões da busca",
  },
  {
    label: "Umami — app (web.entrelares.app)",
    url: "https://cloud.umami.is/analytics/us/websites/6fdd6c5a-4bce-449f-8188-3b7399a859d8",
    what: "visitantes e eventos do app na web",
  },
];

// ── The aggregate's shape (supabase/migrations/20261002190000_t99_weekly_bulletin.sql)

interface Week {
  week_start: string;
  families_created: number;
  first_channel: { android: number; web: number; web_installed: number; none: number };
  planned_within_7d: number;
  invitations_sent: number;
  invitations_accepted: number;
  active_families: number;
  conversions: {
    total: number;
    during_trial: number;
    by_rail: { asaas: number; play: number };
    by_cycle: { monthly: number; annual: number; single: number; unknown: number };
  };
  cancellations: number;
  overdue_started: number;
  trial_reminders: { d7: number; d1: number; ended: number };
  unplanned_nudges: number;
}

interface TrendPoint {
  week_start: string;
  families_created: number;
  active_families: number;
  invitations_sent: number;
  conversions_total: number;
}

interface Bulletin {
  report_version: number;
  generated_at: string;
  week_start: string;
  week_end: string;
  this_week: Week;
  previous_week: Week;
  trend: TrendPoint[];
  snapshot: {
    families_total: number;
    paying_families: number;
    trials_ending_7d: number;
    dunning: number;
  };
  referrals: null;
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

/** "2026-09-28" → "28/09". */
function ddmm(iso: string): string {
  const [, m, d] = iso.split("-");
  return `${d}/${m}`;
}

/** "2026-09-28" → "28/09/2026". */
function ddmmyyyy(iso: string): string {
  const [y, m, d] = iso.split("-");
  return `${d}/${m}/${y}`;
}

/** "<strong>N</strong> (semana anterior: M)". */
function vs(now: number, before: number): string {
  return `<strong>${now}</strong> (semana anterior: ${before})`;
}

export function subjectOf(b: Bulletin, envPrefix: string): string {
  return `${envPrefix}Boletim semanal — semana de ${ddmm(b.week_start)} a ${ddmm(b.week_end)}`;
}

export function htmlOf(b: Bulletin): string {
  const w = b.this_week;
  const p = b.previous_week;
  const s = b.snapshot;

  const acquisition = list([
    `Famílias criadas: ${vs(w.families_created, p.families_created)}`,
    `Primeiro canal dessas famílias: Android ${w.first_channel.android} · web ${w.first_channel.web}` +
      ` · web instalado ${w.first_channel.web_installed} · sem uso registrado ${w.first_channel.none}`,
    `Planejaram nos primeiros 7 dias: <strong>${w.planned_within_7d}</strong> de ${w.families_created}` +
      ` (até agora; semana anterior: ${p.planned_within_7d} de ${p.families_created})`,
    `Convites enviados: ${vs(w.invitations_sent, p.invitations_sent)}`,
    `Convites aceitos: ${vs(w.invitations_accepted, p.invitations_accepted)}`,
  ]);

  const usage = list([
    `Famílias ativas (algum membro usou o app na semana): ${vs(w.active_families, p.active_families)}`,
    `Famílias no total: <strong>${s.families_total}</strong> · pagantes agora: <strong>${s.paying_families}</strong>`,
  ]);

  const sales = list([
    `Avaliações Premium que terminam nos próximos 7 dias: <strong>${s.trials_ending_7d}</strong>`,
    `Primeiro pagamento (avaliação → pago): ${vs(w.conversions.total, p.conversions.total)}` +
      `; ainda durante a avaliação: ${w.conversions.during_trial}`,
    `Por trilho: web (Asaas) ${w.conversions.by_rail.asaas} · Play ${w.conversions.by_rail.play}`,
    `Por ciclo: mensal ${w.conversions.by_cycle.monthly} · anual ${w.conversions.by_cycle.annual}` +
      ` · Pix avulso ${w.conversions.by_cycle.single} · sem ciclo ${w.conversions.by_cycle.unknown}`,
    `Cancelamentos: ${vs(w.cancellations, p.cancellations)}`,
    `Entraram em atraso: ${vs(w.overdue_started, p.overdue_started)} · em atraso agora: <strong>${s.dunning}</strong>`,
  ]);

  const nudges = list([
    `Fim da avaliação (F-77): 7 dias antes ${w.trial_reminders.d7} · 1 dia antes ${w.trial_reminders.d1}` +
      ` · depois do fim ${w.trial_reminders.ended} (semana anterior: ${
        p.trial_reminders.d7 + p.trial_reminders.d1 + p.trial_reminders.ended
      } no total)`,
    `"Falta planejar o primeiro mês" (F-78): ${vs(w.unplanned_nudges, p.unplanned_nudges)}`,
    // F-80 fills `referrals`; until then the line says so instead of a zero.
    b.referrals === null
      ? "Indicações: ainda não medidas (chegam com o F-80)."
      : `Indicações: <strong>${Number(b.referrals)}</strong>`,
  ]);

  const trend = list(b.trend.map((t) =>
    `Semana de ${ddmm(t.week_start)}: criadas ${t.families_created} · ativas ${t.active_families}` +
    ` · convites ${t.invitations_sent} · primeiros pagamentos ${t.conversions_total}`
  ));

  const readings = list(MANUAL_READINGS.map((r) => `${smallLink(r.url, r.label)} — ${r.what}`));

  return emailDocument({
    htmlLang: "pt-BR",
    title: "Boletim semanal",
    body: `${heading("Boletim semanal")}
      ${paragraph(
        `Semana de segunda ${ddmmyyyy(b.week_start)} a domingo ${ddmmyyyy(b.week_end)}, no horário de Brasília,` +
          " comparada à semana anterior. Só contagens: nenhum nome, e-mail ou identificador de família.",
      )}
      ${paragraph("<strong>Aquisição</strong>")}
      ${acquisition}
      ${paragraph("<strong>Uso</strong>")}
      ${usage}
      ${paragraph("<strong>Vendas</strong>")}
      ${sales}
      ${paragraph("<strong>Avisos automáticos enviados</strong>")}
      ${nudges}
      ${paragraph("<strong>Últimas 4 semanas</strong>")}
      ${trend}
      ${paragraph("<strong>Leituras manuais</strong> (sem API; abrir e anotar)")}
      ${readings}
      ${small("As famílias ativas contam quem abriu o app em qualquer canal. O primeiro pagamento é o primeiro" +
        " registro pago da família no histórico de cobrança, em qualquer trilho.", true)}`,
    footer: [
      "Enviado toda segunda-feira às 09:00 ao operador do Entrelares.",
      `Para parar: chave ${SWITCH_KEY} no console de operação.`,
    ],
  });
}

serve(async (req: Request) => {
  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceKey = secretKey();
    if (!isSecretKeyCaller(req, serviceKey)) {
      console.warn("[weekly-bulletin] refused — caller did not present the secret key");
      return json({ error: "Não autorizado." }, 401);
    }
    const admin = createClient(supabaseUrl, serviceKey);

    let body: { dry_run?: unknown; week_start?: unknown } = {};
    try {
      body = (await req.json()) ?? {};
    } catch {
      body = {};
    }
    const dryRun = body.dry_run === true;
    const weekStart = typeof body.week_start === "string" && /^\d{4}-\d{2}-\d{2}$/.test(body.week_start)
      ? body.week_start
      : null;

    if (!dryRun) {
      const { data: enabled, error } = await admin.rpc("setting_bool", {
        p_key: SWITCH_KEY,
        p_default: true,
      });
      if (error) throw new Error(`setting_bool failed: ${error.message}`);
      if (enabled === false) {
        console.log("[weekly-bulletin] switched off — nothing sent");
        return json({ skipped: "disabled" });
      }
    }

    const { data, error } = await admin.rpc("admin_weekly_sales_bulletin", { p_week_start: weekStart });
    if (error) {
      console.error(`[weekly-bulletin] aggregate failed — ${error.message}`);
      return json({ error: error.message }, 500);
    }
    const bulletin = data as Bulletin;

    const envName = Deno.env.get("APP_ENVIRONMENT") ?? "Production";
    const envPrefix = envName.toLowerCase() === "production" ? "" : "[Dev] ";
    const subject = subjectOf(bulletin, envPrefix);
    const html = htmlOf(bulletin);

    if (dryRun) return json({ dry_run: true, week_start: bulletin.week_start, subject, html });

    // ── Once per week: claim, send, release on failure.
    const { error: claimError } = await admin
      .from("weekly_bulletin_sends")
      .insert({ week_start: bulletin.week_start });
    if (claimError) {
      if (claimError.code === "23505") {
        console.log(`[weekly-bulletin] week ${bulletin.week_start} already sent`);
        return json({ skipped: "already_sent", week_start: bulletin.week_start });
      }
      throw new Error(`claim failed: ${claimError.message}`);
    }

    const to = Deno.env.get("OPERATOR_INBOX") ?? OPERATOR_INBOX;
    if (isTestRecipient(to)) {
      console.log(`[weekly-bulletin] week ${bulletin.week_start} test recipient — Resend call suppressed`);
      return json({ sent: true, week_start: bulletin.week_start });
    }

    try {
      const resendKey = Deno.env.get("RESEND_API_KEY");
      if (!resendKey) throw new Error("RESEND_API_KEY secret is not configured.");
      const fromEmail = Deno.env.get("RESEND_FROM_EMAIL") ?? "noreply@entrelares.app";
      const fromName = Deno.env.get("RESEND_FROM_NAME") ?? "Entrelares";
      const res = await fetch(RESEND_API_URL, {
        method: "POST",
        headers: { "Authorization": `Bearer ${resendKey}`, "Content-Type": "application/json" },
        body: JSON.stringify({ from: `${fromName} <${fromEmail}>`, to: [to], subject, html }),
      });
      if (!res.ok) throw new Error(`Resend error ${res.status}: ${await res.text()}`);
    } catch (err) {
      await admin.from("weekly_bulletin_sends").delete().eq("week_start", bulletin.week_start);
      console.error(`[weekly-bulletin] send failed — ${err instanceof Error ? err.message : err}`);
      return json({ error: "send_failed" }, 502);
    }

    // S-13: the week and a count, never an address.
    console.log(
      `[weekly-bulletin] week ${bulletin.week_start} sent (families_created=${bulletin.this_week.families_created})`,
    );
    return json({ sent: true, week_start: bulletin.week_start });
  } catch (err) {
    console.error("[weekly-bulletin] unhandled error:", err);
    return json({ error: String(err) }, 500);
  }
});
