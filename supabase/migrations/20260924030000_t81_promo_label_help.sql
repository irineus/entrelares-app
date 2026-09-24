-- =============================================================================
-- T-81 (follow-up) — the promo flag's help promises only what the flag controls
--
-- `landing.promo_price_label` rules ONE line of the site's price card ("Preço de
-- lançamento até 31/12/2026" / "Launch price until Dec 31, 2026"). Its first help
-- text also claimed "the note that says until when it lasts", which L-34 does not
-- tie to the flag: the FAQ and the price note carry dated sentences that stay
-- true on their own. A separate migration rather than an edit, because the first
-- one had already reached the dev project and `db push` never re-applies a file.
-- =============================================================================

UPDATE public.app_settings
SET help = help || jsonb_build_object(
	'controls', 'A linha "Preço de lançamento até 31/12/2026" do cartão de preço do site (português e inglês). As frases datadas do FAQ e da nota de preço não mudam por aqui.',
	'requires', 'Ao encerrar a promoção, ajustar também os preços e revisar as frases datadas do site (FAQ e nota de preço) — a promoção anunciada vence em 31/12/2026.')
WHERE key = 'landing.promo_price_label';
