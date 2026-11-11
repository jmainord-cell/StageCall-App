-- ---------------------------------------------------------------
-- Refresh the sample gig dates before a demo.
--
-- seed.sql dates the 10 sample gigs relative to the day it ran ("Fri" =
-- next Friday, "Tonight" = today). After a few days some are in the past:
-- open gigs drop out of "Gigs near you" and live shows drop off the map.
-- This moves them forward again with the same rules as seed.sql. It only
-- changes starts_at on the 10 sample gigs; nothing else is touched.
--
--   supabase db query --remote=<project ref> --file db/refresh_sample_dates.sql --yes
--
-- Keep the day/time list in step with seed.sql (test.mjs checks this).
-- ---------------------------------------------------------------

-- Next given weekday (1 = Mon ... 7 = Sun) strictly after today, Arkansas time.
create or replace function pg_temp.next_day(p_isodow int) returns date
language sql stable as $$
  select (now() at time zone 'America/Chicago')::date
       + ((p_isodow - extract(isodow from (now() at time zone 'America/Chicago'))::int + 6) % 7 + 1)
$$;
create or replace function pg_temp.at_local(p_day date, p_time time) returns timestamptz
language sql stable as $$ select (p_day + p_time) at time zone 'America/Chicago' $$;

update gigs g set starts_at = pg_temp.at_local(coalesce(pg_temp.next_day(d.isodow), (now() at time zone 'America/Chicago')::date), d.at)
from (values
  ('30000000-0000-0000-0000-000000000001'::uuid, 5,    time '20:00'),  -- The Corner Stage, Fri 8 PM
  ('30000000-0000-0000-0000-000000000002'::uuid, null, time '21:00'),  -- The Rusty Anchor, tonight 9 PM
  ('30000000-0000-0000-0000-000000000003'::uuid, 5,    time '22:00'),  -- Velvet Room, Fri 10 PM
  ('30000000-0000-0000-0000-000000000004'::uuid, 6,    time '19:00'),  -- Café Lune, Sat 7 PM
  ('30000000-0000-0000-0000-000000000005'::uuid, 6,    time '20:00'),  -- Harbor House, Sat 8 PM
  ('30000000-0000-0000-0000-000000000006'::uuid, 7,    time '16:00'),  -- Brick & Barrel, Sun 4 PM
  ('30000000-0000-0000-0000-000000000007'::uuid, 6,    time '21:00'),  -- The Grain Elevator, Sat 9 PM
  ('30000000-0000-0000-0000-000000000008'::uuid, 5,    time '18:00'),  -- Lakeside Lodge, Fri 6 PM
  ('30000000-0000-0000-0000-000000000009'::uuid, 6,    time '22:00'),  -- Depot Taproom, Sat 10 PM
  ('30000000-0000-0000-0000-000000000010'::uuid, 7,    time '14:00')   -- County Fair Stage, Sun 2 PM
) as d(id, isodow, at)
where g.id = d.id;
