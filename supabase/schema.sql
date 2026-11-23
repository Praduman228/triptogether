-- Trip Expense App - Supabase Schema Migration
-- Run this in your Supabase Dashboard: SQL Editor -> New Query -> Run

-- 1. Profiles Table
CREATE TABLE IF NOT EXISTS public.profiles (
  id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  full_name text NOT NULL DEFAULT '',
  email text NOT NULL DEFAULT '',
  avatar_url text,
  created_at timestamptz NOT NULL DEFAULT now()
);

GRANT SELECT, UPDATE ON public.profiles TO authenticated;
GRANT ALL ON public.profiles TO service_role;
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='profiles' AND policyname='profile_self_select') THEN
    CREATE POLICY profile_self_select ON public.profiles FOR SELECT TO authenticated USING (id = auth.uid());
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='profiles' AND policyname='profile_self_update') THEN
    CREATE POLICY profile_self_update ON public.profiles FOR UPDATE TO authenticated USING (id = auth.uid()) WITH CHECK (id = auth.uid());
  END IF;
END $$;

-- Automatic profile creation on auth.users insert (supports Google OAuth metadata)
CREATE OR REPLACE FUNCTION public.create_profile()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.profiles (id, email, full_name, avatar_url)
  VALUES (
    NEW.id,
    coalesce(NEW.email, ''),
    coalesce(NEW.raw_user_meta_data->>'full_name', NEW.raw_user_meta_data->>'name', ''),
    NEW.raw_user_meta_data->>'avatar_url'
  )
  ON CONFLICT (id) DO UPDATE SET
    full_name = coalesce(nullif(EXCLUDED.full_name, ''), public.profiles.full_name),
    avatar_url = coalesce(EXCLUDED.avatar_url, public.profiles.avatar_url),
    email = coalesce(nullif(EXCLUDED.email, ''), public.profiles.email);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_trip_user_created ON auth.users;
CREATE TRIGGER on_trip_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.create_profile();

-- Backfill any existing auth users
INSERT INTO public.profiles (id, email, full_name, avatar_url)
SELECT
  id,
  coalesce(email, ''),
  coalesce(raw_user_meta_data->>'full_name', raw_user_meta_data->>'name', ''),
  raw_user_meta_data->>'avatar_url'
FROM auth.users
ON CONFLICT (id) DO NOTHING;

-- 2. Trips
CREATE TABLE IF NOT EXISTS public.trips (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id uuid NOT NULL REFERENCES public.profiles(id),
  name text NOT NULL CHECK (length(name) BETWEEN 1 AND 120),
  destination text NOT NULL,
  start_date date NOT NULL,
  end_date date NOT NULL,
  budget bigint NOT NULL CHECK (budget >= 0 AND budget <= 9000000000000),
  currency text NOT NULL DEFAULT 'INR' CHECK (currency IN ('INR','USD','EUR','GBP')),
  description text NOT NULL DEFAULT '',
  cover_path text,
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK (end_date >= start_date)
);

GRANT SELECT ON public.trips TO authenticated;
GRANT ALL ON public.trips TO service_role;
ALTER TABLE public.trips ENABLE ROW LEVEL SECURITY;

-- 3. Trip Members & Roles
CREATE TABLE IF NOT EXISTS public.trip_members (
  trip_id uuid NOT NULL REFERENCES public.trips(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'left')),
  joined_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (trip_id, user_id)
);

GRANT SELECT ON public.trip_members TO authenticated;
GRANT ALL ON public.trip_members TO service_role;
ALTER TABLE public.trip_members ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.trip_member_roles (
  trip_id uuid NOT NULL,
  user_id uuid NOT NULL,
  role text NOT NULL CHECK (role IN ('creator', 'administrator', 'participant')),
  PRIMARY KEY (trip_id, user_id),
  FOREIGN KEY (trip_id, user_id) REFERENCES public.trip_members(trip_id, user_id) ON DELETE CASCADE
);

GRANT SELECT ON public.trip_member_roles TO authenticated;
GRANT ALL ON public.trip_member_roles TO service_role;
ALTER TABLE public.trip_member_roles ENABLE ROW LEVEL SECURITY;

-- Helper security functions
CREATE OR REPLACE FUNCTION public.is_trip_member(t uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.trip_members
    WHERE trip_id = t AND user_id = auth.uid() AND status = 'active'
  );
$$;

CREATE OR REPLACE FUNCTION public.can_manage_trip(t uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.is_trip_member(t) AND EXISTS (
    SELECT 1 FROM public.trip_member_roles
    WHERE trip_id = t AND user_id = auth.uid() AND role IN ('creator', 'administrator')
  );
$$;

REVOKE ALL ON FUNCTION public.is_trip_member(uuid), public.can_manage_trip(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_trip_member(uuid), public.can_manage_trip(uuid) TO authenticated;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='trips' AND policyname='trip_read') THEN
    CREATE POLICY trip_read ON public.trips FOR SELECT TO authenticated USING (public.is_trip_member(id));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='trip_members' AND policyname='members_read') THEN
    CREATE POLICY members_read ON public.trip_members FOR SELECT TO authenticated USING (public.is_trip_member(trip_id));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='trip_member_roles' AND policyname='roles_read') THEN
    CREATE POLICY roles_read ON public.trip_member_roles FOR SELECT TO authenticated USING (public.is_trip_member(trip_id));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='profiles' AND policyname='profile_trip_read') THEN
    CREATE POLICY profile_trip_read ON public.profiles FOR SELECT TO authenticated
      USING (EXISTS (SELECT 1 FROM public.trip_members m WHERE m.user_id = profiles.id AND public.is_trip_member(m.trip_id)));
  END IF;
END $$;

-- 4. Trip Invitations
CREATE TABLE IF NOT EXISTS public.trip_invitations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  trip_id uuid NOT NULL REFERENCES public.trips(id) ON DELETE CASCADE,
  inviter_id uuid NOT NULL REFERENCES public.profiles(id),
  recipient_email text,
  token_hash text NOT NULL UNIQUE,
  expires_at timestamptz NOT NULL DEFAULT now() + interval '7 days',
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'revoked')),
  accepted_by uuid REFERENCES public.profiles(id),
  created_at timestamptz NOT NULL DEFAULT now()
);

GRANT SELECT(id, trip_id, inviter_id, recipient_email, expires_at, status, accepted_by, created_at) ON public.trip_invitations TO authenticated;
GRANT ALL ON public.trip_invitations TO service_role;
ALTER TABLE public.trip_invitations ENABLE ROW LEVEL SECURITY;

CREATE UNIQUE INDEX IF NOT EXISTS active_trip_email ON public.trip_invitations(trip_id, lower(recipient_email))
  WHERE status = 'pending' AND recipient_email IS NOT NULL;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='trip_invitations' AND policyname='invitations_read') THEN
    CREATE POLICY invitations_read ON public.trip_invitations FOR SELECT TO authenticated USING (public.can_manage_trip(trip_id));
  END IF;
END $$;

-- 5. Expense Categories
CREATE TABLE IF NOT EXISTS public.expense_categories (
  slug text PRIMARY KEY,
  label text NOT NULL
);

GRANT SELECT ON public.expense_categories TO authenticated;
GRANT ALL ON public.expense_categories TO service_role;
ALTER TABLE public.expense_categories ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='expense_categories' AND policyname='categories_read') THEN
    CREATE POLICY categories_read ON public.expense_categories FOR SELECT TO authenticated USING (true);
  END IF;
END $$;

INSERT INTO public.expense_categories (slug, label) VALUES
  ('Accommodation', 'Accommodation'),
  ('Food & drinks', 'Food & drinks'),
  ('Transportation', 'Transportation'),
  ('Fuel', 'Fuel'),
  ('Shopping', 'Shopping'),
  ('Activities', 'Activities'),
  ('Entertainment', 'Entertainment'),
  ('Miscellaneous', 'Miscellaneous')
ON CONFLICT (slug) DO NOTHING;

-- 6. Expenses, Contributions, Splits
CREATE TABLE IF NOT EXISTS public.expenses (
  id uuid PRIMARY KEY,
  trip_id uuid NOT NULL REFERENCES public.trips(id) ON DELETE CASCADE,
  created_by uuid NOT NULL REFERENCES public.profiles(id),
  title text NOT NULL CHECK (length(title) BETWEEN 1 AND 160),
  amount bigint NOT NULL CHECK (amount > 0 AND amount <= 9000000000000),
  category text NOT NULL CHECK (category IN ('Accommodation','Food & drinks','Transportation','Fuel','Shopping','Activities','Entertainment','Miscellaneous')),
  occurred_at timestamptz NOT NULL,
  description text NOT NULL DEFAULT '',
  receipt_path text,
  reversal_of uuid UNIQUE REFERENCES public.expenses(id),
  created_at timestamptz NOT NULL DEFAULT now()
);

GRANT SELECT ON public.expenses TO authenticated;
GRANT ALL ON public.expenses TO service_role;
ALTER TABLE public.expenses ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='expenses' AND policyname='expenses_read') THEN
    CREATE POLICY expenses_read ON public.expenses FOR SELECT TO authenticated USING (public.is_trip_member(trip_id));
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS expenses_trip_date ON public.expenses(trip_id, occurred_at DESC);

CREATE TABLE IF NOT EXISTS public.expense_contributions (
  expense_id uuid NOT NULL REFERENCES public.expenses(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.profiles(id),
  amount bigint NOT NULL CHECK (amount > 0),
  PRIMARY KEY (expense_id, user_id)
);

GRANT SELECT ON public.expense_contributions TO authenticated;
GRANT ALL ON public.expense_contributions TO service_role;
ALTER TABLE public.expense_contributions ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='expense_contributions' AND policyname='contributions_read') THEN
    CREATE POLICY contributions_read ON public.expense_contributions FOR SELECT TO authenticated
      USING (EXISTS (SELECT 1 FROM public.expenses e WHERE e.id = expense_id AND public.is_trip_member(e.trip_id)));
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS public.expense_splits (
  expense_id uuid NOT NULL REFERENCES public.expenses(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.profiles(id),
  amount bigint NOT NULL CHECK (amount >= 0),
  PRIMARY KEY (expense_id, user_id)
);

GRANT SELECT ON public.expense_splits TO authenticated;
GRANT ALL ON public.expense_splits TO service_role;
ALTER TABLE public.expense_splits ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='expense_splits' AND policyname='splits_read') THEN
    CREATE POLICY splits_read ON public.expense_splits FOR SELECT TO authenticated
      USING (EXISTS (SELECT 1 FROM public.expenses e WHERE e.id = expense_id AND public.is_trip_member(e.trip_id)));
  END IF;
END $$;

-- 7. Settlements & Allocations
CREATE TABLE IF NOT EXISTS public.settlements (
  id uuid PRIMARY KEY,
  trip_id uuid NOT NULL REFERENCES public.trips(id) ON DELETE CASCADE,
  created_by uuid NOT NULL REFERENCES public.profiles(id),
  sender_id uuid NOT NULL REFERENCES public.profiles(id),
  recipient_id uuid NOT NULL REFERENCES public.profiles(id),
  amount bigint NOT NULL CHECK (amount > 0 AND amount <= 9000000000000),
  note text NOT NULL DEFAULT '',
  occurred_at timestamptz NOT NULL DEFAULT now(),
  CHECK (sender_id <> recipient_id)
);

GRANT SELECT ON public.settlements TO authenticated;
GRANT ALL ON public.settlements TO service_role;
ALTER TABLE public.settlements ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='settlements' AND policyname='settlements_read') THEN
    CREATE POLICY settlements_read ON public.settlements FOR SELECT TO authenticated USING (public.is_trip_member(trip_id));
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS public.settlement_allocations (
  settlement_id uuid NOT NULL REFERENCES public.settlements(id) ON DELETE CASCADE,
  expense_id uuid NOT NULL REFERENCES public.expenses(id) ON DELETE CASCADE,
  amount bigint NOT NULL CHECK (amount > 0),
  PRIMARY KEY (settlement_id, expense_id)
);

GRANT SELECT ON public.settlement_allocations TO authenticated;
GRANT ALL ON public.settlement_allocations TO service_role;
ALTER TABLE public.settlement_allocations ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='settlement_allocations' AND policyname='allocation_read') THEN
    CREATE POLICY allocation_read ON public.settlement_allocations FOR SELECT TO authenticated
      USING (EXISTS (SELECT 1 FROM public.settlements s WHERE s.id = settlement_id AND public.is_trip_member(s.trip_id)));
  END IF;
END $$;

-- 8. Sync Operations
CREATE TABLE IF NOT EXISTS public.sync_operations (
  id uuid PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES public.profiles(id),
  trip_id uuid NOT NULL REFERENCES public.trips(id) ON DELETE CASCADE,
  kind text NOT NULL CHECK (kind IN ('expense', 'settlement')),
  result_id uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

GRANT SELECT ON public.sync_operations TO authenticated;
GRANT ALL ON public.sync_operations TO service_role;
ALTER TABLE public.sync_operations ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='sync_operations' AND policyname='sync_read') THEN
    CREATE POLICY sync_read ON public.sync_operations FOR SELECT TO authenticated USING (user_id = auth.uid());
  END IF;
END $$;

-- 9. RPC Functions
CREATE OR REPLACE FUNCTION public.create_trip(p jsonb)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  t uuid;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Sign in required'; END IF;
  INSERT INTO public.trips (owner_id, name, destination, start_date, end_date, budget, currency, description, cover_path)
  VALUES (auth.uid(), p->>'name', p->>'destination', (p->>'start_date')::date, (p->>'end_date')::date, (p->>'budget')::bigint, coalesce(p->>'currency', 'INR'), coalesce(p->>'description', ''), p->>'cover_path')
  RETURNING id INTO t;
  INSERT INTO public.trip_members (trip_id, user_id) VALUES (t, auth.uid());
  INSERT INTO public.trip_member_roles (trip_id, user_id, role) VALUES (t, auth.uid(), 'creator');
  RETURN t;
END;
$$;

CREATE OR REPLACE FUNCTION public.record_expense(p jsonb)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  t uuid := (p->>'trip_id')::uuid;
  eid uuid := (p->>'id')::uuid;
  a bigint := (p->>'amount')::bigint;
  c jsonb;
  existing public.expenses;
BEGIN
  IF NOT public.is_trip_member(t) THEN RAISE EXCEPTION 'Trip access denied'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(eid::text, 0));
  SELECT * INTO existing FROM public.expenses WHERE id = eid;
  IF FOUND THEN
    IF existing.created_by <> auth.uid() OR existing.trip_id <> t THEN RAISE EXCEPTION 'Operation conflict'; END IF;
    RETURN eid;
  END IF;
  IF a <= 0 OR a > 9000000000000 OR jsonb_array_length(p->'contributions') < 1 OR jsonb_array_length(p->'splits') < 1
     OR (SELECT sum((x->>'amount')::bigint) FROM jsonb_array_elements(p->'contributions') x) <> a
     OR (SELECT sum((x->>'amount')::bigint) FROM jsonb_array_elements(p->'splits') x) <> a THEN
    RAISE EXCEPTION 'Contributions and shares must equal total';
  END IF;
  FOR c IN SELECT * FROM jsonb_array_elements((p->'contributions') || (p->'splits')) LOOP
    IF NOT EXISTS (SELECT 1 FROM public.trip_members WHERE trip_id = t AND user_id = (c->>'user_id')::uuid AND status = 'active') THEN
      RAISE EXCEPTION 'All payers and beneficiaries must be trip members';
    END IF;
  END LOOP;
  INSERT INTO public.expenses (id, trip_id, created_by, title, amount, category, occurred_at, description, receipt_path)
  VALUES (eid, t, auth.uid(), p->>'title', a, p->>'category', (p->>'occurred_at')::timestamptz, coalesce(p->>'description', ''), p->>'receipt_path');
  INSERT INTO public.expense_contributions SELECT eid, (x->>'user_id')::uuid, (x->>'amount')::bigint FROM jsonb_array_elements(p->'contributions') x;
  INSERT INTO public.expense_splits SELECT eid, (x->>'user_id')::uuid, (x->>'amount')::bigint FROM jsonb_array_elements(p->'splits') x;
  INSERT INTO public.sync_operations (id, user_id, trip_id, kind, result_id) VALUES (eid, auth.uid(), t, 'expense', eid);
  RETURN eid;
END;
$$;

CREATE OR REPLACE FUNCTION public.record_settlement(p jsonb)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  t uuid := (p->>'trip_id')::uuid;
  sid uuid := (p->>'id')::uuid;
  old public.settlements;
BEGIN
  IF NOT public.is_trip_member(t) THEN RAISE EXCEPTION 'Trip access denied'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(sid::text, 0));
  SELECT * INTO old FROM public.settlements WHERE id = sid;
  IF FOUND THEN
    IF old.created_by <> auth.uid() OR old.trip_id <> t THEN RAISE EXCEPTION 'Operation conflict'; END IF;
    RETURN sid;
  END IF;
  IF (p->>'sender_id')::uuid <> auth.uid() AND NOT public.can_manage_trip(t) THEN
    RAISE EXCEPTION 'Only sender or trip administrator can record a payment';
  END IF;
  IF (SELECT count(*) FROM public.trip_members WHERE trip_id = t AND status = 'active' AND user_id IN ((p->>'sender_id')::uuid, (p->>'recipient_id')::uuid)) <> 2 THEN
    RAISE EXCEPTION 'Select two distinct trip members';
  END IF;
  INSERT INTO public.settlements (id, trip_id, created_by, sender_id, recipient_id, amount, note)
  VALUES (sid, t, auth.uid(), (p->>'sender_id')::uuid, (p->>'recipient_id')::uuid, (p->>'amount')::bigint, coalesce(p->>'note', ''));
  INSERT INTO public.sync_operations (id, user_id, trip_id, kind, result_id) VALUES (sid, auth.uid(), t, 'settlement', sid);
  RETURN sid;
END;
$$;

CREATE OR REPLACE FUNCTION public.reverse_expense(eid uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  e public.expenses;
  r uuid;
BEGIN
  SELECT * INTO e FROM public.expenses WHERE id = eid;
  IF NOT FOUND OR NOT public.is_trip_member(e.trip_id) OR (e.created_by <> auth.uid() AND NOT public.can_manage_trip(e.trip_id)) THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(eid::text, 0));
  SELECT id INTO r FROM public.expenses WHERE reversal_of = eid;
  IF FOUND THEN RETURN r; END IF;
  IF e.reversal_of IS NOT NULL THEN RAISE EXCEPTION 'Cannot reverse a reversal'; END IF;
  r := gen_random_uuid();
  INSERT INTO public.expenses (id, trip_id, created_by, title, amount, category, occurred_at, description, reversal_of)
  VALUES (r, e.trip_id, auth.uid(), 'Reversal: ' || e.title, e.amount, e.category, now(), 'Correction of original expense', eid);
  INSERT INTO public.expense_contributions SELECT r, user_id, amount FROM public.expense_contributions WHERE expense_id = eid;
  INSERT INTO public.expense_splits SELECT r, user_id, amount FROM public.expense_splits WHERE expense_id = eid;
  RETURN r;
END;
$$;

CREATE OR REPLACE FUNCTION public.create_invitation(t uuid, email_address text, hashed_token text)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  i uuid;
BEGIN
  IF NOT public.can_manage_trip(t) THEN RAISE EXCEPTION 'Only trip administrators can invite'; END IF;
  IF length(hashed_token) <> 64 THEN RAISE EXCEPTION 'Invalid invitation'; END IF;
  UPDATE public.trip_invitations SET status = 'revoked' WHERE trip_id = t AND expires_at <= now() AND status = 'pending';
  INSERT INTO public.trip_invitations (trip_id, inviter_id, recipient_email, token_hash)
  VALUES (t, auth.uid(), nullif(lower(trim(email_address)), ''), hashed_token)
  RETURNING id INTO i;
  RETURN i;
END;
$$;

CREATE OR REPLACE FUNCTION public.revoke_invitation(i uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.trip_invitations SET status = 'revoked' WHERE id = i AND status = 'pending' AND public.can_manage_trip(trip_id);
  IF NOT FOUND THEN RAISE EXCEPTION 'Invitation not available'; END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.accept_invitation(hashed_token text)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  inv public.trip_invitations;
  verified_email text;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Sign in required'; END IF;
  SELECT * INTO inv FROM public.trip_invitations WHERE token_hash = hashed_token FOR UPDATE;
  IF NOT FOUND OR inv.status = 'revoked' OR inv.expires_at <= now() THEN
    RAISE EXCEPTION 'Invitation is invalid or expired';
  END IF;
  SELECT lower(email) INTO verified_email FROM auth.users WHERE id = auth.uid() AND email_confirmed_at IS NOT NULL;
  IF verified_email IS NULL OR (inv.recipient_email IS NOT NULL AND verified_email <> inv.recipient_email) THEN
    RAISE EXCEPTION 'Sign in with the verified email this invitation was sent to';
  END IF;
  IF inv.status = 'accepted' THEN
    IF inv.accepted_by = auth.uid() THEN RETURN inv.trip_id;
    ELSE RAISE EXCEPTION 'Invitation already used';
    END IF;
  END IF;
  INSERT INTO public.trip_members (trip_id, user_id) VALUES (inv.trip_id, auth.uid()) ON CONFLICT (trip_id, user_id) DO NOTHING;
  INSERT INTO public.trip_member_roles (trip_id, user_id, role) VALUES (inv.trip_id, auth.uid(), 'participant') ON CONFLICT DO NOTHING;
  UPDATE public.trip_invitations SET status = 'accepted', accepted_by = auth.uid() WHERE id = inv.id;
  RETURN inv.trip_id;
END;
$$;

REVOKE ALL ON FUNCTION
  public.create_trip(jsonb),
  public.record_expense(jsonb),
  public.record_settlement(jsonb),
  public.reverse_expense(uuid),
  public.create_invitation(uuid, text, text),
  public.revoke_invitation(uuid),
  public.accept_invitation(text)
FROM PUBLIC;

GRANT EXECUTE ON FUNCTION
  public.create_trip(jsonb),
  public.record_expense(jsonb),
  public.record_settlement(jsonb),
  public.reverse_expense(uuid),
  public.create_invitation(uuid, text, text),
  public.revoke_invitation(uuid),
  public.accept_invitation(text)
TO authenticated;

-- 10. Storage Bucket & Policies
INSERT INTO storage.buckets (id, name, public) VALUES ('trip-files', 'trip-files', false) ON CONFLICT (id) DO NOTHING;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='objects' AND schemaname='storage' AND policyname='trip_files_upload') THEN
    CREATE POLICY trip_files_upload ON storage.objects FOR INSERT TO authenticated
      WITH CHECK (bucket_id = 'trip-files' AND (storage.foldername(name))[1] = auth.uid()::text AND public.is_trip_member(((storage.foldername(name))[2])::uuid));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='objects' AND schemaname='storage' AND policyname='trip_files_read') THEN
    CREATE POLICY trip_files_read ON storage.objects FOR SELECT TO authenticated
      USING (bucket_id = 'trip-files' AND public.is_trip_member(((storage.foldername(name))[2])::uuid));
  END IF;
END $$;

-- 11. Realtime Publication
DO $$ BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.expenses, public.settlements, public.trip_members;
EXCEPTION WHEN OTHERS THEN
  NULL;
END $$;
