-- ---------------------------------------------------------------
-- 005: "My events" (upcoming bookings, past events, pending
-- applications) for the signed-in user.
--
-- For a database that already ran 004. A fresh setup gets the same
-- result from policies.sql, so it doesn't need this.
-- ---------------------------------------------------------------
begin;

-- ---------------------------------------------------------------
-- "My events" on the Profile tab, for whoever is signed in:
--   kind = 'booking'      a booked show (side 'artist': you play it;
--                         side 'venue': it's at your venue).
--                         is_past splits Upcoming from Past events.
--   kind = 'application'  artist: you applied, the gig is still open.
--   kind = 'open_gig'     venue: your open gig, with its applicant count.
-- Runs with the caller's own permissions, so it only ever returns the
-- caller's rows.   sb.rpc('my_events')
-- ---------------------------------------------------------------
create function my_events()
returns table (kind text, side text, gig_id uuid, starts_at timestamptz, is_past boolean,
               act_type act_type, venue_id uuid, venue_name text, venue_town text,
               artist_id uuid, artist_name text, pay_cents integer, applicant_count integer)
language sql stable security invoker set search_path = public as $$
  -- bookings where I'm the artist
  select 'booking', 'artist', g.id, g.starts_at, g.starts_at < now(), g.act_type,
         v.id, v.name, v.town, a.id, a.name, b.agreed_pay_cents, null::integer
  from bookings b
  join gigs g    on g.id = b.gig_id
  join venues v  on v.id = g.venue_id
  join artists a on a.id = b.artist_id
  where a.owner_id = auth.uid()
  union all
  -- bookings at my venues
  select 'booking', 'venue', g.id, g.starts_at, g.starts_at < now(), g.act_type,
         v.id, v.name, v.town, a.id, a.name, b.agreed_pay_cents, null
  from bookings b
  join gigs g    on g.id = b.gig_id
  join venues v  on v.id = g.venue_id
  join artists a on a.id = b.artist_id
  where v.owner_id = auth.uid()
  union all
  -- my applications that are still waiting
  select 'application', 'artist', g.id, g.starts_at, false, g.act_type,
         v.id, v.name, v.town, a.id, a.name, g.pay_cents, null
  from applications x
  join gigs g    on g.id = x.gig_id
  join venues v  on v.id = g.venue_id
  join artists a on a.id = x.artist_id
  where a.owner_id = auth.uid() and x.status = 'applied'
    and g.status = 'open' and g.starts_at > now()
  union all
  -- my open gigs
  select 'open_gig', 'venue', c.id, c.starts_at, false, c.act_type,
         c.venue_id, c.venue_name, c.venue_town, null, null, c.pay_cents, c.applicant_count::integer
  from gig_cards c
  join venues v on v.id = c.venue_id
  where v.owner_id = auth.uid() and c.status = 'open' and c.starts_at > now()
  order by 4
$$;
revoke execute on function my_events() from public, anon;
grant execute on function my_events() to authenticated;

commit;
