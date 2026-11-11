-- ---------------------------------------------------------------
-- Stagecall database schema (PostgreSQL / Supabase)
--
-- Run order: schema.sql -> policies.sql -> seed.sql (optional sample data)
--
-- Enum values match the strings index.html already uses
-- ('DJ', 'Band', 'Town', 'Region', ...), so the app can read and write
-- them without a translation layer.
-- ---------------------------------------------------------------

-- ---------------------------------------------------------------
-- Types
-- ---------------------------------------------------------------
create type user_role   as enum ('artist', 'venue', 'fan');
create type act_type    as enum ('DJ', 'Band', 'Solo', 'Singer');
create type reach_level as enum ('Town', 'Region', 'Statewide');
create type travel_help as enum ('None', 'Gas', 'Gas + room', 'Lodging');
create type gig_status  as enum ('open', 'filled', 'cancelled', 'completed');
create type application_status as enum ('applied', 'withdrawn', 'accepted', 'declined');
create type invitation_status  as enum ('sent', 'accepted', 'declined');
create type payment_status     as enum ('unpaid', 'deposit_paid', 'paid', 'refunded');
create type media_kind  as enum ('video', 'audio', 'photo');
create type social_platform as enum ('instagram', 'youtube', 'spotify', 'soundcloud');

-- ---------------------------------------------------------------
-- Accounts
-- One row per signed-in person. id is the Supabase auth user id.
-- ---------------------------------------------------------------
create table profiles (
  id           uuid primary key references auth.users (id) on delete cascade,
  role         user_role not null default 'fan',
  display_name text not null default '',
  avatar_url   text,
  created_at   timestamptz not null default now()
);

-- ---------------------------------------------------------------
-- Artists and venues
-- Owned by a profile. One account can run more than one act or venue.
-- lat/lng drive the "how far will you go" distance filters.
-- ---------------------------------------------------------------
create table artists (
  id           uuid primary key default gen_random_uuid(),
  owner_id     uuid not null references profiles (id) on delete cascade,
  name         text not null,
  act_type     act_type not null,
  genres       text[] not null default '{}',
  bio          text,
  open_to_gigs boolean not null default true,
  town         text,
  state        text,
  lat          double precision check (lat between -90 and 90),
  lng          double precision check (lng between -180 and 180),
  created_at   timestamptz not null default now()
);

create table venues (
  id          uuid primary key default gen_random_uuid(),
  owner_id    uuid not null references profiles (id) on delete cascade,
  name        text not null,
  kind        text,                                   -- e.g. 'Bar with a small stage'
  about       text,
  equipment   text[] not null default '{}',           -- 'Stage', 'PA system', 'Backline', 'DJ booth'
  books       act_type[] not null default '{}',       -- what the venue hires
  town        text,
  state       text,
  lat         double precision check (lat between -90 and 90),
  lng         double precision check (lng between -180 and 180),
  created_at  timestamptz not null default now()
);

create table social_links (
  artist_id  uuid not null references artists (id) on delete cascade,
  platform   social_platform not null,
  url        text not null,
  primary key (artist_id, platform)
);

-- ---------------------------------------------------------------
-- Gigs and the hiring flow
-- ---------------------------------------------------------------
create table gigs (
  id          uuid primary key default gen_random_uuid(),
  venue_id    uuid not null references venues (id) on delete cascade,
  act_type    act_type not null,
  starts_at   timestamptz not null,
  pay_cents   integer not null check (pay_cents >= 0),
  genre       text,                                   -- null means "Any"
  reach       reach_level not null default 'Region',  -- "Draw artists from"
  travel      travel_help not null default 'None',
  notes       text,
  status      gig_status not null default 'open',
  created_at  timestamptz not null default now()
);
create index gigs_open_idx on gigs (starts_at) where status = 'open';
create index gigs_venue_idx on gigs (venue_id);

-- An artist applies to a gig. Withdrawing sets status rather than deleting,
-- so the venue's history stays intact.
create table applications (
  id          uuid primary key default gen_random_uuid(),
  gig_id      uuid not null references gigs (id) on delete cascade,
  artist_id   uuid not null references artists (id) on delete cascade,
  status      application_status not null default 'applied',
  message     text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (gig_id, artist_id)
);
create index applications_artist_idx on applications (artist_id);

-- A venue invites an artist, optionally to a specific gig ("Invite to a gig" on Reels).
create table invitations (
  id          uuid primary key default gen_random_uuid(),
  venue_id    uuid not null references venues (id) on delete cascade,
  artist_id   uuid not null references artists (id) on delete cascade,
  gig_id      uuid references gigs (id) on delete set null,
  status      invitation_status not null default 'sent',
  created_at  timestamptz not null default now()
);
create index invitations_artist_idx on invitations (artist_id);

-- The confirmed artist for a gig. Card details never live here; a payment
-- provider (e.g. Stripe) holds them and we keep only its reference id.
create table bookings (
  id                  uuid primary key default gen_random_uuid(),
  gig_id              uuid not null unique references gigs (id) on delete cascade,
  artist_id           uuid not null references artists (id) on delete restrict,
  agreed_pay_cents    integer not null check (agreed_pay_cents >= 0),
  deposit_cents       integer not null default 0 check (deposit_cents >= 0),
  payment_status      payment_status not null default 'unpaid',
  payment_provider_ref text,
  created_at          timestamptz not null default now()
);

-- ---------------------------------------------------------------
-- Media and the Reels feed
-- Files live in Supabase Storage; storage_path points at the file.
-- Each item belongs to exactly one artist or one venue.
-- ---------------------------------------------------------------
create table media (
  id           uuid primary key default gen_random_uuid(),
  artist_id    uuid references artists (id) on delete cascade,
  venue_id     uuid references venues (id) on delete cascade,
  kind         media_kind not null,
  title        text,
  caption      text,
  storage_path text not null,
  in_reels     boolean not null default false,
  created_at   timestamptz not null default now(),
  check ((artist_id is null) <> (venue_id is null))
);
create index media_reels_idx on media (created_at desc) where in_reels;

create table likes (
  profile_id uuid not null references profiles (id) on delete cascade,
  media_id   uuid not null references media (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (profile_id, media_id)
);

-- "Follow" an artist
create table follows (
  profile_id uuid not null references profiles (id) on delete cascade,
  artist_id  uuid not null references artists (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (profile_id, artist_id)
);

-- "Save venue"
create table saved_venues (
  profile_id uuid not null references profiles (id) on delete cascade,
  venue_id   uuid not null references venues (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (profile_id, venue_id)
);

-- ---------------------------------------------------------------
-- Messaging (not in the prototype UI yet)
-- ---------------------------------------------------------------
create table conversations (
  id         uuid primary key default gen_random_uuid(),
  created_by uuid not null references profiles (id) on delete cascade,
  gig_id     uuid references gigs (id) on delete set null,
  created_at timestamptz not null default now()
);

create table conversation_members (
  conversation_id uuid not null references conversations (id) on delete cascade,
  profile_id      uuid not null references profiles (id) on delete cascade,
  primary key (conversation_id, profile_id)
);

create table messages (
  id              uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references conversations (id) on delete cascade,
  sender_id       uuid not null references profiles (id) on delete cascade,
  body            text not null check (length(body) between 1 and 4000),
  created_at      timestamptz not null default now()
);
create index messages_conversation_idx on messages (conversation_id, created_at);

-- ---------------------------------------------------------------
-- Distance helpers
-- ---------------------------------------------------------------

-- Same numbers as RANGE_MILES in index.html. null = no limit (Statewide).
create function reach_miles(r reach_level) returns double precision
language sql immutable set search_path = '' as $$
  select case r when 'Town' then 15 when 'Region' then 75 else null end::double precision
$$;

-- Great-circle distance in miles (haversine).
create function miles_between(lat1 double precision, lng1 double precision,
                              lat2 double precision, lng2 double precision)
returns double precision
language sql immutable set search_path = '' as $$
  select 2 * 3958.8 * asin(sqrt(
    power(sin(radians(lat2 - lat1) / 2), 2) +
    cos(radians(lat1)) * cos(radians(lat2)) * power(sin(radians(lng2 - lng1) / 2), 2)
  ))
$$;

-- Gig cards for the venue's "Your open gigs" list and anywhere else a gig is shown.
-- security_invoker makes the view respect the caller's row-level security.
create view gig_cards with (security_invoker = true) as
select g.*,
       v.name  as venue_name,
       v.town  as venue_town,
       v.lat   as venue_lat,
       v.lng   as venue_lng,
       (select count(*) from applications a
         where a.gig_id = g.id and a.status = 'applied') as applicant_count
from gigs g
join venues v on v.id = g.venue_id;

-- "Gigs in reach" for an artist. A gig shows when it is within the distance
-- the artist chose AND within the distance the venue chose to draw from.
create function gigs_in_reach(p_artist_id uuid,
                              p_range reach_level default 'Region',
                              p_act act_type default null)
returns table (gig_id uuid, venue_name text, venue_town text, act_type act_type,
               starts_at timestamptz, pay_cents integer, genre text,
               travel travel_help, miles double precision)
language sql stable security invoker set search_path = public as $$
  select c.id, c.venue_name, c.venue_town, c.act_type, c.starts_at, c.pay_cents,
         c.genre, c.travel, d.miles
  from gig_cards c
  cross join artists a
  cross join lateral (select miles_between(a.lat, a.lng, c.venue_lat, c.venue_lng) as miles) d
  where a.id = p_artist_id
    and c.status = 'open'
    and c.starts_at > now()
    and (p_act is null or c.act_type = p_act)
    and (reach_miles(p_range) is null or d.miles <= reach_miles(p_range))
    and (reach_miles(c.reach) is null or d.miles <= reach_miles(c.reach))
  order by d.miles, c.starts_at
$$;

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
