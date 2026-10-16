// T-48 — the Google Play Developer API client the store rail needs.
//
// Two things live here because both store functions need them and neither may
// disagree with the other:
//   1. an OAuth access token minted from the service account (Google gives no
//      long-lived key for this API — you sign a JWT with the account's private
//      key and exchange it), and
//   2. reading a subscription purchase, which is the ONLY source of truth for
//      "is this purchase real, and until when does it pay".
//
// The client never decides entitlement; this file is what lets the SERVER
// decide it from Google's own answer instead of from a token the app sent.

/** The service account JSON, as pasted into the PLAY_SERVICE_ACCOUNT secret. */
interface ServiceAccount {
	client_email: string;
	private_key: string;
}

/** What Play answers about a subscription purchase (the fields we act on). */
export interface StorePurchase {
	/** Milliseconds since epoch, as a string — Google's own shape. */
	expiryTimeMillis?: string;
	startTimeMillis?: string;
	/** Google's codes: 0 = payment pending, 1 = payment received, 2 = free trial,
	 * 3 = pending deferred upgrade/downgrade. (F-80's "first paid payment"
	 * counts a verification only at 1 — `isPurchaseLive` below already reads 0
	 * as pending.) */
	paymentState?: number;
	/** 1 = canceled by user, 0 = ... see the API docs; absent = not canceled. */
	cancelReason?: number;
	/** Set when the purchase supersedes another one (upgrade/downgrade/resub). */
	linkedPurchaseToken?: string;
	priceAmountMicros?: string;
	priceCurrencyCode?: string;
	acknowledgementState?: number;
	orderId?: string;
}

function serviceAccount(): ServiceAccount {
	const raw = Deno.env.get("PLAY_SERVICE_ACCOUNT");
	if (!raw) {
		throw new Error(
			"PLAY_SERVICE_ACCOUNT is not set — the store rail cannot verify a " +
			"purchase without the Play Developer API service account. Create it in " +
			"Google Cloud, grant it access in the Play Console, and set the JSON as " +
			"a function secret (see supabase/README.md § Play Billing).",
		);
	}
	const parsed = JSON.parse(raw) as ServiceAccount;
	if (!parsed.client_email || !parsed.private_key) {
		throw new Error("PLAY_SERVICE_ACCOUNT is missing client_email/private_key.");
	}
	return parsed;
}

function base64Url(bytes: Uint8Array): string {
	return btoa(String.fromCharCode(...bytes))
		.replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function encodeSegment(value: unknown): string {
	return base64Url(new TextEncoder().encode(JSON.stringify(value)));
}

/** PEM (PKCS#8) → a CryptoKey Web Crypto will sign RS256 with. */
async function importPrivateKey(pem: string): Promise<CryptoKey> {
	// The secret travels as JSON, so the newlines arrive escaped.
	const normalized = pem.replace(/\\n/g, "\n");
	const body = normalized
		.replace(/-----BEGIN PRIVATE KEY-----/, "")
		.replace(/-----END PRIVATE KEY-----/, "")
		.replace(/\s+/g, "");
	const der = Uint8Array.from(atob(body), (c) => c.charCodeAt(0));
	return await crypto.subtle.importKey(
		"pkcs8",
		der,
		{ name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
		false,
		["sign"],
	);
}

/** Cached for the life of the isolate — the token is good for an hour. */
let cachedToken: { value: string; expiresAt: number } | null = null;

/** An OAuth access token for the Android Publisher scope. */
export async function playAccessToken(): Promise<string> {
	const now = Math.floor(Date.now() / 1000);
	// 60 s of slack: a token that expires mid-request is a 401 we cannot retry
	// usefully, and minting a new one is cheap.
	if (cachedToken && cachedToken.expiresAt - 60 > now) return cachedToken.value;

	const account = serviceAccount();
	const claims = {
		iss: account.client_email,
		scope: "https://www.googleapis.com/auth/androidpublisher",
		aud: "https://oauth2.googleapis.com/token",
		iat: now,
		exp: now + 3600,
	};
	const unsigned = `${encodeSegment({ alg: "RS256", typ: "JWT" })}.${encodeSegment(claims)}`;
	const signature = await crypto.subtle.sign(
		"RSASSA-PKCS1-v1_5",
		await importPrivateKey(account.private_key),
		new TextEncoder().encode(unsigned),
	);
	const assertion = `${unsigned}.${base64Url(new Uint8Array(signature))}`;

	const response = await fetch("https://oauth2.googleapis.com/token", {
		method: "POST",
		headers: { "Content-Type": "application/x-www-form-urlencoded" },
		body: new URLSearchParams({
			grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
			assertion,
		}),
	});
	if (!response.ok) {
		throw new Error(
			`Google refused the service account assertion (${response.status}): ` +
			`${await response.text()}`,
		);
	}
	const token = await response.json() as { access_token: string; expires_in: number };
	cachedToken = { value: token.access_token, expiresAt: now + token.expires_in };
	return token.access_token;
}

/**
 * The purchase Play knows about, or null when Google says it does not exist
 * (404) — which is the answer to a forged or already-superseded token.
 *
 * Anything else throws: a 5xx from Google is NOT "the purchase is fake", and
 * treating it as such would strip Premium from a family that paid.
 */
export async function fetchStorePurchase(
	packageName: string,
	productId: string,
	purchaseToken: string,
): Promise<StorePurchase | null> {
	const url = `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/` +
		`${encodeURIComponent(packageName)}/purchases/subscriptions/` +
		`${encodeURIComponent(productId)}/tokens/${encodeURIComponent(purchaseToken)}`;

	const response = await fetch(url, {
		headers: { Authorization: `Bearer ${await playAccessToken()}` },
	});
	if (response.status === 404) return null;
	if (!response.ok) {
		throw new Error(
			`Play Developer API answered ${response.status}: ${await response.text()}`,
		);
	}
	return await response.json() as StorePurchase;
}

/**
 * Whether this purchase currently pays for Premium.
 *
 * `paymentState` 0 means the charge is still pending (a slow form of payment);
 * 1 is a free trial Google is running and 2/3 are pending upgrades — all of
 * them are "the subscription is live". The expiry is what actually bounds it,
 * and Play keeps it in the future through the grace period it manages itself.
 */
export function isPurchaseLive(purchase: StorePurchase, nowMs = Date.now()): boolean {
	const expiry = Number(purchase.expiryTimeMillis ?? "0");
	if (!Number.isFinite(expiry) || expiry <= 0) return false;
	if (expiry <= nowMs) return false;
	return purchase.paymentState !== 0;
}

/** The period end this purchase pays until, as an ISO instant. */
export function purchaseExpiry(purchase: StorePurchase): string | null {
	const expiry = Number(purchase.expiryTimeMillis ?? "0");
	return Number.isFinite(expiry) && expiry > 0
		? new Date(expiry).toISOString()
		: null;
}

/** What a deferral answered: Play's new expiry, or its refusal as-is. */
export type DeferOutcome =
	| { ok: true; newExpiryTimeMillis: string }
	| { ok: false; status: number; body: string };

/**
 * F-80 — moves a subscription's expiry (and so its next charge) from
 * [expectedExpiryMs] to [desiredExpiryMs]: `purchases.subscriptions.defer`.
 *
 * `expectedExpiryTimeMillis` is Google's own optimistic lock — a deferral
 * computed from a stale expiry is refused instead of applied twice — which is
 * what lets the caller reconcile an attempt whose answer it never saw.
 *
 * The call needs the "Manage orders and subscriptions" permission on the
 * service account in the Play Console; without it Google answers 401/403 and
 * this returns that status for the caller to record. Only a network failure
 * throws (the outcome is then UNKNOWN, never "refused").
 */
export async function deferStorePurchase(
	packageName: string,
	productId: string,
	purchaseToken: string,
	expectedExpiryMs: string,
	desiredExpiryMs: string,
): Promise<DeferOutcome> {
	const url = `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/` +
		`${encodeURIComponent(packageName)}/purchases/subscriptions/` +
		`${encodeURIComponent(productId)}/tokens/${encodeURIComponent(purchaseToken)}:defer`;

	const response = await fetch(url, {
		method: "POST",
		headers: {
			Authorization: `Bearer ${await playAccessToken()}`,
			"Content-Type": "application/json",
		},
		body: JSON.stringify({
			deferralInfo: {
				expectedExpiryTimeMillis: expectedExpiryMs,
				desiredExpiryTimeMillis: desiredExpiryMs,
			},
		}),
	});
	if (!response.ok) {
		return { ok: false, status: response.status, body: (await response.text()).slice(0, 2000) };
	}
	const answer = await response.json() as { newExpiryTimeMillis?: string };
	return { ok: true, newExpiryTimeMillis: answer.newExpiryTimeMillis ?? desiredExpiryMs };
}

/** Play reports money in micros; the ledger and the UI speak cents. */
export function priceCents(purchase: StorePurchase): number | null {
	const micros = Number(purchase.priceAmountMicros ?? "");
	if (!Number.isFinite(micros) || micros <= 0) return null;
	return Math.round(micros / 10000);
}
