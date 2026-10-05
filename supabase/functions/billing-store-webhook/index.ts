// T-48 (redesigned, T-53 lote 5) — Real-Time Developer Notifications (RTDN).
//
// Google publishes every subscription lifecycle change to a Pub/Sub topic, and
// Pub/Sub pushes it here. This is the store rail's twin of `billing-webhook`:
// it authenticates the call, records the message in the SAME `billing_events`
// ledger (idempotency + audit) and applies the effect through the SAME
// `set_family_plan` RPC. Everything that happens to a store subscription
// AFTER the purchase — renewal, cancellation, expiry, refund, revocation,
// pause — arrives here, because the app is not running when it happens.
//
// Notification type → effect (the ones that move money or access):
//   1 RECOVERED · 2 RENEWED · 4 PURCHASED · 7 RESTARTED
//       → active, period end = Play's expiry, plan = premium.
//   3 CANCELED
//       → canceled (no further charges). Premium survives until the period
//         end, exactly like an Asaas cancellation: the grace cron lapses it.
//   12 REVOKED · 13 EXPIRED
//       → canceled and plan = free NOW (Google took the money back, or the
//         paid time is over).
//   5 ON_HOLD · 6 IN_GRACE_PERIOD · 10 PAUSED
//       → overdue (stamped), which is what the existing grace machinery,
//         the B-3 warning and the UI already understand.
//   anything else → recorded, acknowledged, no effect.
//
// Security:
//   · verify_jwt = false: Pub/Sub cannot send a Supabase JWT. The SHARED TOKEN
//     is the real authentication — configure the push subscription's endpoint
//     with `?token=<PLAY_RTDN_TOKEN>` (Pub/Sub allows no custom headers).
//   · Never trust the message body for entitlement: it says WHICH purchase
//     changed, and the Play Developer API is then asked what the truth is.
//   · Always 200 on content we do not care about — a non-2xx makes Pub/Sub
//     retry the same message for days and delays every OTHER family's events.

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { secretKey } from "../_shared/keys.ts";
import { fetchStorePurchase, priceCents, purchaseExpiry } from "../_shared/play.ts";

const ACTIVATING = new Set([1, 2, 4, 7]);
const ENDING_NOW = new Set([12, 13]);
const DUNNING = new Set([5, 6, 10]);
const CANCELED = 3;

function jsonResponse(body: unknown, status = 200): Response {
	return new Response(JSON.stringify(body), {
		status,
		headers: { "Content-Type": "application/json" },
	});
}

interface PubSubPush {
	message?: { data?: string; messageId?: string; message_id?: string };
}

interface DeveloperNotification {
	packageName?: string;
	eventTimeMillis?: string;
	subscriptionNotification?: {
		notificationType?: number;
		purchaseToken?: string;
		subscriptionId?: string;
	};
	testNotification?: { version?: string };
}

serve(async (req) => {
	if (req.method !== "POST") return jsonResponse({ ok: true, ignored: true });

	// ── Authentication: the shared token on the query string ────────────────
	const expected = Deno.env.get("PLAY_RTDN_TOKEN");
	const presented = new URL(req.url).searchParams.get("token");
	if (!expected || presented !== expected) {
		return jsonResponse({ error: "unauthorized" }, 401);
	}

	try {
		const push = await req.json().catch(() => ({})) as PubSubPush;
		const encoded = push.message?.data;
		const messageId = push.message?.messageId ?? push.message?.message_id;
		if (!encoded || !messageId) return jsonResponse({ ok: true, ignored: true });

		const notification = JSON.parse(atob(encoded)) as DeveloperNotification;

		// Google sends one of these when the topic is wired up. Acknowledging
		// it is the whole point of the test — do not treat it as an event.
		if (notification.testNotification) {
			return jsonResponse({ ok: true, test: true });
		}

		const subscriptionNotification = notification.subscriptionNotification;
		const purchaseToken = subscriptionNotification?.purchaseToken;
		const productId = subscriptionNotification?.subscriptionId;
		const type = subscriptionNotification?.notificationType ?? 0;
		if (!purchaseToken || !productId) {
			return jsonResponse({ ok: true, ignored: true });
		}

		const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
		const admin = createClient(supabaseUrl, secretKey(), {
			auth: { persistSession: false },
		});

		// The row this message is about. A token we never stored is a purchase
		// made against another install/environment — recorded, ignored.
		const { data: subscription } = await admin
			.from("subscriptions")
			.select("id, family_id, cycle")
			.eq("store_purchase_token", purchaseToken)
			.maybeSingle();

		// ── Idempotency gate, shared with the Asaas rail ─────────────────────
		const { data: ledger, error: ledgerError } = await admin
			.from("billing_events")
			.upsert(
				{
					event_id: `play-rtdn:${messageId}`,
					event_type: `PLAY_RTDN_${type}`,
					subscription_id: subscription?.id ?? null,
					family_id: subscription?.family_id ?? null,
					payload: notification,
				},
				{ onConflict: "event_id", ignoreDuplicates: true },
			)
			.select("id");
		if (ledgerError) throw ledgerError;
		if (!ledger || ledger.length === 0) {
			return jsonResponse({ ok: true, duplicate: true });
		}
		if (!subscription) return jsonResponse({ ok: true, ignored: true });

		const nowUtc = new Date().toISOString();

		if (ACTIVATING.has(type)) {
			// Ask Google what the truth is rather than trusting the message —
			// the notification says WHICH purchase changed, not until when it
			// now pays.
			const packageName = notification.packageName ??
				Deno.env.get("PLAY_PACKAGE_NAME") ?? "com.entrelares.app";
			const purchase = await fetchStorePurchase(packageName, productId, purchaseToken);
			if (!purchase) return jsonResponse({ ok: true, ignored: true });

			// F-107: the ledger row keeps the purchase it was answered with —
			// the price and the Google order id are what `get_billing_history`
			// shows, and what dedupes it against the verification of the same
			// period.
			const { error: ledgerUpdateError } = await admin
				.from("billing_events")
				.update({ payload: { ...notification, purchase } })
				.eq("event_id", `play-rtdn:${messageId}`);
			if (ledgerUpdateError) throw ledgerUpdateError;

			const { error } = await admin
				.from("subscriptions")
				.update({
					status: "active",
					current_period_end: purchaseExpiry(purchase),
					overdue_since: null,
					canceled_at: null,
					price_cents: priceCents(purchase) ?? undefined,
					store_product_id: productId,
					updated_at: nowUtc,
				})
				.eq("id", subscription.id);
			if (error) throw error;

			const { error: planError } = await admin.rpc("set_family_plan", {
				p_family_id: subscription.family_id,
				p_plan: "premium",
			});
			if (planError) throw planError;
			return jsonResponse({ ok: true, applied: "active" });
		}

		if (type === CANCELED) {
			// No further charges; the paid period is HONORED. Same shape the
			// web rail's cancellation leaves behind, so the offer copy, the
			// F-42 machinery and the grace cron all keep working unchanged.
			const { error } = await admin
				.from("subscriptions")
				.update({ status: "canceled", canceled_at: nowUtc, updated_at: nowUtc })
				.eq("id", subscription.id);
			if (error) throw error;
			return jsonResponse({ ok: true, applied: "canceled" });
		}

		if (ENDING_NOW.has(type)) {
			// REVOKED means Google refunded and took access back; EXPIRED means
			// the paid time is genuinely over. Both end Premium NOW — and the
			// data is never deleted (backlog invariant), only the plan flips.
			const { error } = await admin
				.from("subscriptions")
				.update({
					status: "canceled",
					canceled_at: nowUtc,
					current_period_end: nowUtc,
					updated_at: nowUtc,
				})
				.eq("id", subscription.id);
			if (error) throw error;

			const { error: planError } = await admin.rpc("set_family_plan", {
				p_family_id: subscription.family_id,
				p_plan: "free",
			});
			if (planError) throw planError;
			return jsonResponse({ ok: true, applied: "free" });
		}

		if (DUNNING.has(type)) {
			// Play is retrying the charge (or the user paused). The plan is NOT
			// touched here: the existing grace cron owns the downgrade, exactly
			// as it does for an Asaas PAYMENT_OVERDUE.
			const { error } = await admin
				.from("subscriptions")
				.update({ status: "overdue", overdue_since: nowUtc, updated_at: nowUtc })
				.eq("id", subscription.id);
			if (error) throw error;
			return jsonResponse({ ok: true, applied: "overdue" });
		}

		return jsonResponse({ ok: true, recorded: true });
	} catch (error) {
		console.error("billing-store-webhook", error);
		// Pub/Sub retries a 500 with backoff, which is what we want for a
		// transient failure — the ledger row makes the retry idempotent.
		return jsonResponse({ error: "internal" }, 500);
	}
});
