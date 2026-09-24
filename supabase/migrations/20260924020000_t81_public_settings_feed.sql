-- =============================================================================
-- T-81 — A public, read-only feed of the parameters the landing may show
--
-- The landing (`entrelares-site`) repeats prices, plan limits and launch flags
-- by hand; L-34 makes it read them. It needs a source it can read WITHOUT any
-- credential: `app_settings` is SELECT for `authenticated` only (RLS is_public,
-- column grant since T-80) and the anon key has zero privilege by construction
-- (T-44). Granting anon a table or an RPC would break that invariant, so the
-- feed is an Edge Function (`public-settings`) that reads with the secret key
-- and answers a fixed whitelist — this column.
--
--   · `landing_visible` is NOT `is_public`: `is_public` means "the signed-in app
--     may read it"; a landing value is readable by the whole internet. The
--     CHECK makes a site value always an app value too, so a server-only row
--     (the e-mail caps) can never leak through the feed.
--   · Three landing-only flags are born here with the T-80 metadata. The Play
--     badge flag starts TRUE, not false as the card proposed: the landing
--     already shows the badge since the T-59 flip (22/09/2026), and the flag
--     mirrors today's page — it is the switch to take the badge DOWN, not the
--     one that puts it up.
-- =============================================================================

ALTER TABLE public.app_settings
	ADD COLUMN IF NOT EXISTS landing_visible boolean NOT NULL DEFAULT false;

ALTER TABLE public.app_settings
	ADD CONSTRAINT app_settings_landing_is_public
		CHECK (NOT landing_visible OR is_public);

COMMENT ON COLUMN public.app_settings.landing_visible IS
	'T-81: served to anyone by the public-settings Edge Function (the landing reads it, L-34). Implies is_public (CHECK).';

-- ── The whitelist: what entrelares.app states today ─────────────────────────
-- The help of each key stops saying the landing types the number by hand; the
-- sentence is true from this migration on for the FEED, and for the page once
-- L-34 ships.

UPDATE public.app_settings SET landing_visible = true,
	help = help || jsonb_build_object('caveats',
		'NÃO muda: assinaturas Asaas ativas (os Termos garantem o preço contratado) e o preço da Play (Play Console). O site lê este valor pelo feed public-settings (T-81) a partir do L-34, com cache de alguns minutos.')
WHERE key = 'billing.price_monthly_cents';

UPDATE public.app_settings SET landing_visible = true,
	help = help || jsonb_build_object('caveats',
		'NÃO muda: assinaturas Asaas ativas e o preço da Play. Precisa ser no máximo 12 × o mensal. O site lê este valor pelo feed public-settings (T-81) a partir do L-34, com cache de alguns minutos.')
WHERE key = 'billing.price_annual_cents';

UPDATE public.app_settings SET landing_visible = true,
	help = help || jsonb_build_object('caveats',
		'O app já lê o valor (U-57). O site lê pelo feed public-settings (T-81) a partir do L-34, com cache de alguns minutos. Precisa ser no máximo calendar_months_premium.')
WHERE key = 'calendar_months_free';

UPDATE public.app_settings SET landing_visible = true,
	help = help || jsonb_build_object('caveats',
		'O app já lê o valor. O site lê pelo feed public-settings (T-81) a partir do L-34, com cache de alguns minutos. Precisa ser no mínimo calendar_months_free.')
WHERE key = 'calendar_months_premium';

UPDATE public.app_settings SET landing_visible = true,
	help = help || jsonb_build_object('caveats',
		'Os Termos dizem "dois responsáveis" (entrelares-site, termos.html) — o texto legal nunca é substituído pelo feed. O site lê o valor pelo feed public-settings (T-81) a partir do L-34. Precisa ser no máximo max_caregivers.')
WHERE key = 'free_caregivers';

-- ── Landing-only flags ───────────────────────────────────────────────────────

INSERT INTO public.app_settings
	(key, value, value_type, category, description, is_public, landing_visible, unit, impact, help)
VALUES
	('landing.launch_free_badge', 'true', 'bool', 'landing',
	 'Mostra a frase "Grátis no lançamento" no site (hero e caixas de chamada, só em português).',
	 true, true, 'flag', 'sensitive',
	 jsonb_build_object(
		'controls', 'A frase "Grátis no lançamento" do site em português: o selo do hero e as quatro caixas de chamada.',
		'shown_at', jsonb_build_array('landing'),
		'if_increased', 'Ligado: o site promete que o app é grátis no lançamento.',
		'if_decreased', 'Desligado: a frase some do site. O "Free plan, no credit card" da versão em inglês fica sempre — o plano gratuito existe com ou sem lançamento.',
		'takes_effect', 'Site em alguns minutos (cache do L-34); o app não lê esta chave.',
		'caveats', 'Só a frase: o plano gratuito e os limites dele não mudam por aqui.')),
	('landing.promo_price_label', 'true', 'bool', 'landing',
	 'Mostra no site a linha "Preço de lançamento até 31/12/2026" no cartão de preço.',
	 true, true, 'flag', 'normal',
	 jsonb_build_object(
		'controls', 'A linha "Preço de lançamento até 31/12/2026" do cartão de preço do site (português e inglês). As frases datadas do FAQ e da nota de preço não mudam por aqui.',
		'shown_at', jsonb_build_array('landing'),
		'if_increased', 'Ligado: o site chama o preço atual de preço de lançamento.',
		'if_decreased', 'Desligado: o preço aparece sem o rótulo de lançamento — use quando a promoção acabar.',
		'takes_effect', 'Site em alguns minutos (cache do L-34); o app não lê esta chave.',
		'caveats', 'Só o rótulo: o valor vem de billing.price_monthly_cents / billing.price_annual_cents.',
		'requires', 'Ao encerrar a promoção, ajustar também os preços e revisar as frases datadas do site (FAQ e nota de preço) — a promoção anunciada vence em 31/12/2026.')),
	('landing.play_badge', 'true', 'bool', 'landing',
	 'Mostra no site o selo do Google Play e a frase "No Google Play e na web".',
	 true, true, 'flag', 'sensitive',
	 jsonb_build_object(
		'controls', 'O selo oficial do Google Play e o selo "No Google Play e na web" do hero do site, nas duas línguas.',
		'shown_at', jsonb_build_array('landing'),
		'if_increased', 'Ligado: o site manda o visitante Android para a ficha da Play.',
		'if_decreased', 'Desligado: o site volta a oferecer só a versão web — use se a ficha da Play sair do ar.',
		'takes_effect', 'Site em alguns minutos (cache do L-34); o app não lê esta chave.',
		'caveats', 'Nasce ligado porque o site já mostra o selo desde a virada do T-59 (22/09/2026).'))
ON CONFLICT (key) DO NOTHING;
