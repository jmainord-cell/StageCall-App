-- ---------------------------------------------------------------
-- 004: Musicians board, and keep responded-to gigs visible.
--
-- For a database that already ran 003. A fresh setup gets the same
-- result from schema.sql and policies.sql, so it doesn't need this.
--
-- 1. Musicians board: collab_posts, collab_responses, the collab_cards
--    view, collab_posts_in_reach(), their rules, team_up() and
--    undo_team_up().
-- 2. An artist can still see a gig they applied to after it's filled
--    (before, a booked artist lost sight of their own gig).
-- ---------------------------------------------------------------
begin;

-- ---------------------------------------------------------------
-- Musicians board: artists looking for other artists (a band needs a
-- singer, a solo act needs a backing band). Others tap "I'm interested";
-- the poster picks one with Team up, or passes.
-- ---------------------------------------------------------------
create type collab_purpose as enum ('Fill-in for a show', 'Opening act', 'Backing band', 'Join my act', 'Jam / session');

-- Where the post is comes from the poster's artist row (town, lat, lng).
create table collab_posts (
  id          uuid primary key default gen_random_uuid(),
  artist_id   uuid not null references artists (id) on delete cascade,  -- who posted
  wants       act_type not null,                                        -- who they're looking for
  purpose     collab_purpose not null,
  when_text   text not null check (length(when_text) between 1 and 40),  -- 'Sat', 'Flexible', 'Ongoing'
  pay_text    text not null check (length(pay_text) between 1 and 40),   -- '$150', 'Split the door', 'Unpaid'
  genre       text,                                                     -- null means "Any"
  reach       reach_level not null default 'Region',                    -- "Draw from"
  note        text check (length(note) <= 500),
  status      gig_status not null default 'open',                       -- open / filled (teamed up) / cancelled
  created_at  timestamptz not null default now()
);
create index collab_posts_open_idx on collab_posts (created_at desc) where status = 'open';
create index collab_posts_artist_idx on collab_posts (artist_id);

-- "I'm interested". Same statuses as applications:
-- applied (interested) / withdrawn (took it back) / accepted (teamed up) / declined (passed).
create table collab_responses (
  post_id     uuid not null references collab_posts (id) on delete cascade,
  artist_id   uuid not null references artists (id) on delete cascade,  -- who's interested
  status      application_status not null default 'applied',
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  primary key (post_id, artist_id)
);
create index collab_responses_artist_idx on collab_responses (artist_id);

-- Post cards for the board, with the poster's name and place.
create view collab_cards with (security_invoker = true) as
select p.*,
       a.name      as poster_name,
       a.act_type  as poster_act_type,
       a.genres    as poster_genres,
       a.town      as poster_town,
       a.lat       as poster_lat,
       a.lng       as poster_lng,
       (select count(*) from collab_responses r
         where r.post_id = p.id and r.status = 'applied') as interested_count
from collab_posts p
join artists a on a.id = p.artist_id;

-- The board for an artist: open posts by others, within the distance the
-- artist chose AND the distance the poster chose, nearest first.
create function collab_posts_in_reach(p_artist_id uuid,
                                      p_range reach_level default 'Region',
                                      p_wants act_type default null)
returns table (post_id uuid, poster_id uuid, poster_name text, poster_act_type act_type,
               poster_genres text[], poster_town text, wants act_type,
               purpose collab_purpose, when_text text, pay_text text, genre text,
               note text, miles double precision)
language sql stable security invoker set search_path = public as $$
  select c.id, c.artist_id, c.poster_name, c.poster_act_type, c.poster_genres, c.poster_town,
         c.wants, c.purpose, c.when_text, c.pay_text, c.genre, c.note, d.miles
  from collab_cards c
  cross join artists me
  cross join lateral (select miles_between(me.lat, me.lng, c.poster_lat, c.poster_lng) as miles) d
  where me.id = p_artist_id
    and c.artist_id <> me.id
    and c.status = 'open'
    and (p_wants is null or c.wants = p_wants)
    and (reach_miles(p_range) is null or d.miles <= reach_miles(p_range))
    and (reach_miles(c.reach) is null or d.miles <= reach_miles(c.reach))
  order by d.miles, c.created_at desc
$$;

-- True if the caller (as one of their acts) applied to this gig, so they
-- can still see it once it's filled or cancelled.
create function private.applied_to_gig(p_gig_id uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from applications x join artists a on a.id = x.artist_id
                 where x.gig_id = p_gig_id and a.owner_id = auth.uid())
$$;

drop policy "open gigs are public" on gigs;
-- Open gigs are public; a venue also sees its own filled/cancelled gigs,
-- and an artist still sees a gig they applied to (booked or not).
create policy "open gigs are public"  on gigs for select
  using (status = 'open' or private.owns_venue(venue_id) or private.applied_to_gig(id));

-- ---------------------------------------------------------------
-- Musicians board rules. They mirror gigs and applications:
-- open posts are public; the poster manages their post and teams up or
-- passes; the responder says "I'm interested" or takes it back.
-- ---------------------------------------------------------------
create function private.owns_collab_post(p_post_id uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from collab_posts p join artists a on a.id = p.artist_id
                 where p.id = p_post_id and a.owner_id = auth.uid())
$$;

-- True if the caller (as one of their acts) replied to this post.
create function private.replied_to_post(p_post_id uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from collab_responses r join artists a on a.id = r.artist_id
                 where r.post_id = p_post_id and a.owner_id = auth.uid())
$$;

-- Same one-step status changes as applications:
--   responder: applied -> withdrawn, withdrawn -> applied
--   poster:    applied -> accepted / declined, declined -> applied (undo
--              pass), accepted -> applied (undo team-up)
create function private.check_response_update() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  step text;
begin
  if auth.uid() is null then
    return new;
  end if;
  if new.post_id <> old.post_id or new.artist_id <> old.artist_id then
    raise exception 'A response cannot be moved to another post or artist';
  end if;
  if new.status <> old.status then
    step := old.status || '>' || new.status;
    if private.owns_artist(new.artist_id) and step in ('applied>withdrawn', 'withdrawn>applied') then
      null;  -- take it back / interested again
    elsif private.owns_collab_post(new.post_id)
          and step in ('applied>accepted', 'applied>declined', 'declined>applied', 'accepted>applied') then
      null;  -- team up / pass / undo pass / undo team-up
    elsif step in ('applied>withdrawn', 'withdrawn>applied') then
      raise exception 'Only the musician who replied can take it back';
    elsif step in ('applied>accepted', 'applied>declined', 'declined>applied', 'accepted>applied') then
      raise exception 'Only the poster can team up, pass or undo';
    else
      raise exception 'A response cannot go from % to %', old.status, new.status;
    end if;
  end if;
  new.updated_at := now();
  return new;
end $$;

create trigger response_update_rules
  before update on collab_responses
  for each row execute function private.check_response_update();

revoke execute on function private.check_response_update() from public, anon, authenticated;

alter table collab_posts     enable row level security;
alter table collab_responses enable row level security;

-- Open posts are public; the poster also sees their own filled/cancelled
-- posts, and a musician still sees a post they replied to.
create policy "open posts are public" on collab_posts for select
  using (status = 'open' or private.owns_artist(artist_id) or private.replied_to_post(id));
create policy "manage own posts"      on collab_posts for all
  using (private.owns_artist(artist_id)) with check (private.owns_artist(artist_id));

-- Only the two sides see a response.
create policy "see own responses"     on collab_responses for select
  using (private.owns_artist(artist_id) or private.owns_collab_post(post_id));
-- Reply as your own act, to someone else's open post.
create policy "reply to open posts"   on collab_responses for insert
  with check (private.owns_artist(artist_id)
              and exists (select 1 from collab_posts p
                          where p.id = post_id and p.status = 'open' and p.artist_id <> collab_responses.artist_id));
create policy "either side updates"   on collab_responses for update
  using (private.owns_artist(artist_id) or private.owns_collab_post(post_id))
  with check (private.owns_artist(artist_id) or private.owns_collab_post(post_id));

-- Team up in one step, and undo it (same idea as book_artist / cancel_booking).
--   sb.rpc('team_up', { p_post_id, p_artist_id })
--   sb.rpc('undo_team_up', { p_post_id })
create function team_up(p_post_id uuid, p_artist_id uuid) returns void
language plpgsql security invoker set search_path = public as $$
begin
  if not private.owns_collab_post(p_post_id) then
    raise exception 'Only the musician who posted this can team up';
  end if;
  perform 1 from collab_posts where id = p_post_id and status = 'open' for update;
  if not found then
    raise exception 'This post is not open';
  end if;
  update collab_responses set status = 'accepted'
    where post_id = p_post_id and artist_id = p_artist_id and status = 'applied';
  if not found then
    raise exception 'This musician has no open reply on this post';
  end if;
  update collab_posts set status = 'filled' where id = p_post_id;
end $$;

create function undo_team_up(p_post_id uuid) returns void
language plpgsql security invoker set search_path = public as $$
begin
  if not private.owns_collab_post(p_post_id) then
    raise exception 'Only the musician who posted this can undo the team-up';
  end if;
  perform 1 from collab_posts where id = p_post_id and status = 'filled' for update;
  if not found then
    raise exception 'This post has no team-up to undo';
  end if;
  update collab_responses set status = 'applied' where post_id = p_post_id and status = 'accepted';
  update collab_posts set status = 'open' where id = p_post_id;
end $$;

revoke execute on function team_up(uuid, uuid) from public, anon;
revoke execute on function undo_team_up(uuid) from public, anon;
grant execute on function team_up(uuid, uuid) to authenticated;
grant execute on function undo_team_up(uuid) to authenticated;

commit;
