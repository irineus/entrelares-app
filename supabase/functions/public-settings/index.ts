// T-81 — the public, read-only feed of the parameters the landing may show.
//
// WHY. The landing (`entrelares-site`) states prices, plan limits and launch
// flags; L-34 makes it read them instead of typing them. It has no credential
// to read with, and giving it one would break T-44 (the anon key has zero
// privilege by construction). So this function reads `app_settings` with the
// secret key and answers ONLY the rows flagged `landing_visible` — a column
// whose CHECK makes every such row `is_public` too, so a server-only value (the
// e-mail caps) can never leave through here.
//
// CONTRACT (the consumer is L-34's Worker and its deploy job, server to server):
//   GET  → 200 {"values": {"<key>": "<value>"}, "updated_at": "<max updated_at>"}
//          Cache-Control: public, max-age=60 · ETag · 304 on a matching
//          If-None-Match
//   else → 405 (no CORS: no browser calls this)
//
// The ETag is a digest of the BODY, not `updated_at` as the card first said: a
// migration may move a value without stamping `updated_at` (the T-80 console
// is the only writer that does), and an ETag that did not move with the value
// would answer 304 over a stale price.
//
// Runs with verify_jwt = false: an anonymous caller holds no JWT, and the feed
// is public by design — what it may say is decided by the column, not the caller.

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { secretKey } from "../_shared/keys.ts";

const JSON_HEADERS = { "Content-Type": "application/json; charset=utf-8" };

async function digest(text: string): Promise<string> {
	const bytes = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
	return Array.from(new Uint8Array(bytes), (b) => b.toString(16).padStart(2, "0")).join("");
}

serve(async (req) => {
	if (req.method !== "GET") {
		return new Response(JSON.stringify({ error: "method_not_allowed" }), {
			status: 405,
			headers: { ...JSON_HEADERS, Allow: "GET" },
		});
	}

	const admin = createClient(Deno.env.get("SUPABASE_URL")!, secretKey());
	const { data, error } = await admin
		.from("app_settings")
		.select("key, value, updated_at")
		.eq("landing_visible", true)
		.order("key");

	if (error || !data) {
		console.error("public-settings: read failed", error);
		// No cache on a failure: the consumer keeps its last good copy (L-34's
		// Worker cache, or the values baked at deploy) and asks again next time.
		return new Response(JSON.stringify({ error: "unavailable" }), {
			status: 503,
			headers: { ...JSON_HEADERS, "Cache-Control": "no-store" },
		});
	}

	const values: Record<string, string> = {};
	let updatedAt = "";
	for (const row of data) {
		values[row.key] = row.value;
		if (row.updated_at > updatedAt) updatedAt = row.updated_at;
	}

	const body = JSON.stringify({ values, updated_at: updatedAt || null });
	const etag = `"${await digest(body)}"`;
	const headers = {
		...JSON_HEADERS,
		"Cache-Control": "public, max-age=60",
		ETag: etag,
	};

	if (req.headers.get("If-None-Match") === etag) {
		return new Response(null, { status: 304, headers });
	}
	return new Response(body, { status: 200, headers });
});
