-- =============================================================================
-- F-108 (PR 3) — the invitation by link, live in production
--
-- `feature.invite_link` was seeded false in PR 1 (T-84: every module is born
-- dark). Everything it gates is in place: the link invitation and its claim
-- paths on the server (PR 1, 20261119120000_f108_invite_link.sql), the app's
-- share-right-after-adding and the unlocked invitee e-mail (PR 2, 3.4.0 (231)),
-- and the Android already-signed-in offer (3.4.1 (232)).
--
-- ORDER (the S-22 trap, as in F-07's per_child_live): the Android build that
-- predates PR 2 locks the sign-up e-mail to the invitation's, so an invitation
-- born WITHOUT an e-mail would strand whoever installs from Play and gets that
-- older build. So this migration merges only AFTER the owner promoted a build
-- carrying PR 2 to Play Production — 3.5.0 (233), promoted 20/11/2026.
--
-- Takes effect: the server on the next invitation; the app on its next open
-- (settings are read once per open). Emergency switch: set the key back to
-- false in the console — links already shared stay valid until they expire
-- or are revoked.
--
-- No policy change: a link invitation stores LESS than an e-mail one (no
-- address), and the 30-day purge of never-accepted rows is untouched — not
-- material, no `PolicyVersions` bump (§3, S-15).
-- =============================================================================

UPDATE public.app_settings
SET value = 'true'
WHERE key = 'feature.invite_link';
