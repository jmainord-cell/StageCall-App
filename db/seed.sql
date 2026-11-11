-- ---------------------------------------------------------------
-- Stagecall sample data: the same gigs, venues, artists, live shows and
-- reels the prototype shows in index.html. The places are real Arkansas
-- towns (home is Fayetteville, the same HOME as index.html); the venue
-- and artist names are fictional.
--
-- Gig dates are relative to the day you load this file, on Arkansas
-- time: "Fri" means the next Friday after today, "Tonight" means today.
--
-- Sample accounts have no password and cannot sign in. They exist only to
-- own the sample rows. Run after schema.sql and policies.sql; the sign-up
-- trigger creates each profile from its metadata.
-- ---------------------------------------------------------------

-- Next given weekday (1 = Mon ... 7 = Sun) strictly after today, Arkansas time.
-- pg_temp: exists only while this file runs.
create or replace function pg_temp.next_day(p_isodow int) returns date
language sql stable as $$
  select (now() at time zone 'America/Chicago')::date
       + ((p_isodow - extract(isodow from (now() at time zone 'America/Chicago'))::int + 6) % 7 + 1)
$$;
create or replace function pg_temp.at_local(p_day date, p_time time) returns timestamptz
language sql stable as $$ select (p_day + p_time) at time zone 'America/Chicago' $$;

insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-000000000001', 'corner-stage@example.com',  '{"role":"venue","display_name":"The Corner Stage"}'),
  ('00000000-0000-0000-0000-000000000002', 'sample-venues@example.com', '{"role":"venue","display_name":"Sample venues"}'),
  ('00000000-0000-0000-0000-000000000011', 'mara-voss@example.com',     '{"role":"artist","display_name":"Mara Voss"}'),
  ('00000000-0000-0000-0000-000000000012', 'sample-artists@example.com','{"role":"artist","display_name":"Sample artists"}');

-- ---------------------------------------------------------------
-- Venues (miles are from home in Fayetteville, 36.0626, -94.1574)
-- ---------------------------------------------------------------
insert into venues (id, owner_id, name, kind, about, equipment, books, town, state, lat, lng) values
  ('10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'The Corner Stage', 'Live room & bar',
     'The vibe, the crowd, what nights you book.', '{Stage,"PA system",Backline,"DJ booth"}', '{DJ,Band,Solo,Singer}', 'Fayetteville', 'AR', 36.0660, -94.1608),   -- 0.3 mi
  ('10000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000002', 'The Rusty Anchor', 'Bar with a small stage',
     'Stage and PA provided. Bands Thursday to Saturday.', '{Stage,"PA system"}', '{Band}', 'Fayetteville', 'AR', 36.0768, -94.1612),                                -- 1.0 mi
  ('10000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000002', 'Velvet Room', 'Club · DJ booth',
     'Late nights, dance floor, DJ booth with monitors.', '{"DJ booth"}', '{DJ}', 'Fayetteville', 'AR', 36.0905, -94.1690),                                          -- 2.0 mi
  ('10000000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000002', 'Café Lune', 'Café · Acoustic corner',
     'Weekend evenings, small crowd, good listening room.', '{}', '{Solo,Singer}', 'Fayetteville', 'AR', 36.0545, -94.1702),                                         -- 0.9 mi
  ('10000000-0000-0000-0000-000000000005', '00000000-0000-0000-0000-000000000002', 'Harbor House', 'Restaurant',
     null, '{"PA system"}', '{Singer}', 'Springdale', 'AR', 36.1867, -94.1288),                                                                                      -- 8.7 mi
  ('10000000-0000-0000-0000-000000000006', '00000000-0000-0000-0000-000000000002', 'Brick & Barrel', 'Bar',
     null, '{Stage}', '{Band}', 'Fayetteville', 'AR', 36.0398, -94.1405),                                                                                            -- 1.8 mi
  ('10000000-0000-0000-0000-000000000007', '00000000-0000-0000-0000-000000000002', 'The Grain Elevator', 'Event hall',
     null, '{Stage,"PA system"}', '{Band}', 'Eureka Springs', 'AR', 36.4012, -93.7379),                                                                              -- 33 mi
  ('10000000-0000-0000-0000-000000000008', '00000000-0000-0000-0000-000000000002', 'Lakeside Lodge', 'Lodge',
     null, '{}', '{Solo}', 'Harrison', 'AR', 36.2298, -93.1077),                                                                                                     -- 60 mi
  ('10000000-0000-0000-0000-000000000009', '00000000-0000-0000-0000-000000000002', 'Depot Taproom', 'Taproom',
     null, '{"DJ booth"}', '{DJ}', 'Conway', 'AR', 35.0887, -92.4421),                                                                                               -- 118 mi
  ('10000000-0000-0000-0000-000000000010', '00000000-0000-0000-0000-000000000002', 'County Fair Stage', 'Outdoor stage',
     null, '{Stage,"PA system"}', '{Band}', 'Little Rock', 'AR', 34.7465, -92.2896);                                                                                 -- 139 mi

-- ---------------------------------------------------------------
-- Artists (Mara Voss at home; the others where the Musicians board puts them)
-- ---------------------------------------------------------------
insert into artists (id, owner_id, name, act_type, genres, bio, town, state, lat, lng) values
  ('20000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000011', 'Mara Voss', 'Singer', '{Jazz,Soul}',
     'Who you are, what you play, where you have played.', 'Fayetteville', 'AR', 36.0626, -94.1574),
  ('20000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000012', 'DJ Kestrel', 'DJ', '{House}',
     null, 'Fort Smith', 'AR', 35.3859, -94.3985),
  ('20000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000012', 'The Loose Ends', 'Band', '{"Indie rock"}',
     'Four-piece, own PA, happy to travel.', 'Springdale', 'AR', 36.1750, -94.1350),
  ('20000000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000012', 'Eli Park', 'Solo', '{Acoustic}',
     null, 'Fayetteville', 'AR', 36.0720, -94.1300),
  ('20000000-0000-0000-0000-000000000005', '00000000-0000-0000-0000-000000000012', 'Brass Tacks Trio', 'Band', '{Blues}',
     null, 'Rogers', 'AR', 36.3320, -94.1185),
  ('20000000-0000-0000-0000-000000000006', '00000000-0000-0000-0000-000000000012', 'Rosa Vale', 'Singer', '{Country}',
     null, 'Harrison', 'AR', 36.2350, -93.1150);

insert into social_links (artist_id, platform, url) values
  ('20000000-0000-0000-0000-000000000001', 'instagram', 'https://example.com/maravoss/instagram'),
  ('20000000-0000-0000-0000-000000000001', 'spotify',   'https://example.com/maravoss/spotify');

-- ---------------------------------------------------------------
-- Gigs (g1-g10 in state.gigs in index.html; isodow 5 = Fri, 6 = Sat, 7 = Sun)
-- ---------------------------------------------------------------
insert into gigs (id, venue_id, act_type, starts_at, pay_cents, genre, reach, travel) values
  ('30000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', 'Singer', pg_temp.at_local(pg_temp.next_day(5), '20:00'), 18000, 'Jazz',      'Region',    'None'),
  ('30000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000002', 'Band',   pg_temp.at_local((now() at time zone 'America/Chicago')::date, '21:00'), 30000, 'Rock', 'Town', 'None'),  -- tonight
  ('30000000-0000-0000-0000-000000000003', '10000000-0000-0000-0000-000000000003', 'DJ',     pg_temp.at_local(pg_temp.next_day(5), '22:00'), 25000, 'House',     'Region',    'None'),
  ('30000000-0000-0000-0000-000000000004', '10000000-0000-0000-0000-000000000004', 'Solo',   pg_temp.at_local(pg_temp.next_day(6), '19:00'), 12000, 'Acoustic',  'Town',      'None'),
  ('30000000-0000-0000-0000-000000000005', '10000000-0000-0000-0000-000000000005', 'Singer', pg_temp.at_local(pg_temp.next_day(6), '20:00'), 18000, 'Standards', 'Town',      'None'),
  ('30000000-0000-0000-0000-000000000006', '10000000-0000-0000-0000-000000000006', 'Band',   pg_temp.at_local(pg_temp.next_day(7), '16:00'), 20000, 'Blues',     'Region',    'None'),
  ('30000000-0000-0000-0000-000000000007', '10000000-0000-0000-0000-000000000007', 'Band',   pg_temp.at_local(pg_temp.next_day(6), '21:00'), 45000, 'Country',   'Region',    'Gas'),
  ('30000000-0000-0000-0000-000000000008', '10000000-0000-0000-0000-000000000008', 'Solo',   pg_temp.at_local(pg_temp.next_day(5), '18:00'), 20000, 'Acoustic',  'Statewide', 'Gas + room'),
  ('30000000-0000-0000-0000-000000000009', '10000000-0000-0000-0000-000000000009', 'DJ',     pg_temp.at_local(pg_temp.next_day(6), '22:00'), 35000, 'House',     'Statewide', 'Gas + room'),
  ('30000000-0000-0000-0000-000000000010', '10000000-0000-0000-0000-000000000010', 'Band',   pg_temp.at_local(pg_temp.next_day(7), '14:00'), 60000, 'Country',   'Statewide', 'Lodging'),
  -- History for "My events" (not in index.html's sample list): 3 past shows and 1 upcoming
  ('30000000-0000-0000-0000-000000000011', '10000000-0000-0000-0000-000000000001', 'Singer', pg_temp.at_local(pg_temp.next_day(5) - 28, '20:00'), 18000, 'Jazz',      'Region',    'None'),
  ('30000000-0000-0000-0000-000000000012', '10000000-0000-0000-0000-000000000004', 'Singer', pg_temp.at_local(pg_temp.next_day(6) - 14, '19:00'), 12000, 'Standards', 'Town',      'None'),
  ('30000000-0000-0000-0000-000000000013', '10000000-0000-0000-0000-000000000001', 'Solo',   pg_temp.at_local(pg_temp.next_day(7) - 21, '18:00'), 15000, 'Acoustic',  'Town',      'None'),
  ('30000000-0000-0000-0000-000000000014', '10000000-0000-0000-0000-000000000001', 'Singer', pg_temp.at_local(pg_temp.next_day(5) + 7,  '20:00'), 20000, 'Soul',      'Region',    'None');

-- ---------------------------------------------------------------
-- Live shows (state.bookings in index.html): 4 gigs already booked,
-- plus the "My events" history above (3 past, 1 upcoming).
-- Each booked artist has an accepted application, the gig is filled,
-- and it no longer shows up in "Gigs near you".
-- ---------------------------------------------------------------
insert into applications (gig_id, artist_id, status) values
  ('30000000-0000-0000-0000-000000000002', '20000000-0000-0000-0000-000000000003', 'accepted'),  -- Rusty Anchor   <- The Loose Ends
  ('30000000-0000-0000-0000-000000000006', '20000000-0000-0000-0000-000000000005', 'accepted'),  -- Brick & Barrel <- Brass Tacks Trio
  ('30000000-0000-0000-0000-000000000008', '20000000-0000-0000-0000-000000000004', 'accepted'),  -- Lakeside Lodge <- Eli Park
  ('30000000-0000-0000-0000-000000000009', '20000000-0000-0000-0000-000000000002', 'accepted'),  -- Depot Taproom  <- DJ Kestrel
  ('30000000-0000-0000-0000-000000000011', '20000000-0000-0000-0000-000000000001', 'accepted'),  -- past: Corner Stage <- Mara Voss
  ('30000000-0000-0000-0000-000000000012', '20000000-0000-0000-0000-000000000001', 'accepted'),  -- past: Café Lune    <- Mara Voss
  ('30000000-0000-0000-0000-000000000013', '20000000-0000-0000-0000-000000000004', 'accepted'),  -- past: Corner Stage <- Eli Park
  ('30000000-0000-0000-0000-000000000014', '20000000-0000-0000-0000-000000000001', 'accepted');  -- upcoming: Corner Stage <- Mara Voss

insert into bookings (gig_id, artist_id, agreed_pay_cents)
select a.gig_id, a.artist_id, g.pay_cents
from applications a join gigs g on g.id = a.gig_id
where a.status = 'accepted';

update gigs set status = 'filled' where id in (select gig_id from bookings);
-- the 3 past shows happened
update gigs set status = 'completed' where id in ('30000000-0000-0000-0000-000000000011',
  '30000000-0000-0000-0000-000000000012', '30000000-0000-0000-0000-000000000013');
update bookings set payment_status = 'paid' where gig_id in ('30000000-0000-0000-0000-000000000011',
  '30000000-0000-0000-0000-000000000012', '30000000-0000-0000-0000-000000000013');

-- ---------------------------------------------------------------
-- Musicians board (c1-c5 in state.gigs in index.html). Each post sits
-- where its poster lives. "when" and "pay" are free text, as in the app.
-- ---------------------------------------------------------------
insert into collab_posts (id, artist_id, wants, purpose, when_text, pay_text, genre, note) values
  ('40000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000003', 'Singer', 'Fill-in for a show', 'Sat · 9 PM', '$150',           'Indie rock',
     'Our singer is out sick. Can you learn 8 covers by Saturday?'),                                     -- The Loose Ends, Springdale
  ('40000000-0000-0000-0000-000000000002', '20000000-0000-0000-0000-000000000005', 'Solo',   'Opening act',        'Fri · 7 PM', '$100',           'Blues',
     '30-minute acoustic opener before our set at Brick & Barrel.'),                                     -- Brass Tacks Trio, Rogers
  ('40000000-0000-0000-0000-000000000003', '20000000-0000-0000-0000-000000000004', 'Band',   'Backing band',       'Sun · 4 PM', 'Split the door', 'Acoustic',
     'Need bass and drums behind me for a patio show. Charts provided.'),                                -- Eli Park, Fayetteville
  ('40000000-0000-0000-0000-000000000004', '20000000-0000-0000-0000-000000000006', 'Band',   'Join my act',        'Ongoing',    'Split the door', 'Country',
     'Booking fair season. Looking for a steady band to tour the state with.'),                          -- Rosa Vale, Harrison
  ('40000000-0000-0000-0000-000000000005', '20000000-0000-0000-0000-000000000002', 'Singer', 'Jam / session',      'Flexible',   'Unpaid',         'House',
     'Want a vocalist for a live house set. Let’s try a session first.');                                -- DJ Kestrel, Fort Smith

-- ---------------------------------------------------------------
-- Media: reels (REELS in index.html) and Mara's portfolio
-- storage_path is where the file will go in Supabase Storage.
-- ---------------------------------------------------------------
insert into media (artist_id, venue_id, kind, title, caption, storage_path, in_reels) values
  ('20000000-0000-0000-0000-000000000001', null, 'video', 'Live at the loft',  'Late set at the loft.',                  'sample/mara-loft.mp4',        true),
  ('20000000-0000-0000-0000-000000000001', null, 'video', 'Rooftop session',   null,                                     'sample/mara-rooftop.mp4',     false),
  ('20000000-0000-0000-0000-000000000001', null, 'audio', 'Demo reel',         null,                                     'sample/mara-demo.mp3',        false),
  ('20000000-0000-0000-0000-000000000002', null, 'video', null,                'Two hours of warm-up grooves.',          'sample/kestrel.mp4',          true),
  ('20000000-0000-0000-0000-000000000003', null, 'video', null,                'Four-piece, own PA, happy to travel.',   'sample/loose-ends.mp4',       true),
  ('20000000-0000-0000-0000-000000000004', null, 'video', null,                'Songs for a patio crowd.',               'sample/eli-park.mp4',         true),
  (null, '10000000-0000-0000-0000-000000000002', 'photo', null, 'Stage and PA provided. Bands Thursday to Saturday.', 'sample/rusty-anchor.jpg', true),
  (null, '10000000-0000-0000-0000-000000000003', 'photo', null, 'Late nights, dance floor, DJ booth with monitors.',  'sample/velvet-room.jpg',  true),
  (null, '10000000-0000-0000-0000-000000000004', 'photo', null, 'Weekend evenings, small crowd, good listening room.', 'sample/cafe-lune.jpg',   true);
