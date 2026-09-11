// S-10 — sudo-mode elevation: prove it is still you, right now, and get a
// 5-minute elevation window.
//
// The client calls this with the user's JWT plus ONE of two proofs. The
// function resolves the user FROM THE TOKEN (never from the body) and then:
//
//   · `{ password }`      — verifies it through GoTrue's own token endpoint with
//     the publishable key — a throwaway grant whose tokens are discarded, so the
//     caller's session is never touched (same pattern as U-17's register-invitee).
//   · `{ request_code: true }` — mints a one-time code, stores only its digest
//     (see the S-21 migration) and mails the plaintext through
//     `send-account-email`. Grants nothing by itself.
//   · `{ code }`          — redeems that code.
//
// S-21: the second proof exists because a session that signed in with Google
// HAS NO PASSWORD, which shut the whole sudo surface — leaving the family,
// cancelling one's own departure, requesting / withdrawing / executing a family
// deletion, changing admin permissions, the F-58 console and
// admin-update-member-email — to four real accounts, three of them the sole
// admin of a one-seat family. Both proofs are offered to EVERY session, not
// just to password-less ones: production carries an account with a password and
// no `email` identity, so "which providers are on the token" was never a
// reliable answer to "can this person type a password", and the server is the
// only side that actually knows.
//
// Sensitive RPCs check is_elevated() server-side, so a stolen session token
// alone cannot perform account operations.
//
// Rate limiting: GoTrue's own password-grant limits apply to the verification
// call; the code path is throttled by CODE_MIN_INTERVAL_SECONDS on the request
// side and by a three-attempt ceiling on the redeem side (both enforced inside
// the RPCs, in one statement, so parallel guesses cannot each see zero); and the
// client throttles the prompt (3 failures → 60 s cooldown).

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { publishableKey, secretKey } from "../_shared/keys.ts";
import { internalCallHeaders } from "../_shared/auth.ts";

const ELEVATION_MINUTES = 5;

// S-21 — the code's numbers live HERE and nowhere else: the RPCs take them as
// arguments and the client's mirror test reads this file. Ten minutes is long
// enough to switch to a mail app and back on a phone, short enough that a code
// left in an inbox is not a standing key.
const CODE_LENGTH = 6;
const CODE_TTL_MINUTES = 10;
const CODE_MIN_INTERVAL_SECONDS = 60;

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

/** A uniformly distributed decimal code, from the CSPRNG. `Math.random()` is
 *  not acceptable here: this string is the whole proof. Rejection sampling
 *  keeps every code equally likely — taking a modulo of a byte would make the
 *  low digits measurably more common. */
function mintCode(): string {
  const digits = new Array<string>(CODE_LENGTH);
  const buf = new Uint8Array(1);
  for (let i = 0; i < CODE_LENGTH; i++) {
    let v: number;
    do {
      crypto.getRandomValues(buf);
      v = buf[0];
    } while (v >= 250); // 250 = 25 * 10; anything above would bias 0–5
    digits[i] = String(v % 10);
  }
  return digits.join("");
}

/** The digest the table stores. Salted with the user id so one leaked table is
 *  not a rainbow table over a million codes — and so the same code for two
 *  users is two different rows. */
async function hashCode(userId: string, code: string): Promise<string> {
  const bytes = new TextEncoder().encode(`${userId}:${code}`);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceKey  = secretKey();
    const anonKey     = publishableKey();
    const admin       = createClient(supabaseUrl, serviceKey);

    // Identity comes from the session token, never from the request body.
    const authHeader = req.headers.get("Authorization") ?? "";
    const jwt = authHeader.replace(/^Bearer\s+/i, "");
    if (!jwt) {
      return jsonResponse({ error: "Sessão inválida. Entre novamente." }, 401);
    }
    const { data: userData, error: userError } = await admin.auth.getUser(jwt);
    if (userError || !userData?.user?.email) {
      return jsonResponse({ error: "Sessão inválida. Entre novamente." }, 401);
    }
    const userId = userData.user.id;

    const body = await req.json().catch(() => ({}));
    const { password, code, request_code: requestCode } = body ?? {};

    // ── Mode 2: ask for a code ────────────────────────────────────────────────
    if (requestCode === true) {
      const plain = mintCode();
      const { data: requested, error: requestError } = await admin
        .rpc("request_elevation_code", {
          p_user_id: userId,
          p_code_hash: await hashCode(userId, plain),
          p_ttl_seconds: CODE_TTL_MINUTES * 60,
          p_min_interval_seconds: CODE_MIN_INTERVAL_SECONDS,
        });

      if (requestError) {
        console.error(`[elevate] request_elevation_code failed: ${requestError.message}`);
        return jsonResponse({ error: "Não foi possível enviar o código. Tente novamente." }, 500);
      }
      // The RPC returns a one-row table; PostgREST hands back a list.
      const row = Array.isArray(requested) ? requested[0] : requested;

      if (row?.status === "throttled") {
        // The previous code is still good — saying "wait" while it sits unused
        // in their inbox would be the wrong instruction.
        return jsonResponse({
          code_sent: false,
          throttled: true,
          expires_at: row.expires_at,
          error: "Já enviamos um código há pouco. Confira seu e-mail — ele ainda é válido.",
        }, 429);
      }

      // S-16: the relay authorizes the caller by the SECRET key on `apikey`, so
      // this is a bare fetch — `functions.invoke` would send the key as a
      // Bearer token, which `isSecretKeyCaller` refuses by design.
      const mailRes = await fetch(`${supabaseUrl}/functions/v1/send-account-email`, {
        method: "POST",
        headers: internalCallHeaders(serviceKey),
        body: JSON.stringify({
          emailType: "elevation_code",
          userId,
          code: plain,
          expiresInMinutes: CODE_TTL_MINUTES,
          // Same convention as every other send-account-email caller
          // (purge-deleted, register-invitee, claim-invitation): the subject
          // tag that tells a QA e-mail apart from a real one.
          environmentPrefix:
            (Deno.env.get("APP_ENVIRONMENT") ?? "Production").toLowerCase() === "production"
              ? ""
              : "[Dev] ",
        }),
      });
      if (!mailRes.ok) {
        console.error(`[elevate] elevation code mail failed: ${mailRes.status} ${await mailRes.text()}`);
        return jsonResponse({ error: "Não foi possível enviar o código. Tente novamente." }, 502);
      }

      return jsonResponse({
        code_sent: true,
        expires_at: row?.expires_at ?? null,
        expires_in_minutes: CODE_TTL_MINUTES,
      });
    }

    // ── Mode 3: redeem a code ─────────────────────────────────────────────────
    if (typeof code === "string" && code.trim() !== "") {
      const { data: verdict, error: consumeError } = await admin
        .rpc("consume_elevation_code", {
          p_user_id: userId,
          p_code_hash: await hashCode(userId, code.trim()),
        });

      if (consumeError) {
        console.error(`[elevate] consume_elevation_code failed: ${consumeError.message}`);
        return jsonResponse({ error: "Não foi possível confirmar. Tente novamente." }, 500);
      }

      if (verdict !== "ok") {
        // 401 for every refusal, so the client's existing "the proof was
        // rejected" branch covers this path too; the SENTENCE is what differs,
        // because "wrong code" and "ask for a new one" are different next steps.
        const message = verdict === "locked"
          ? "Muitas tentativas. Peça um novo código."
          : verdict === "invalid"
          ? "Código incorreto."
          : "Código expirado. Peça um novo.";
        return jsonResponse({ error: message, verdict }, 401);
      }

      return jsonResponse(await grantElevation(admin, userId));
    }

    // ── Mode 1: the password ──────────────────────────────────────────────────
    if (!password || typeof password !== "string") {
      return jsonResponse({ error: "Informe sua senha." }, 400);
    }

    // Throwaway password grant against GoTrue — the returned tokens are
    // discarded on purpose; this is only a password check.
    const verify = await fetch(`${supabaseUrl}/auth/v1/token?grant_type=password`, {
      method: "POST",
      headers: { "Content-Type": "application/json", apikey: anonKey },
      body: JSON.stringify({ email: userData.user.email, password }),
    });

    if (verify.status === 429) {
      return jsonResponse(
        { error: "Muitas tentativas. Aguarde alguns minutos antes de tentar novamente." }, 429);
    }
    if (!verify.ok) {
      return jsonResponse({ error: "Senha incorreta." }, 401);
    }

    return jsonResponse(await grantElevation(admin, userId));
  } catch (err) {
    console.error(`[elevate] unexpected: ${err instanceof Error ? err.message : err}`);
    return jsonResponse({ error: "Não foi possível confirmar. Tente novamente." }, 500);
  }
});

/** Opens the window. Shared by both proofs on purpose — whatever was verified,
 *  what the gated RPCs see afterwards is identical. */
async function grantElevation(
  admin: ReturnType<typeof createClient>,
  userId: string,
): Promise<Record<string, unknown>> {
  const elevatedUntil = new Date(Date.now() + ELEVATION_MINUTES * 60_000).toISOString();
  const { error: upsertError } = await admin
    .from("auth_elevations")
    .upsert({ user_id: userId, elevated_until: elevatedUntil });

  if (upsertError) {
    console.error(`[elevate] upsert failed: ${upsertError.message}`);
    throw new Error(`auth_elevations upsert: ${upsertError.message}`);
  }
  return { elevated_until: elevatedUntil };
}
