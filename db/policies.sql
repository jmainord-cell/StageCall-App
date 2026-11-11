-- ---------------------------------------------------------------
-- Stagecall row-level security (Supabase)
--
-- The app talks to the database straight from the browser with the public
-- "anon" key, so these policies are the only thing stopping one user from
-- editing another user's data. Every table has RLS turned on; anything not
-- explicitly allowed below is denied.
--
-- Run after schema.sql.
-- ---------------------------------------------------------------

-- ---------------------------------------------------------------
-- Helper functions live in a "private" schema. Supabase's API only
-- exposes "public", so nobody can call these directly from the browser;
-- the policies below can still use them.
-- ---------------------------------------------------------------
create schema if not exists private;
grant usage on schema private to anon, authenticated;

-- ---------------------------------------------------------------
-- Ownership helpers. security definer so they can look up ownership
-- without tripping the policies of the table they read.
-- ---------------------------------------------------------------
create function private.owns_artist(p_artist_id uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from artists where id = p_artist_id and owner_id = auth.uid())
$$;

create function private.owns_venue(p_venue_id uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from venues where id = p_venue_id and owner_id = auth.uid())
$$;

create function private.owns_gig(p_gig_id uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from gigs g join venues v on v.id = g.venue_id
                 where g.id = p_gig_id and v.owner_id = auth.uid())
$$;

create function private.in_conversation(p_conversation_id uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from conversation_members
                 where conversation_id = p_conversation_id and profile_id = auth.uid())
$$;

create function private.started_conversation(p_conversation_id uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from conversations
                 where id = p_conversation_id and created_by = auth.uid())
$$;

-- ---------------------------------------------------------------
-- Policies can't limit which values a user writes, so this trigger does:
-- the artist may only apply or withdraw, the venue may only accept or
-- decline, and nobody can move an application to another gig or artist.
-- auth.uid() is null for admin/service-role writes, which skip the check.
-- ---------------------------------------------------------------
create function private.check_application_update() returns trigger
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

create trigger application_update_rules
  before update on applications
  for each row execute function private.check_application_update();

-- ---------------------------------------------------------------
-- Create a profile automatically when someone signs up.
-- The sign-up form can pass { role, display_name } as user metadata.
-- ---------------------------------------------------------------
create function private.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into profiles (id, role, display_name)
  values (new.id,
          coalesce((new.raw_user_meta_data ->> 'role')::user_role, 'fan'),
          coalesce(new.raw_user_meta_data ->> 'display_name', ''))
  on conflict (id) do nothing;
  return new;
end $$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function private.handle_new_user();

-- Trigger functions run on their own; no one needs to call them by hand.
revoke execute on function private.check_application_update() from public, anon, authenticated;
revoke execute on function private.handle_new_user() from public, anon, authenticated;

-- ---------------------------------------------------------------
-- Turn RLS on everywhere
-- ---------------------------------------------------------------
alter table profiles             enable row level security;
alter table artists              enable row level security;
alter table venues               enable row level security;
alter table social_links         enable row level security;
alter table gigs                 enable row level security;
alter table applications         enable row level security;
alter table invitations          enable row level security;
alter table bookings             enable row level security;
alter table media                enable row level security;
alter table likes                enable row level security;
alter table follows              enable row level security;
alter table saved_venues         enable row level security;
alter table conversations        enable row level security;
alter table conversation_members enable row level security;
alter table messages             enable row level security;

-- ---------------------------------------------------------------
-- Public browsing: anyone can see profiles, acts, venues, socials,
-- open gigs and media. Only the owner can change them.
-- ---------------------------------------------------------------
create policy "profiles are public"   on profiles for select using (true);
create policy "edit own profile"      on profiles for update using (id = auth.uid()) with check (id = auth.uid());

create policy "artists are public"    on artists for select using (true);
create policy "manage own artists"    on artists for all
  using (owner_id = auth.uid()) with check (owner_id = auth.uid());

create policy "venues are public"     on venues for select using (true);
create policy "manage own venues"     on venues for all
  using (owner_id = auth.uid()) with check (owner_id = auth.uid());

create policy "socials are public"    on social_links for select using (true);
create policy "manage own socials"    on social_links for all
  using (private.owns_artist(artist_id)) with check (private.owns_artist(artist_id));

create policy "media is public"       on media for select using (true);
create policy "manage own media"      on media for all
  using (private.owns_artist(artist_id) or private.owns_venue(venue_id))
  with check (private.owns_artist(artist_id) or private.owns_venue(venue_id));

-- Open gigs are public; a venue also sees its own filled/cancelled gigs.
create policy "open gigs are public"  on gigs for select using (status = 'open' or private.owns_venue(venue_id));
create policy "manage own gigs"       on gigs for all
  using (private.owns_venue(venue_id)) with check (private.owns_venue(venue_id));

-- ---------------------------------------------------------------
-- Hiring flow: only the two sides of a deal can see it.
-- ---------------------------------------------------------------
create policy "see own applications"  on applications for select
  using (private.owns_artist(artist_id) or private.owns_gig(gig_id));
create policy "artist applies"        on applications for insert
  with check (private.owns_artist(artist_id));
-- Artist withdraws; venue accepts or declines.
create policy "either side updates"   on applications for update
  using (private.owns_artist(artist_id) or private.owns_gig(gig_id))
  with check (private.owns_artist(artist_id) or private.owns_gig(gig_id));

create policy "see own invitations"   on invitations for select
  using (private.owns_venue(venue_id) or private.owns_artist(artist_id));
create policy "venue invites"         on invitations for insert
  with check (private.owns_venue(venue_id));
create policy "either side updates"   on invitations for update
  using (private.owns_venue(venue_id) or private.owns_artist(artist_id))
  with check (private.owns_venue(venue_id) or private.owns_artist(artist_id));

create policy "see own bookings"      on bookings for select
  using (private.owns_gig(gig_id) or private.owns_artist(artist_id));
create policy "venue books"           on bookings for insert
  with check (private.owns_gig(gig_id));
create policy "venue updates booking" on bookings for update
  using (private.owns_gig(gig_id)) with check (private.owns_gig(gig_id));

-- ---------------------------------------------------------------
-- Personal lists: likes, follows, saved venues
-- ---------------------------------------------------------------
create policy "own likes"        on likes        for all using (profile_id = auth.uid()) with check (profile_id = auth.uid());
create policy "own follows"      on follows      for all using (profile_id = auth.uid()) with check (profile_id = auth.uid());
create policy "own saved venues" on saved_venues for all using (profile_id = auth.uid()) with check (profile_id = auth.uid());

-- ---------------------------------------------------------------
-- Messaging: members only
-- ---------------------------------------------------------------
create policy "members see conversation" on conversations for select
  using (created_by = auth.uid() or private.in_conversation(id));
create policy "start as self"         on conversations for insert with check (created_by = auth.uid());

create policy "members see members"   on conversation_members for select using (private.in_conversation(conversation_id));
-- The person who started a conversation, or anyone already in it, can add people.
create policy "members add members"   on conversation_members for insert
  with check (private.started_conversation(conversation_id) or private.in_conversation(conversation_id));

create policy "members read messages" on messages for select using (private.in_conversation(conversation_id));
create policy "members send as self"  on messages for insert
  with check (sender_id = auth.uid() and private.in_conversation(conversation_id));

-- ---------------------------------------------------------------
-- Live shows on the map: booked gigs that anyone can see.
-- Bookings are private (pay, deposit, payment status), so a security
-- definer function in the private schema reads them and returns only
-- what a flyer would show. The public view on top is what the app reads:
--   sb.from('live_shows').select('*')
-- A show stays listed until 4 hours after it starts, so tonight's show
-- is still "live" while it's on.
-- ---------------------------------------------------------------
create function private.live_shows()
returns table (gig_id uuid, starts_at timestamptz, act_type act_type,
               venue_id uuid, venue_name text, venue_town text,
               venue_lat double precision, venue_lng double precision,
               artist_id uuid, artist_name text)
language sql stable security definer set search_path = public as $$
  select g.id, g.starts_at, g.act_type,
         v.id, v.name, v.town, v.lat, v.lng,
         a.id, a.name
  from bookings b
  join gigs g    on g.id = b.gig_id
  join venues v  on v.id = g.venue_id
  join artists a on a.id = b.artist_id
  where g.status = 'filled'
    and g.starts_at > now() - interval '4 hours'
  order by g.starts_at
$$;
revoke execute on function private.live_shows() from public;
grant execute on function private.live_shows() to anon, authenticated;

create view live_shows with (security_invoker = true) as
  select * from private.live_shows();
grant select on live_shows to anon, authenticated;
