-- ---------------------------------------------------------------
-- 002: public live shows for the map.
--
-- For a database that already ran 001. A fresh setup gets the same
-- result from policies.sql, so it doesn't need this.
-- ---------------------------------------------------------------
begin;

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

commit;
