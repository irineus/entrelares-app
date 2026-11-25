// T-48 (redesigned, T-53 lote 5) — the store rail's entitlement path.
//
// The Flutter app sells a subscription through Play Billing and hands the
// resulting PURCHASE TOKEN here. This function is the only thing that turns
// that token into Premium: it asks the Play Developer API whether the purchase
// is real and until when it pays, then applies the effect through the SAME
// `set_family_plan` RPC and the SAME `billing_events` ledger the Asaas webhook
// uses. Nothing about entitlement is re-implemented — the client's claim never
// becomes a grant on the client's word.
//
// Why a function and not only the RTDN webhook: the webhook is asynchronous
// and Google delivers it when it feels like it. A payer who just bought inside
// the app expects Premium NOW, and this is the round trip that gives it to
// them. The webhook then owns everything that happens afterwards (renewal,
// cancellation, refund, grace) — both write the same row, keyed by the same
// idempotency ledger, so they cannot double-apply.
//
// Security:
//   · Runs with verify_jwt = false (S-16: the platform gate only understands
//     legacy keys) and authorizes itself — a valid USER session is required,
//     and the family is resolved from that user's profile with the secret key.
//     A caller cannot name a family; it gets its own.
//   · One purchase funds ONE family. The unique index on
//     `subscriptions.store_purchase_token` is what enforces it: a receipt
//     replayed by a second family is refused by the DATABASE, not by a check
//     here that could drift.
//   · The master switch `billing.store_enabled` must be on. While it is off
//     the client shows the neutral note and never calls this — but a build
//     that did would be refused here too.

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { secretKey } from "../_shared/keys.ts";
import {
	fetchStorePurchase,
	isPurchaseLive,
	priceCents,
	purchaseExpiry,
} from "../_shared/play.ts";
import {
	isPaidPurchase,
	isTestPurchase,
	notifySale,
	playAmountCents,
	playCurrency,
	playCycle,
	playOrderKind,
} from "../_shared/sale_alert.ts";

/** The Play products this app sells, and the cycle each one means. */
const PRODUCT_CYCLES: Record<string, string> = {
	premium_monthly: "monthly",
	premium_annual: "annual",
};

function jsonResponse(body: unknown, status = 200): Response {
	return new Response(JSON.stringify(body), {
		status,
		headers: { "Content-Type": "application/json" },
	});
}

/** Refusals are read by the PAYER, so they are PT-BR and say what to do. */
function refuse(message: string, status = 400): Response {
	return jsonResponse({ error: message }, status);
}

serve(async (req) => {
	if (req.method !== "POST") return refuse("Método não suportado.", 405);

	try {
		const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
		const admin = createClient(supabaseUrl, secretKey(), {
			auth: { persistSession: false },
		});

		// ── Who is calling ───────────────────────────────────────────────────
		const jwt = (req.headers.get("Authorization") ?? "")
			.replace(/^Bearer\s+/i, "").trim();
		if (!jwt) return refuse("Sessão expirada. Entre novamente.", 401);

		const { data: userData, error: userError } = await admin.auth.getUser(jwt);
		if (userError || !userData?.user) {
			return refuse("Sessão expirada. Entre novamente.", 401);
		}

		const { data: profile, error: profileError } = await admin
			.from("profiles")
			.select("family_id, is_admin")
			.eq("user_id", userData.user.id)
			.maybeSingle();
		if (profileError) throw profileError;
		if (!profile?.family_id) {
			return refuse("Não encontramos sua família. Entre novamente.", 403);
		}

		// ── Is the store rail even on ────────────────────────────────────────
		const { data: setting } = await admin
			.from("app_settings")
			.select("value")
			.eq("key", "billing.store_enabled")
			.maybeSingle();
		if (setting?.value !== "true") {
			return refuse(
				"A compra pela loja ainda não está disponível. Se você foi cobrado, " +
				"escreva para suporte@entrelares.app — nada fica perdido.",
				409,
			);
		}

		// ── What the client is claiming ──────────────────────────────────────
		const body = await req.json().catch(() => ({})) as {
			product_id?: string;
			purchase_token?: string;
		};
		const productId = (body.product_id ?? "").trim();
		const purchaseToken = (body.purchase_token ?? "").trim();
		const cycle = PRODUCT_CYCLES[productId];
		if (!cycle || !purchaseToken) {
			return refuse("Compra inválida. Tente novamente pela loja.", 400);
		}

		// ── What GOOGLE says about it ────────────────────────────────────────
		const packageName = Deno.env.get("PLAY_PACKAGE_NAME") ?? "com.entrelares.app";
		const purchase = await fetchStorePurchase(packageName, productId, purchaseToken);
		if (!purchase) {
			// Google does not know this token: forged, or already superseded by
			// an upgrade. Either way there is nothing to grant.
			return refuse("A loja não reconheceu esta compra.", 404);
		}
		if (!isPurchaseLive(purchase)) {
			return refuse(
				"A loja ainda não confirmou o pagamento. Assim que confirmar, o " +
				"Premium é liberado automaticamente.",
				409,
			);
		}

		const periodEnd = purchaseExpiry(purchase);
		const nowUtc = new Date().toISOString();

		// ── The ledger first: it is the idempotency gate for BOTH rails ──────
		// Keyed by token AND expiry so re-verifying the same period is a no-op
		// while a RENEWAL (new expiry, same token) still writes its own row.
		const eventId = `play:${purchaseToken}:${purchase.expiryTimeMillis ?? "0"}`;
		const { data: ledger, error: ledgerError } = await admin
			.from("billing_events")
			.upsert(
				{
					event_id: eventId,
					event_type: "PLAY_PURCHASE_VERIFIED",
					family_id: profile.family_id,
					payload: { product_id: productId, purchase, source: "verify" },
				},
				{ onConflict: "event_id", ignoreDuplicates: true },
			)
			.select("id");
		if (ledgerError) throw ledgerError;
		const alreadyApplied = !ledger || ledger.length === 0;

		// ── The row. One per family; the store rail owns it while it pays ────
		const { data: existing } = await admin
			.from("subscriptions")
			.select("id, family_id")
			.eq("family_id", profile.family_id)
			.maybeSingle();

		const row = {
			family_id: profile.family_id,
			gateway: "play",
			status: "active",
			cycle,
			// Play reports the price it actually charged, in the buyer's
			// currency — the app_settings prices rule the web rail only.
			price_cents: priceCents(purchase) ?? 1,
			current_period_end: periodEnd,
			overdue_since: null,
			canceled_at: null,
			billing_type: "PLAY",
			single_charge: false,
			store_purchase_token: purchaseToken,
			store_product_id: productId,
			updated_at: nowUtc,
		};

		const { error: writeError } = existing
			? await admin.from("subscriptions").update(row).eq("id", existing.id)
			: await admin.from("subscriptions").insert(row);

		if (writeError) {
			// 23505 on the token index: another family already holds this
			// purchase. The DATABASE is what refuses it, and the payer needs a
			// sentence they can act on.
			if ((writeError as { code?: string }).code === "23505") {
				return refuse(
					"Esta compra já está vinculada a outra família. Fale com o " +
					"suporte para transferi-la: suporte@entrelares.app",
					409,
				);
			}
			throw writeError;
		}

		// ── Entitlement, through the SAME door as every other rail ───────────
		const { error: planError } = await admin.rpc("set_family_plan", {
			p_family_id: profile.family_id,
			p_plan: "premium",
		});
		if (planError) throw planError;

		// T-111: the app usually reaches us before the RTDN does, so a first
		// purchase is most often told from HERE. Same key as the RTDN (the
		// Google order id), so whichever path comes second sends nothing.
		if (isPaidPurchase(purchase)) {
			await notifySale(admin, {
				saleKey: purchase.orderId ? `play:order:${purchase.orderId}` : eventId,
				rail: "play",
				kind: playOrderKind(purchase.orderId),
				cycle: playCycle(productId),
				amountCents: playAmountCents(purchase),
				currency: playCurrency(purchase),
				isTest: isTestPurchase(purchase),
			});
		}

		return jsonResponse({
			ok: true,
			duplicate: alreadyApplied,
			current_period_end: periodEnd,
		});
	} catch (error) {
		console.error("billing-store-verify", error);
		// A 500 is honest here: the client keeps the purchase, Play will
		// redeliver through RTDN, and the family is not told a lie.
		return refuse(
			"Não foi possível confirmar a compra agora. Ela não foi perdida — " +
			"tente novamente em instantes.",
			500,
		);
	}
});
