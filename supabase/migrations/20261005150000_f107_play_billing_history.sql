-- =============================================================================
-- F-107 — the payment history learns the Google Play rail
--
-- `get_billing_history` (F-43, 28/07/2026) predates the store rail and read
-- only the Asaas event types, from the Asaas payload shape. T-48's migration
-- promised that store money would "land as ordinary payments" in this timeline
-- and never redefined the RPC: since 23/08/2026 a family paying through Play
-- has seen an empty history. Found by the owner on 05/10/2026, with two test
-- purchases active and only an August Pix listed.
--
-- The Play rows, read from what the store rail writes:
--   · payment  — PLAY_PURCHASE_VERIFIED (`billing-store-verify`) and the
--                activating RTDNs 1/2/4/7 (`billing-store-webhook`, which since
--                F-107 keeps the purchase it fetches under `payload.purchase`).
--                Only a PAID purchase (`paymentState` 1, or absent) with the
--                purchase in the payload; the amount is `priceAmountMicros`.
--                One row per Google order: the verification and the RTDN of the
--                same period share `purchase.orderId` (`GPA…`, `GPA…..1` on the
--                first renewal), which is the dedupe key.
--   · canceled — RTDN 3 (no more renewals; paid time honored).
--   · refund   — RTDN 12 (revoked: Google refunded and took access back).
--   · downgraded — RTDN 13 (expired: back to Gratuito).
-- An RTDN written before F-107 carries no purchase, so it cannot say what was
-- paid nor be deduped against its verification: it is left out rather than
-- shown twice or without an amount. Dunning RTDNs (5/6/10) stay out, as they
-- were — the plan screen already tells an overdue Play payer what to do.
-- billing_type 'PLAY'; no invoice URL (Google mails the receipt).
-- Signature, admin gate, family scope, 100-row cap and Asaas rows: unchanged.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_billing_history()
RETURNS TABLE (
	occurred_at  timestamp with time zone,
	category     text,
	amount       numeric,
	billing_type text,
	invoice_url  text
)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
	me public.profiles%ROWTYPE;
BEGIN
	SELECT * INTO me FROM public.profiles WHERE user_id = auth.uid();
	IF me.id IS NULL OR NOT me.is_admin THEN
		RAISE EXCEPTION 'Somente administradores da família podem ver o histórico de pagamentos.'
			USING ERRCODE = 'check_violation';
	END IF;

	RETURN QUERY
	WITH asaas AS (
		SELECT e.received_at AS r_at,
		       CASE e.event_type
		           WHEN 'PAYMENT_CONFIRMED'        THEN 'payment'
		           WHEN 'PAYMENT_RECEIVED'         THEN 'payment'
		           WHEN 'PAYMENT_REFUNDED'         THEN 'refund'
		           WHEN 'PAYMENT_OVERDUE'          THEN 'overdue'
		           WHEN 'SUBSCRIPTION_DELETED'     THEN 'canceled'
		           WHEN 'SUBSCRIPTION_INACTIVATED' THEN 'canceled'
		           WHEN 'GRACE_DOWNGRADE'          THEN 'downgraded'
		       END AS r_category,
		       (e.payload -> 'payment' ->> 'value')::numeric AS r_amount,
		       e.payload -> 'payment' ->> 'billingType'      AS r_billing_type,
		       e.payload -> 'payment' ->> 'invoiceUrl'       AS r_invoice_url,
		       COALESCE(e.payload -> 'payment' ->> 'id', e.event_id) AS r_dedupe
		FROM public.billing_events e
		WHERE e.family_id = me.family_id
		  AND e.event_type IN ('PAYMENT_CONFIRMED', 'PAYMENT_RECEIVED', 'PAYMENT_REFUNDED',
		                       'PAYMENT_OVERDUE', 'SUBSCRIPTION_DELETED',
		                       'SUBSCRIPTION_INACTIVATED', 'GRACE_DOWNGRADE')
	), play_paid AS (
		SELECT e.received_at AS r_at,
		       'payment'::text AS r_category,
		       round((e.payload -> 'purchase' ->> 'priceAmountMicros')::numeric / 1000000, 2) AS r_amount,
		       'PLAY'::text AS r_billing_type,
		       NULL::text AS r_invoice_url,
		       'play:' || COALESCE(e.payload -> 'purchase' ->> 'orderId', e.event_id) AS r_dedupe
		FROM public.billing_events e
		WHERE e.family_id = me.family_id
		  AND e.event_type IN ('PLAY_PURCHASE_VERIFIED',
		                       'PLAY_RTDN_1', 'PLAY_RTDN_2', 'PLAY_RTDN_4', 'PLAY_RTDN_7')
		  AND jsonb_typeof(e.payload -> 'purchase') = 'object'
		  AND COALESCE(e.payload -> 'purchase' ->> 'paymentState', '1') = '1'
	), play_state AS (
		SELECT e.received_at AS r_at,
		       CASE e.event_type
		           WHEN 'PLAY_RTDN_3'  THEN 'canceled'
		           WHEN 'PLAY_RTDN_12' THEN 'refund'
		           WHEN 'PLAY_RTDN_13' THEN 'downgraded'
		       END AS r_category,
		       NULL::numeric AS r_amount,
		       'PLAY'::text AS r_billing_type,
		       NULL::text AS r_invoice_url,
		       e.event_id AS r_dedupe
		FROM public.billing_events e
		WHERE e.family_id = me.family_id
		  AND e.event_type IN ('PLAY_RTDN_3', 'PLAY_RTDN_12', 'PLAY_RTDN_13')
	), relevant AS (
		SELECT * FROM asaas
		UNION ALL SELECT * FROM play_paid
		UNION ALL SELECT * FROM play_state
	), deduped AS (
		SELECT DISTINCT ON (r.r_category, r.r_dedupe)
		       r.r_at, r.r_category, r.r_amount, r.r_billing_type, r.r_invoice_url
		FROM relevant r
		ORDER BY r.r_category, r.r_dedupe, r.r_at ASC
	)
	SELECT d.r_at, d.r_category, d.r_amount, d.r_billing_type, d.r_invoice_url
	FROM deduped d
	ORDER BY d.r_at DESC
	LIMIT 100;
END;
$$;

ALTER FUNCTION public.get_billing_history() OWNER TO postgres;
REVOKE ALL ON FUNCTION public.get_billing_history() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_billing_history() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_billing_history() TO service_role;
