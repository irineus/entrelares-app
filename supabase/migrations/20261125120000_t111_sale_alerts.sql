-- =============================================================================
-- T-111 — the operator hears of every sale the moment it happens
--
-- WHY. Google Play sends no per-sale notification (the Play Console's e-mail
-- settings have only "Payments and compliance", checked 25/11/2026) and the
-- Asaas dashboard is a second console. Both rails already reach us in real
-- time — `billing-webhook` (Asaas), `billing-store-webhook` (Play RTDN) and
-- `billing-store-verify` (the app's purchase) — and until now told nobody.
-- T-99's bulletin counts the week on Mondays; this is the moment.
--
-- WHAT. Owner, 25/11/2026: ONE e-mail per event to the operator inbox, for a
-- first purchase, a renewal, a cancellation and a refund; a license-tester
-- purchase alerts too, tagged "[teste]"; a trial start is not a sale. The
-- message carries rail, kind, cycle, amount and time — never a family, member,
-- e-mail or order id (the F-69 / T-99 rule).
--
-- HOW. The functions call `claim_sale_alert` BEFORE sending. The ledger below
-- is the dedupe across rails and paths: the Play verification and the RTDN of
-- the same period share the Google order id (F-107's key), Asaas sends
-- CONFIRMED and then RECEIVED for one card payment, and DELETED + INACTIVATED
-- for one cancellation — the first claim wins and the rest send nothing. A
-- switched-off key claims nothing. `sent_at` is stamped after Resend accepts;
-- NULL means the send was attempted and failed (logged, never retried — a sale
-- alert must never fail or retry the webhook that applied the money).
--
-- ACCESS. Service role only, table and function.
-- =============================================================================

-- ── 1. The kill switch ──────────────────────────────────────────────────────

INSERT INTO public.app_settings
	(key, value, value_type, category, description, is_public, unit, impact, help)
VALUES
	('ops.sale_alert.enabled', 'true', 'bool', 'operator',
	 'Liga o e-mail ao operador a cada compra, renovação, cancelamento ou reembolso, na Play e na web (T-111).',
	 false, 'flag', 'normal',
	 jsonb_build_object(
		'controls', 'Se os webhooks de cobrança (Asaas e Google Play) mandam um e-mail para contato@entrelares.app a cada primeira compra, renovação, cancelamento ou reembolso do Premium.',
		'shown_at', jsonb_build_array('email'),
		'if_increased', 'Ligado: um e-mail por acontecimento, só com canal, tipo, plano, valor e horário (nenhum nome, e-mail ou id de família). Compras de teste chegam marcadas [teste].',
		'if_decreased', 'Desligado: a cobrança segue aplicada normalmente e nenhum e-mail sai. Nenhuma família é afetada.',
		'takes_effect', 'No próximo evento de cobrança (a chave é lida a cada evento).',
		'caveats', 'Cada e-mail gasta um envio da cota diária do Resend, compartilhada com os e-mails de conta. No projeto de desenvolvimento chegam com [Dev] no assunto.'))
ON CONFLICT (key) DO NOTHING;

-- ── 2. The ledger: one alert per sale event ─────────────────────────────────

CREATE TABLE public.sale_alerts (
	sale_key     text PRIMARY KEY,
	rail         text NOT NULL CHECK (rail IN ('play', 'asaas')),
	kind         text NOT NULL CHECK (kind IN ('purchase', 'renewal', 'canceled', 'refund')),
	cycle        text NOT NULL CHECK (cycle IN ('monthly', 'annual', 'single', 'unknown')),
	amount_cents integer CHECK (amount_cents IS NULL OR amount_cents >= 0),
	currency     text CHECK (currency IS NULL OR currency ~ '^[A-Z]{3}$'),
	is_test      boolean NOT NULL DEFAULT false,
	created_at   timestamp with time zone NOT NULL DEFAULT timezone('utc', now()),
	sent_at      timestamp with time zone
);

COMMENT ON TABLE public.sale_alerts IS
	'T-111: one row per sale event e-mailed to the operator (dedupe key: Google order id, Asaas payment/subscription id). No family data. Service role only.';

ALTER TABLE public.sale_alerts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.sale_alerts FROM anon, authenticated;
GRANT ALL ON public.sale_alerts TO service_role;

-- ── 3. The claim ────────────────────────────────────────────────────────────
-- TRUE = this caller owns the alert and must send it; FALSE = switched off, or
-- another path / a redelivery already claimed the same sale.

CREATE OR REPLACE FUNCTION public.claim_sale_alert(
	p_sale_key     text,
	p_rail         text,
	p_kind         text,
	p_cycle        text,
	p_amount_cents integer,
	p_currency     text,
	p_is_test      boolean
)
RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
	IF NOT public.setting_bool('ops.sale_alert.enabled', true) THEN
		RETURN false;
	END IF;

	INSERT INTO public.sale_alerts (sale_key, rail, kind, cycle, amount_cents, currency, is_test)
	VALUES (p_sale_key, p_rail, p_kind, COALESCE(p_cycle, 'unknown'), p_amount_cents, p_currency,
	        COALESCE(p_is_test, false))
	ON CONFLICT (sale_key) DO NOTHING;

	RETURN FOUND;
END;
$$;

ALTER FUNCTION public.claim_sale_alert(text, text, text, text, integer, text, boolean) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.claim_sale_alert(text, text, text, text, integer, text, boolean)
	FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_sale_alert(text, text, text, text, integer, text, boolean)
	TO service_role;
