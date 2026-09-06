// F-09 — the FCM HTTP v1 client.
//
// **Why hand-rolled.** The v1 API authenticates with a Google service account,
// not with a static server key (the legacy key API was retired in 2024). The
// canonical client is `firebase-admin`, a Node library whose dependency tree
// does not belong in an Edge Function; the actual work is a signed JWT
// exchanged for an access token, which Web Crypto does natively. Roughly the
// same shape as the Standard Webhooks verification `send-auth-email` already
// does by hand, and for the same reason.
//
// **The credential is a per-environment secret** (`FCM_SERVICE_ACCOUNT`, the
// service account's JSON). It must exist on dev AND prod BEFORE CI redeploys
// the functions — the same ordering trap S-16 documented for the API keys. It
// is absent by design until the owner does the console work, and everything
// here fails CLOSED: no credential means no push, never a thrown request that
// takes a notification INSERT down with it.

/// A send's outcome, per token. `retire` marks the tokens FCM says are dead —
/// the caller deletes those rows, which is the only garbage collection
/// `push_subscriptions` gets.
export interface SendResult {
	token: string;
	ok: boolean;
	retire: boolean;
	error?: string;
}

interface ServiceAccount {
	client_email: string;
	private_key: string;
	project_id: string;
}

const TOKEN_URL = "https://oauth2.googleapis.com/token";
const SCOPE = "https://www.googleapis.com/auth/firebase.messaging";

/// Isolate-scoped access-token cache. An isolate serves many notifications
/// before it is recycled, and minting a token per push would triple the
/// latency of every one of them for no benefit.
let cached: { token: string; expiresAt: number } | null = null;

function serviceAccount(): ServiceAccount | null {
	const raw = Deno.env.get("FCM_SERVICE_ACCOUNT");
	if (!raw) return null;
	try {
		const parsed = JSON.parse(raw) as ServiceAccount;
		if (!parsed.client_email || !parsed.private_key || !parsed.project_id) return null;
		return parsed;
	} catch {
		return null;
	}
}

/// True when this project is armed to push at all. Read by the function's
/// health branch so an unarmed environment says so instead of looking broken.
export function fcmConfigured(): boolean {
	return serviceAccount() !== null;
}

function base64url(bytes: Uint8Array | string): string {
	const raw = typeof bytes === "string"
		? bytes
		: String.fromCharCode(...bytes);
	return btoa(raw).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

/// PEM (PKCS#8) → a CryptoKey Web Crypto will sign with.
async function importPrivateKey(pem: string): Promise<CryptoKey> {
	// The JSON carries the PEM with literal "\n" escapes already decoded by
	// JSON.parse; strip the armour and the whitespace, and what is left is
	// base64 DER.
	const body = pem
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

async function accessToken(account: ServiceAccount): Promise<string> {
	const now = Math.floor(Date.now() / 1000);
	// 60s of slack: a token that expires in flight is a 401 nobody can retry
	// their way out of.
	if (cached && cached.expiresAt - 60 > now) return cached.token;

	const header = base64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
	const claims = base64url(JSON.stringify({
		iss: account.client_email,
		scope: SCOPE,
		aud: TOKEN_URL,
		iat: now,
		exp: now + 3600,
	}));

	const key = await importPrivateKey(account.private_key);
	const signature = new Uint8Array(
		await crypto.subtle.sign(
			"RSASSA-PKCS1-v1_5",
			key,
			new TextEncoder().encode(`${header}.${claims}`),
		),
	);
	const assertion = `${header}.${claims}.${base64url(signature)}`;

	const response = await fetch(TOKEN_URL, {
		method: "POST",
		headers: { "Content-Type": "application/x-www-form-urlencoded" },
		body: new URLSearchParams({
			grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
			assertion,
		}),
	});

	const payload = await response.json().catch(() => ({}));
	if (!response.ok || !payload.access_token) {
		throw new Error(
			`FCM token exchange failed (${response.status}): ${payload.error_description ?? payload.error ?? "no access_token"}`,
		);
	}

	cached = {
		token: payload.access_token as string,
		expiresAt: now + Number(payload.expires_in ?? 3600),
	};
	return cached.token;
}

/// One FCM message per token. FCM v1 has no multicast endpoint — the batch API
/// the old server key offered went with it — so N tokens is N requests, sent
/// concurrently. A family holds a handful of devices, so the fan-out is small
/// by construction.
export async function sendToTokens(
	tokens: string[],
	copy: { title: string; body: string },
	data: Record<string, string>,
): Promise<SendResult[]> {
	const account = serviceAccount();
	if (account === null || tokens.length === 0) return [];

	const bearer = await accessToken(account);
	const url =
		`https://fcm.googleapis.com/v1/projects/${account.project_id}/messages:send`;

	return await Promise.all(tokens.map(async (token): Promise<SendResult> => {
		try {
			const response = await fetch(url, {
				method: "POST",
				headers: {
					"Authorization": `Bearer ${bearer}`,
					"Content-Type": "application/json",
				},
				body: JSON.stringify({
					message: {
						token,
						// A `notification` block (not data-only): it is the only
						// payload the OS displays on its own with the app killed,
						// and on iOS a silent data message is throttled and may
						// never arrive. `data` rides alongside for the tap target.
						notification: { title: copy.title, body: copy.body },
						data,
						android: {
							priority: "high",
							notification: {
								// Groups a family's notices into one stack, and gives
								// the client a channel to create up front.
								channel_id: "entrelares_swaps",
								tag: data.notificationId,
							},
						},
						apns: {
							// Written now so the T-40 iOS build inherits a payload
							// that already behaves: the alert is what iOS renders,
							// and `sound` is what makes it more than a badge.
							payload: { aps: { sound: "default" } },
						},
						webpush: {
							// T-62 — the browser's equivalent of the Android
							// silhouette gotcha: with no `icon` the notification
							// arrives carrying whatever the browser picks, which on
							// desktop Chrome is a generic bell and not this product.
							// The path is RELATIVE on purpose — `showNotification`
							// resolves it against the service worker's own URL, so
							// the same payload names the right origin on every
							// environment and this sender never has to learn a
							// hostname it would then have to keep in sync.
							//
							// No `fcm_options.link`: the destination is a product
							// rule (which tab a type lands on), and it lives beside
							// the rule it mirrors, in `firebase-messaging-sw.js`.
							// Naming a link here would ALSO hand the tap to the
							// SDK's own click handler, which stops propagation.
							notification: { icon: "/icons/Icon-192.png" },
						},
					},
				}),
			});

			if (response.ok) return { token, ok: true, retire: false };

			const payload = await response.json().catch(() => ({}));
			const status = payload?.error?.status ?? String(response.status);
			// UNREGISTERED = the app was uninstalled or the token rotated.
			// INVALID_ARGUMENT on a send = a malformed token. Both are permanent,
			// and both are what keeps the table from filling with dead rows. Every
			// other failure (quota, 5xx) is transient and the row stays.
			const retire = status === "UNREGISTERED" || status === "NOT_FOUND" ||
				status === "INVALID_ARGUMENT";
			return { token, ok: false, retire, error: status };
		} catch (error) {
			return { token, ok: false, retire: false, error: String(error) };
		}
	}));
}
