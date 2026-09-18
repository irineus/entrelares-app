import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { secretKey } from "../_shared/keys.ts";
import { isSecretKeyCaller } from "../_shared/auth.ts";
import { resolveLang } from "../_shared/i18n.ts";
import { PUSH_TYPES, type PushParams, renderPush } from "../_shared/push.ts";
import { fcmConfigured, sendToTokens } from "../_shared/fcm.ts";

// F-09 — the push dispatcher.
//
// **One caller: the database.** Every push-worthy moment in this product
// already writes a `notifications` row — some by SQL trigger, some by the
// client's own insert. Hanging the dispatcher off THAT insert (a pg_net call
// from an AFTER INSERT trigger) is what keeps push, in-app and e-mail from ever
// telling three different stories: there is one event, written once, and the
// three channels are three renderings of it.
//
// Not browser-invoked, so no CORS. `verify_jwt` is off (the trigger sends the
// project's SECRET key on `apikey`, which the platform gate does not verify),
// so the caller is authorized here — S-16, same shape as the crons.
//
// **Everything fails closed and quiet.** An unarmed environment (no
// `FCM_SERVICE_ACCOUNT`), a recipient with no device, a payload that cannot be
// rendered, a token FCM has retired — each answers 200 with a reason. The
// notification row and its e-mail have already happened; a push that cannot be
// sent must never become an error the writer sees, and the trigger is fired
// asynchronously precisely so it cannot roll one back either.

interface Payload {
  notification_id?: number;
}

interface NotificationRow {
  id: number;
  recipient_profile_id: number;
  type: string;
  params: PushParams | null;
  swap_request_id: number | null;
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

serve(async (req: Request) => {
  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceKey = secretKey();
    const supabase = createClient(supabaseUrl, serviceKey);

    if (!isSecretKeyCaller(req, serviceKey)) {
      console.warn("[send-push-notification] refused — no secret key");
      return json({ error: "Não autorizado." }, 401);
    }

    // The warm-up POST the deploy pipeline sends carries no body. Answering it
    // with the arming state also makes this the cheapest way to ask a project
    // whether its FCM credential is in place.
    const payload = await req.json().catch(() => ({})) as Payload;
    if (!payload.notification_id) {
      return json({ skipped: "no notification_id", configured: fcmConfigured() });
    }

    if (!fcmConfigured()) {
      // Not an error: this is the state of every environment before the owner
      // does the Firebase console work, and the state prod stays in until the
      // secret is set. Saying so out loud beats a silent no-op.
      return json({ skipped: "FCM_SERVICE_ACCOUNT not set" });
    }

    const { data: row, error: readError } = await supabase
      .from("notifications")
      .select("id, recipient_profile_id, type, params, swap_request_id")
      .eq("id", payload.notification_id)
      .maybeSingle<NotificationRow>();

    if (readError) throw readError;
    if (!row) return json({ skipped: "notification not found" });

    // The trigger already filters, but a trigger can ship ahead of a function
    // and a type can be added to one list and not the other. Refusing twice is
    // what keeps that from becoming a push nobody designed.
    if (!PUSH_TYPES.includes(row.type)) {
      return json({ skipped: `type ${row.type} is not pushable` });
    }

    // U-13: the RECIPIENT's language, never the writer's — `language_effective`
    // and not `language`, because the first is NULL for anyone who never opened
    // the picker (see the same note in send-swap-email).
    const { data: profile } = await supabase
      .from("profiles")
      .select("language_effective")
      .eq("id", row.recipient_profile_id)
      .maybeSingle<{ language_effective: string | null }>();

    const lang = resolveLang(profile?.language_effective);
    const copy = renderPush(lang, row.type, row.params);
    if (copy === null) {
      console.warn(
        `[send-push-notification] unrenderable payload — notification ${row.id}, type ${row.type}`,
      );
      return json({ skipped: "payload could not be rendered" });
    }

    const { data: subs } = await supabase
      .from("push_subscriptions")
      .select("token")
      .eq("profile_id", row.recipient_profile_id);

    const tokens = (subs ?? []).map((s: { token: string }) => s.token);
    if (tokens.length === 0) return json({ skipped: "no registered device" });

    const results = await sendToTokens(tokens, copy, {
      // What the tap needs to land somewhere useful. Values only — the client
      // routes from these, it never renders them.
      notificationId: String(row.id),
      type: row.type,
      // F-52: the second dimension the tap routes on. One type carries four
      // wordings, and only two of them leave the reader with something to do —
      // without this the channel has to choose one tab for all four, and the
      // first version chose by not pushing the other three at all.
      kind: typeof row.params?.["kind"] === "string" ? row.params["kind"] : "",
      swapRequestId: row.swap_request_id === null ? "" : String(row.swap_request_id),
      date: row.params?.["date"] ?? "",
    });

    // The only garbage collection this table gets: FCM is the authority on
    // which tokens are dead, and it only says so in response to a real send.
    const retire = results.filter((r) => r.retire).map((r) => r.token);
    if (retire.length > 0) {
      await supabase.from("push_subscriptions").delete().in("token", retire);
    }

    const sent = results.filter((r) => r.ok).length;
    const failed = results.filter((r) => !r.ok && !r.retire);
    if (failed.length > 0) {
      console.warn(
        `[send-push-notification] ${failed.length} transient failure(s) on notification ${row.id}: ` +
          failed.map((f) => f.error).join(", "),
      );
    }

    return json({ sent, retired: retire.length, failed: failed.length });
  } catch (error) {
    // A thrown dispatcher must not look like a working one.
    console.error("[send-push-notification]", error);
    return json({ error: String(error) }, 500);
  }
});
