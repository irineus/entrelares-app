-- Reference rows a stack built from the migrations alone does not have.
--
-- Read by `supabase start` / `supabase db reset` (config.toml `[db.seed]`) and by
-- nothing else: `supabase db push` never runs it, so the hosted projects are not
-- touched. It exists for the DB gate's LOCAL stack (Fulcrum 04.3.1 / T-94).
--
-- The pair father/mother is DATA in the hosted projects, not migration: it came
-- with the V001 schema the 20260713 baseline dump replaced, and the F-27
-- catalog migration (20260715043019) only renamed it and seeded the other 19
-- roles around it. Idempotent, and by slug — never by id, which differs here.
INSERT INTO public.roles (role, label_pt)
SELECT v.role, v.label_pt
FROM (VALUES ('father', 'Pai'), ('mother', 'Mãe')) AS v(role, label_pt)
WHERE NOT EXISTS (
  SELECT 1 FROM public.roles r
  WHERE r.family_id IS NULL AND r.role = v.role
);
