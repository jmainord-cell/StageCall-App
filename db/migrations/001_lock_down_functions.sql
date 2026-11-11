-- ---------------------------------------------------------------
-- 001: lock down helper functions (fixes the 17 Supabase security
-- advisor warnings).
--
-- For a database that already ran the earlier schema.sql and
-- policies.sql. A fresh setup gets the same result from those two
-- files, so it doesn't need this.
--
-- 1. The ownership helpers and trigger functions move from "public"
--    (exposed by the API) to "private" (not exposed). Policies and
--    triggers point at functions by id, so they keep working.
-- 2. The trigger functions can no longer be called by hand.
-- 3. The distance functions get a fixed search_path.
-- ---------------------------------------------------------------
begin;

create schema if not exists private;
grant usage on schema private to anon, authenticated;

alter function public.owns_artist(uuid)          set schema private;
alter function public.owns_venue(uuid)           set schema private;
alter function public.owns_gig(uuid)             set schema private;
alter function public.in_conversation(uuid)      set schema private;
alter function public.started_conversation(uuid) set schema private;
alter function public.check_application_update() set schema private;
alter function public.handle_new_user()          set schema private;

-- Its body calls the helpers by name, so it must use their new home.
create or replace function private.check_application_update() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then
    return new;
  end if;
  if new.gig_id <> old.gig_id or new.artist_id <> old.artist_id then
    raise exception 'An application cannot be moved to another gig or artist';
  end if;
  if new.status in ('applied', 'withdrawn') and not private.owns_artist(new.artist_id) then
    raise exception 'Only the artist can apply or withdraw';
  end if;
  if new.status in ('accepted', 'declined') and not private.owns_gig(new.gig_id) then
    raise exception 'Only the venue can accept or decline';
  end if;
  new.updated_at := now();
  return new;
end $$;

revoke execute on function private.check_application_update() from public, anon, authenticated;
revoke execute on function private.handle_new_user() from public, anon, authenticated;

alter function public.reach_miles(reach_level) set search_path = '';
alter function public.miles_between(double precision, double precision, double precision, double precision) set search_path = '';
alter function public.gigs_in_reach(uuid, reach_level, act_type) set search_path = public;

commit;
