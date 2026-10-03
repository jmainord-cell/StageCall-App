-- ---------------------------------------------------------------
-- Stagecall sample data: the same gigs, venues, artists and reels the
-- prototype shows in index.html. All names and places are fictional.
--
-- Locations are laid out around a made-up home point (38.0, -92.0) so the
-- distances roughly match the prototype (1 degree of latitude ~ 69.09 mi).
-- Gig dates are relative to the day you load this file.
--
-- Sample accounts have no password and cannot sign in. They exist only to
-- own the sample rows. Run after schema.sql and policies.sql; the sign-up
-- trigger creates each profile from its metadata.
-- ---------------------------------------------------------------

insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-000000000001', 'corner-stage@example.com',  '{"role":"venue","display_name":"The Corner Stage"}'),
  ('00000000-0000-0000-0000-000000000002', 'sample-venues@example.com', '{"role":"venue","display_name":"Sample venues"}'),
  ('00000000-0000-0000-0000-000000000011', 'mara-voss@example.com',     '{"role":"artist","display_name":"Mara Voss"}'),
  ('00000000-0000-0000-0000-000000000012', 'sample-artists@example.com','{"role":"artist","display_name":"Sample artists"}');

-- ---------------------------------------------------------------
-- Venues (north of home; miles / 69.09 = degrees of latitude)
-- ---------------------------------------------------------------
insert into venues (id, owner_id, name, kind, about, equipment, books, town, state, lat, lng) values
  ('10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'The Corner Stage', 'Live room & bar',
     'The vibe, the crowd, what nights you book.', '{Stage,"PA system",Backline,"DJ booth"}', '{DJ,Band,Solo,Singer}', 'Home', 'MO', 38 + 0.4/69.09, -92),
  ('10000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000002', 'The Rusty Anchor', 'Bar with a small stage',
     'Stage and PA provided. Bands Thursday to Saturday.', '{Stage,"PA system"}', '{Band}', 'Home', 'MO', 38 + 1.2/69.09, -92),
  ('10000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000002', 'Velvet Room', 'Club · DJ booth',
     'Late nights, dance floor, DJ booth with monitors.', '{"DJ booth"}', '{DJ}', 'Home', 'MO', 38 + 2.4/69.09, -92),
  ('10000000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000002', 'Café Lune', 'Café · Acoustic corner',
     'Weekend evenings, small crowd, good listening room.', '{}', '{Solo,Singer}', 'Home', 'MO', 38 + 0.8/69.09, -92),
  ('10000000-0000-0000-0000-000000000005', '00000000-0000-0000-0000-000000000002', 'Harbor House', 'Restaurant',
     null, '{"PA system"}', '{Singer}', 'Home', 'MO', 38 + 3.1/69.09, -92),
  ('10000000-0000-0000-0000-000000000006', '00000000-0000-0000-0000-000000000002', 'Brick & Barrel', 'Bar',
     null, '{Stage}', '{Band}', 'Home', 'MO', 38 + 1.9/69.09, -92),
  ('10000000-0000-0000-0000-000000000007', '00000000-0000-0000-0000-000000000002', 'The Grain Elevator', 'Event hall',
     null, '{Stage,"PA system"}', '{Band}', 'Hollis Creek', 'MO', 38 + 38/69.09, -92),
  ('10000000-0000-0000-0000-000000000008', '00000000-0000-0000-0000-000000000002', 'Lakeside Lodge', 'Lodge',
     null, '{}', '{Solo}', 'Pine Hollow', 'MO', 38 + 64/69.09, -92),
  ('10000000-0000-0000-0000-000000000009', '00000000-0000-0000-0000-000000000002', 'Depot Taproom', 'Taproom',
     null, '{"DJ booth"}', '{DJ}', 'Dunmore', 'MO', 38 + 112/69.09, -92),
  ('10000000-0000-0000-0000-000000000010', '00000000-0000-0000-0000-000000000002', 'County Fair Stage', 'Outdoor stage',
     null, '{Stage,"PA system"}', '{Band}', 'Fairview', 'MO', 38 + 145/69.09, -92);

-- ---------------------------------------------------------------
-- Artists (Mara Voss at home; the rest south of home)
-- ---------------------------------------------------------------
insert into artists (id, owner_id, name, act_type, genres, bio, town, state, lat, lng) values
  ('20000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000011', 'Mara Voss', 'Singer', '{Jazz,Soul}',
     'Who you are, what you play, where you have played.', 'Home', 'MO', 38, -92),
  ('20000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000012', 'DJ Kestrel', 'DJ', '{House}',
     null, 'Southbend', 'MO', 38 - 55/69.09, -92),
  ('20000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000012', 'The Loose Ends', 'Band', '{"Indie rock"}',
     'Four-piece, own PA, happy to travel.', 'Millbrook', 'MO', 38 - 90/69.09, -92),
  ('20000000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000012', 'Eli Park', 'Solo', '{Acoustic}',
     null, 'Home', 'MO', 38 - 4/69.09, -92);

insert into social_links (artist_id, platform, url) values
  ('20000000-0000-0000-0000-000000000001', 'instagram', 'https://example.com/maravoss/instagram'),
  ('20000000-0000-0000-0000-000000000001', 'spotify',   'https://example.com/maravoss/spotify');

-- ---------------------------------------------------------------
-- Gigs (state.gigs in index.html)
-- ---------------------------------------------------------------
insert into gigs (id, venue_id, act_type, starts_at, pay_cents, genre, reach, travel) values
  ('30000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', 'Singer', current_date + 2 + time '20:00', 18000, 'Jazz',      'Region',    'None'),
  ('30000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000002', 'Band',   current_date + 1 + time '21:00', 30000, 'Rock',      'Town',      'None'),
  ('30000000-0000-0000-0000-000000000003', '10000000-0000-0000-0000-000000000003', 'DJ',     current_date + 2 + time '22:00', 25000, 'House',     'Region',    'None'),
  ('30000000-0000-0000-0000-000000000004', '10000000-0000-0000-0000-000000000004', 'Solo',   current_date + 3 + time '19:00', 12000, 'Acoustic',  'Town',      'None'),
  ('30000000-0000-0000-0000-000000000005', '10000000-0000-0000-0000-000000000005', 'Singer', current_date + 3 + time '20:00', 18000, 'Standards', 'Town',      'None'),
  ('30000000-0000-0000-0000-000000000006', '10000000-0000-0000-0000-000000000006', 'Band',   current_date + 4 + time '16:00', 20000, 'Blues',     'Region',    'None'),
  ('30000000-0000-0000-0000-000000000007', '10000000-0000-0000-0000-000000000007', 'Band',   current_date + 3 + time '21:00', 45000, 'Country',   'Region',    'Gas'),
  ('30000000-0000-0000-0000-000000000008', '10000000-0000-0000-0000-000000000008', 'Solo',   current_date + 2 + time '18:00', 20000, 'Acoustic',  'Statewide', 'Gas + room'),
  ('30000000-0000-0000-0000-000000000009', '10000000-0000-0000-0000-000000000009', 'DJ',     current_date + 3 + time '22:00', 35000, 'House',     'Statewide', 'Gas + room'),
  ('30000000-0000-0000-0000-000000000010', '10000000-0000-0000-0000-000000000010', 'Band',   current_date + 4 + time '14:00', 60000, 'Country',   'Statewide', 'Lodging');

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
