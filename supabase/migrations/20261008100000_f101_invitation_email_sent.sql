-- F-101 — the invitation row remembers whether its e-mail actually left.
--
-- The T-103 audit (04/10/2026) watched the Família card say "Convite enviado"
-- beside a toast saying the e-mail had failed: the card only knew "pending or
-- expired", and the failure lived in a transient snack. In production that
-- failure is Resend's 100/day account allowance (T-67, shared with sign-ups and
-- a second product), so a founder who invites on a busy day is told two
-- opposite things and loses the one next step that works — sharing the link.
--
-- `email_sent_at` is stamped by `send-swap-email` (service role) after Resend
-- accepted the message — or after the T-49 suppression of a test recipient,
-- where nothing failed. A Resend refusal throws before the stamp, so the column
-- stays NULL and the card says "E-mail não enviado" with *Compartilhar* as the
-- obvious move. No client writes it; the table's grants are unchanged (RLS
-- family-scoped SELECT, writes only through the RPCs).
--
-- Rows that exist today were sent before anything recorded it: they are
-- backfilled from `created_at`, because a card that suddenly called every open
-- invitation "não enviado" would be lying in the other direction.

ALTER TABLE public.family_invitations
	ADD COLUMN IF NOT EXISTS email_sent_at timestamptz;

COMMENT ON COLUMN public.family_invitations.email_sent_at IS
	'F-101: when send-swap-email handed the invitation e-mail to Resend (or suppressed a test recipient). NULL = the e-mail never left; the card offers the link instead. Backfilled from created_at for rows older than the column.';

UPDATE public.family_invitations
   SET email_sent_at = created_at
 WHERE email_sent_at IS NULL;
