// Tests schema.sql, policies.sql and seed.sql against real Postgres (PGlite),
// with a small stand-in for Supabase's auth schema. Run from db/:
//   npm install
//   npm test

import { PGlite } from '@electric-sql/pglite';
import { readFileSync } from 'node:fs';

const DB = new URL('./', import.meta.url);
const db = new PGlite();

const MARA = '00000000-0000-0000-0000-000000000011';     // artist account
const SAMPLE_ART = '00000000-0000-0000-0000-000000000012';
const CORNER = '00000000-0000-0000-0000-000000000001';   // venue account
const MARA_ARTIST = '20000000-0000-0000-0000-000000000001';
const KESTREL = '20000000-0000-0000-0000-000000000002';
const ELI = '20000000-0000-0000-0000-000000000004';
const GIG_CORNER = '30000000-0000-0000-0000-000000000001';
const GIG_RUSTY = '30000000-0000-0000-0000-000000000002';

let pass = 0, fail = 0;
function check(name, ok, detail = '') {
  ok ? pass++ : fail++;
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? '  -> ' + detail : ''}`);
}
async function expectError(name, sql, params = []) {
  try { await db.query(sql, params); check(name, false, 'no error raised'); }
  catch (e) { check(name, true, e.message); }
}
async function as(uid) {
  await db.exec(uid ? 'set role authenticated' : 'set role anon');
  await db.query(`select set_config('request.jwt.claim.sub', $1, false)`, [uid || '']);
}
async function asAdmin() {
  await db.exec('reset role');
  await db.query(`select set_config('request.jwt.claim.sub', '', false)`);
}

// --- Stub of what Supabase provides ---
await db.exec(`
  create schema auth;
  create table auth.users (id uuid primary key, email text, raw_user_meta_data jsonb);
  create function auth.uid() returns uuid language sql stable as
    $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
  create role anon; create role authenticated;
  -- Like Supabase: new tables and functions in public are granted to anon and
  -- authenticated when they are created, so the files' own revokes still count.
  grant usage on schema public, auth to anon, authenticated;
  grant execute on all functions in schema auth to anon, authenticated;
  alter default privileges in schema public grant all on tables to anon, authenticated;
  alter default privileges in schema public grant execute on functions to anon, authenticated;
`);

for (const f of ['schema.sql', 'policies.sql', 'seed.sql']) {
  try { await db.exec(readFileSync(new URL(f, DB), 'utf8')); check(`load ${f}`, true); }
  catch (e) { check(`load ${f}`, false, e.message); process.exit(1); }
}

// --- Data loaded ---
const counts = (await db.query(`select
  (select count(*) from profiles)::int p, (select count(*) from venues)::int v,
  (select count(*) from artists)::int a, (select count(*) from gigs)::int g,
  (select count(*) from media where in_reels)::int r`)).rows[0];
check('signup trigger made 4 profiles', counts.p === 4, JSON.stringify(counts));
check('10 venues, 6 artists, 14 gigs (10 from the app + 4 history), 7 reels', counts.v === 10 && counts.a === 6 && counts.g === 14 && counts.r === 7, JSON.stringify(counts));

// --- Arkansas locations (HOME and venue miles from BACKEND_SETUP.md section 6) ---
const HOME = [36.0626, -94.1574];
const venueMiles = (await db.query(`select name, town, state, miles_between($1, $2, lat, lng) m from venues order by id`, HOME)).rows;
const expected = [['The Corner Stage', 0.3], ['The Rusty Anchor', 1.0], ['Velvet Room', 2.0], ['Café Lune', 0.9], ['Harbor House', 8.7],
  ['Brick & Barrel', 1.8], ['The Grain Elevator', 33], ['Lakeside Lodge', 60], ['Depot Taproom', 118], ['County Fair Stage', 139]];
const off = expected.filter(([n, mi], i) => venueMiles[i].name !== n || venueMiles[i].state !== 'AR' || Math.abs(venueMiles[i].m - mi) > (mi < 10 ? 0.1 : 1));
check('venues are at the Arkansas places in the setup guide', off.length === 0,
  off.length ? off.map(([n]) => n).join(', ') : venueMiles.map(v => `${v.town} ${v.m.toFixed(1)}`).join(' / '));
const mara = (await db.query(`select town, lat, lng from artists where id = $1`, [MARA_ARTIST])).rows[0];
check('Mara Voss lives at HOME (Fayetteville)', mara.lat === HOME[0] && mara.lng === HOME[1] && mara.town === 'Fayetteville');

// --- Live shows: the 4 sample bookings (state.bookings in index.html) ---
const live = (await db.query(`select v.name venue, a.name artist, g.status::text, b.agreed_pay_cents = g.pay_cents same_pay,
  (select status::text from applications x where x.gig_id = g.id and x.artist_id = a.id) app
  from bookings b join gigs g on g.id = b.gig_id join venues v on v.id = g.venue_id join artists a on a.id = b.artist_id
  where g.id <= '30000000-0000-0000-0000-000000000010' order by v.name`)).rows;
check('4 sample live shows: Brick & Barrel, Depot Taproom, Lakeside Lodge, Rusty Anchor',
  live.map(r => r.venue + '=' + r.artist).join(', ') === 'Brick & Barrel=Brass Tacks Trio, Depot Taproom=DJ Kestrel, Lakeside Lodge=Eli Park, The Rusty Anchor=The Loose Ends',
  live.map(r => r.venue + '=' + r.artist).join(', '));
check('each live show: gig filled, pay copied, application accepted', live.every(r => r.status === 'filled' && r.same_pay && r.app === 'accepted'));
const hist = (await db.query(`select v.name venue, a.name artist, g.status::text s, b.payment_status::text p, g.starts_at < now() past
  from bookings b join gigs g on g.id = b.gig_id join venues v on v.id = g.venue_id join artists a on a.id = b.artist_id
  where g.id > '30000000-0000-0000-0000-000000000010' order by g.starts_at`)).rows;
check('history: 3 past shows (completed, paid) and 1 upcoming',
  hist.map(r => `${r.venue}=${r.artist}:${r.past ? 'past' : 'upcoming'}:${r.s}:${r.p}`).join(', ') ===
  'The Corner Stage=Mara Voss:past:completed:paid, The Corner Stage=Eli Park:past:completed:paid, Café Lune=Mara Voss:past:completed:paid, The Corner Stage=Mara Voss:upcoming:filled:unpaid',
  hist.map(r => `${r.venue}=${r.artist}:${r.past ? 'past' : 'upcoming'}`).join(', '));
const future = (await db.query(`select count(*)::int n from gigs where status = 'open' and starts_at <= now()`)).rows[0].n;
check('every open sample gig is in the future', future === 0, `past=${future}`);
const roles = (await db.query(`select role::text from profiles where id = $1`, [CORNER])).rows[0].role;
check('profile role comes from sign-up metadata', roles === 'venue', roles);

// --- Lock-down (Supabase security advisor) ---
const definerInPublic = (await db.query(`select count(*)::int n from pg_proc p join pg_namespace s on s.oid = p.pronamespace
  where s.nspname = 'public' and p.prosecdef`)).rows[0].n;
check('no security definer functions in the public (API) schema', definerInPublic === 0, `n=${definerInPublic}`);
const trig = (await db.query(`select
  has_function_privilege('anon', 'private.handle_new_user()', 'execute') a,
  has_function_privilege('authenticated', 'private.check_application_update()', 'execute') b`)).rows[0];
check('nobody can call the trigger functions by hand', !trig.a && !trig.b, JSON.stringify(trig));
const unpinned = (await db.query(`select string_agg(p.proname, ', ') names from pg_proc p join pg_namespace s on s.oid = p.pronamespace
  where s.nspname in ('public', 'private') and p.prokind = 'f' and p.proconfig is null`)).rows[0].names;
check('every function has a fixed search_path', unpinned === null, unpinned || '');

// --- Distance filters: same counts the prototype shows for Mara ---
const reach = async (artist, range, act = null) =>
  (await db.query(`select * from gigs_in_reach($1, $2, $3)`, [artist, range, act])).rows;
const town = await reach(MARA_ARTIST, 'Town');
// Booked gigs drop out, as in the app (index.html hides a gig someone else got).
check('Mara / Town = 4 gigs (matches prototype)', town.length === 4, town.map(r => r.venue_name).join(', '));
check('Mara / Region = 5 gigs (matches prototype)', (await reach(MARA_ARTIST, 'Region')).length === 5);
check('Mara / Statewide = 6 gigs (matches prototype)', (await reach(MARA_ARTIST, 'Statewide')).length === 6);
check('nearest gig is listed first', town[0].venue_name === 'The Corner Stage', `${town[0].venue_name} ${town[0].miles.toFixed(2)} mi`);
const grain = (await reach(MARA_ARTIST, 'Region')).find(r => r.venue_name === 'The Grain Elevator');
check('Grain Elevator (Eureka Springs) is ~33 mi away', Math.abs(grain.miles - 33) < 1, grain.miles.toFixed(2));
// Kestrel is in Fort Smith, ~49 mi out: Town venues (Café Lune, Harbor House) and the
// Grain Elevator (Region, ~79 mi from him) don't want him; the rest are booked.
const kes = await reach(KESTREL, 'Statewide');
check('Kestrel (Fort Smith) / Statewide = 3: venue Town/Region limits respected', kes.length === 3, kes.map(r => r.venue_name).join(', '));
check('Kestrel / Statewide / DJ only = 1 (Velvet Room)', (await reach(KESTREL, 'Statewide', 'DJ')).map(r => r.venue_name).join() === 'Velvet Room');

// --- Live shows on the map (public view over private bookings) ---
// the app's 4 live shows + Mara's upcoming show at The Corner Stage (sample history)
const LIVE4 = 'Brick & Barrel=Brass Tacks Trio, Depot Taproom=DJ Kestrel, Lakeside Lodge=Eli Park, The Corner Stage=Mara Voss, The Rusty Anchor=The Loose Ends';
const liveNames = async () => (await db.query(`select venue_name, artist_name from live_shows`)).rows
  .map(r => r.venue_name + '=' + r.artist_name).sort().join(', ');
await as(null);
check('anon sees the 5 upcoming live shows for the map (past ones are not shown)', (await liveNames()) === LIVE4, await liveNames());
const liveCols = (await db.query(`select * from live_shows limit 1`)).fields.map(f => f.name);
check('live shows expose no pay or payment details', !liveCols.some(c => /pay|deposit|payment/.test(c)), liveCols.join(', '));
check('anon still cannot read the bookings table', (await db.query(`select * from bookings`)).rows.length === 0);
const viewUnsafe = (await db.query(`select count(*)::int n from pg_class c join pg_namespace s on s.oid = c.relnamespace
  where s.nspname = 'public' and c.relkind = 'v' and not coalesce(c.reloptions::text[] @> '{security_invoker=true}', false)`)).rows[0].n;
check('every public view runs with the caller\'s permissions', viewUnsafe === 0, `n=${viewUnsafe}`);
await asAdmin();
await db.query(`update gigs set starts_at = now() - interval '5 hours' where id = $1`, [GIG_RUSTY]);
check('a show drops off the map 4 hours after it starts', !(await liveNames()).includes('Rusty Anchor'));

// --- refresh_sample_dates.sql brings stale sample dates back ---
await db.exec(readFileSync(new URL('refresh_sample_dates.sql', DB), 'utf8'));
const seeded = (await db.query(`select id, starts_at from gigs order by id`)).rows;
await db.exec(`update gigs set starts_at = starts_at - interval '30 days'`);
check('with stale dates, gigs and live shows disappear',
  (await reach(MARA_ARTIST, 'Statewide')).length === 0 && (await liveNames()) === '');
await db.exec(readFileSync(new URL('refresh_sample_dates.sql', DB), 'utf8'));
const refreshed = (await db.query(`select id, starts_at from gigs order by id`)).rows;
check('refresh sets the same dates as seed.sql', JSON.stringify(seeded) === JSON.stringify(refreshed));
const canRefresh = (await db.query(`select has_function_privilege('anon', 'private.refresh_sample_dates()', 'execute') a,
  has_function_privilege('authenticated', 'private.refresh_sample_dates()', 'execute') b`)).rows[0];
check('only the database itself can run the daily refresh', !canRefresh.a && !canRefresh.b, JSON.stringify(canRefresh));
const counts3 = [(await reach(MARA_ARTIST, 'Town')).length, (await reach(MARA_ARTIST, 'Region')).length, (await reach(MARA_ARTIST, 'Statewide')).length];
check('after refresh: Mara 4 / 5 / 6 and the same 5 live shows', counts3.join('/') === '4/5/6' && (await liveNames()) === LIVE4, counts3.join('/'));

// --- RLS: browsing ---
await as(null);
check('anon can browse the 6 open gigs, not the filled ones', (await db.query(`select * from gig_cards`)).rows.length === 6);
check('anon cannot see bookings', (await db.query(`select * from bookings`)).rows.length === 0);
await asAdmin();
await db.query(`insert into applications (gig_id, artist_id) values ($1, $2)`, [GIG_RUSTY, ELI]);

// --- My events (Profile tab) ---
const events = async () => (await db.query(`select * from my_events()`)).rows;
const fmt = rows => rows.map(r => `${r.kind}/${r.side}/${r.is_past ? 'past' : 'next'}:${r.venue_name}${r.artist_name ? '=' + r.artist_name : ''}`).join(', ');
await as(MARA);
let ev = await events();
check('Mara: 2 past shows, 1 upcoming booking, nothing pending',
  fmt(ev) === 'booking/artist/past:The Corner Stage=Mara Voss, booking/artist/past:Café Lune=Mara Voss, booking/artist/next:The Corner Stage=Mara Voss', fmt(ev));
check('Mara sees what she was paid', ev.map(r => r.pay_cents).join() === '18000,12000,20000');
await as(CORNER);
ev = await events();
check('Corner Stage: 2 past shows, 1 upcoming, 1 open gig with 0 applicants',
  fmt(ev.filter(r => r.kind === 'booking')) === 'booking/venue/past:The Corner Stage=Mara Voss, booking/venue/past:The Corner Stage=Eli Park, booking/venue/next:The Corner Stage=Mara Voss'
  && ev.filter(r => r.kind === 'open_gig').map(r => r.gig_id + ':' + r.applicant_count).join() === GIG_CORNER + ':0', fmt(ev));
await as(SAMPLE_ART);
check("other accounts don't see Mara's events", !(await events()).some(r => r.artist_name === 'Mara Voss'));
await as(null);
await expectError('signed-out visitors have no events', `select * from my_events()`);

// --- RLS: applying ---
await as(MARA);
await db.query(`insert into applications (gig_id, artist_id) values ($1, $2)`, [GIG_CORNER, MARA_ARTIST]);
check('Mara can apply as her own act', true);
await expectError('Mara cannot apply as DJ Kestrel', `insert into applications (gig_id, artist_id) values ($1, $2)`, [GIG_CORNER, KESTREL]);
const maraApps = (await db.query(`select artist_id from applications`)).rows;
check("Mara sees only her own applications (1 new + 3 from her bookings)", maraApps.length === 4 && maraApps.every(r => r.artist_id === MARA_ARTIST), `n=${maraApps.length}`);
await expectError('Mara cannot accept her own application',
  `update applications set status = 'accepted' where gig_id = $1 and artist_id = $2`, [GIG_CORNER, MARA_ARTIST]);
await expectError('Mara cannot move her application to another gig',
  `update applications set gig_id = $1 where artist_id = $2`, [GIG_RUSTY, MARA_ARTIST]);
await db.query(`update applications set status = 'withdrawn' where gig_id = $1 and artist_id = $2`, [GIG_CORNER, MARA_ARTIST]);
await db.query(`update applications set status = 'applied' where gig_id = $1 and artist_id = $2`, [GIG_CORNER, MARA_ARTIST]);
check('Mara can withdraw and re-apply', true);

// --- RLS: venue side ---
await as(CORNER);
const cards = (await db.query(`select applicant_count::int n from gig_cards where id = $1`, [GIG_CORNER])).rows[0];
check('venue sees applicant count on its gig', cards.n === 1, `n=${cards.n}`);
check('My events: Corner Stage open gig now shows 1 applicant',
  (await events()).find(r => r.kind === 'open_gig' && r.gig_id === GIG_CORNER)?.applicant_count === 1);
await as(MARA);
check('My events: Mara sees her pending application', (await events()).some(r => r.kind === 'application' && r.gig_id === GIG_CORNER));
await as(CORNER);
const cornerApps = (await db.query(`select x.gig_id from applications x join gigs g on g.id = x.gig_id
  where g.venue_id <> '10000000-0000-0000-0000-000000000001'`)).rows;
check("Corner Stage can't see applications to other venues' gigs", cornerApps.length === 0, `n=${cornerApps.length}`);

// --- Book in one step, undo booking, undo decline ---
// Corner Stage's gig: Mara applied; Eli and Kestrel apply too.
await asAdmin();
await db.query(`insert into applications (gig_id, artist_id) values ($1, $2), ($1, $3)`, [GIG_CORNER, ELI, KESTREL]);
const appStatus = async () => Object.fromEntries((await db.query(
  `select a.name, x.status::text s from applications x join artists a on a.id = x.artist_id where x.gig_id = $1`, [GIG_CORNER])).rows.map(r => [r.name, r.s]));
const gigState = async () => (await db.query(`select g.status::text s, (select count(*)::int from bookings b where b.gig_id = g.id) n
  from gigs g where g.id = $1`, [GIG_CORNER])).rows[0];
await as(CORNER);
await db.query(`update applications set status = 'declined' where gig_id = $1 and artist_id = $2`, [GIG_CORNER, KESTREL]);
await db.query(`update applications set status = 'applied' where gig_id = $1 and artist_id = $2`, [GIG_CORNER, KESTREL]);
check('venue can undo a decline', (await appStatus())['DJ Kestrel'] === 'applied');
await db.query(`update applications set status = 'declined' where gig_id = $1 and artist_id = $2`, [GIG_CORNER, KESTREL]);
await as(SAMPLE_ART);
await expectError("declined artist can't undo the venue's decline",
  `update applications set status = 'applied' where gig_id = $1 and artist_id = $2`, [GIG_CORNER, KESTREL]);
await as(MARA);
await expectError('an artist cannot book', `select book_artist($1, $2)`, [GIG_CORNER, MARA_ARTIST]);
await as(CORNER);
await expectError("can't book an artist the venue declined", `select book_artist($1, $2)`, [GIG_CORNER, KESTREL]);
check('a failed booking changes nothing', JSON.stringify(await gigState()) === '{"s":"open","n":0}', JSON.stringify(await gigState()));
await db.query(`select book_artist($1, $2)`, [GIG_CORNER, ELI]);
const booked = await appStatus(), bk = (await db.query(`select agreed_pay_cents p from bookings where gig_id = $1`, [GIG_CORNER])).rows[0];
await as(SAMPLE_ART);
check('the booked artist can still see the filled gig', (await db.query(`select id from gig_cards where id = $1`, [GIG_CORNER])).rows.length === 1);
await as(MARA);
check('an applicant who was not picked can still see it too', (await db.query(`select id from gig_cards where id = $1`, [GIG_CORNER])).rows.length === 1);
await as(CORNER);
check('book_artist: booking at the gig pay, gig filled, Eli accepted',
  JSON.stringify(await gigState()) === '{"s":"filled","n":1}' && bk.p === 18000 && booked['Eli Park'] === 'accepted', JSON.stringify(booked));
check('others are untouched: Mara still applied ("Not selected"), Kestrel still declined',
  booked['Mara Voss'] === 'applied' && booked['DJ Kestrel'] === 'declined');
await expectError("can't book a gig that's already booked", `select book_artist($1, $2)`, [GIG_CORNER, MARA_ARTIST]);
await as(null);
check('the new booking shows up as a live show', (await liveNames()).includes('The Corner Stage=Eli Park'));
await as(SAMPLE_ART);
await expectError("booked artist can't withdraw on their own",
  `update applications set status = 'withdrawn' where gig_id = $1 and artist_id = $2`, [GIG_CORNER, ELI]);
await as(MARA);
await expectError("an artist can't undo a booking", `select cancel_booking($1)`, [GIG_CORNER]);
await asAdmin();
await db.query(`update bookings set payment_status = 'deposit_paid' where gig_id = $1`, [GIG_CORNER]);
await as(CORNER);
await expectError("can't undo a booking that has a payment", `select cancel_booking($1)`, [GIG_CORNER]);
const del = await db.query(`delete from bookings where gig_id = $1`, [GIG_CORNER]);
check("venue can't delete a paid booking directly", del.affectedRows === 0);
await asAdmin();
await db.query(`update bookings set payment_status = 'unpaid' where gig_id = $1`, [GIG_CORNER]);
await as(CORNER);
await db.query(`select cancel_booking($1)`, [GIG_CORNER]);
const undone = await appStatus();
check('cancel_booking: booking gone, gig open, Eli back to applied, Kestrel still declined',
  JSON.stringify(await gigState()) === '{"s":"open","n":0}' && undone['Eli Park'] === 'applied' && undone['DJ Kestrel'] === 'declined' && undone['Mara Voss'] === 'applied', JSON.stringify(undone));
await as(null);
check('the undone booking leaves the map', !(await liveNames()).includes('The Corner Stage=Eli Park'));
const anonExec = (await db.query(`select has_function_privilege('anon', 'book_artist(uuid, uuid)', 'execute') b,
  has_function_privilege('anon', 'cancel_booking(uuid)', 'execute') c`)).rows[0];
check('signed-out visitors cannot call book_artist or cancel_booking', !anonExec.b && !anonExec.c, JSON.stringify(anonExec));

// --- Direct accept + booking insert still work for the venue ---
await as(CORNER);
await db.query(`update applications set status = 'accepted' where gig_id = $1 and artist_id = $2`, [GIG_CORNER, MARA_ARTIST]);
check('venue can accept an applicant', (await appStatus())['Mara Voss'] === 'accepted');
await expectError('venue cannot withdraw on the artist\'s behalf',
  `update applications set status = 'withdrawn' where gig_id = $1`, [GIG_CORNER]);
const hijack = await db.query(`update gigs set pay_cents = 1 where id = $1`, [GIG_RUSTY]);
check("Corner Stage can't edit another venue's gig", hijack.affectedRows === 0);
await db.query(`insert into gigs (venue_id, act_type, starts_at, pay_cents) values ('10000000-0000-0000-0000-000000000001', 'DJ', now() + interval '1 day', 20000)`);
check('Corner Stage can post a gig', true);
await expectError("Corner Stage can't post a gig as Velvet Room",
  `insert into gigs (venue_id, act_type, starts_at, pay_cents) values ('10000000-0000-0000-0000-000000000003', 'DJ', now(), 1)`);
await db.query(`insert into bookings (gig_id, artist_id, agreed_pay_cents) values ($1, $2, 18000)`, [GIG_CORNER, MARA_ARTIST]);
check('venue can book the accepted artist', true);
await as(MARA);
const maraBookings = (await db.query(`select artist_id from bookings`)).rows;
check('artist sees her bookings and no one else\'s', maraBookings.length === 4 && maraBookings.every(r => r.artist_id === MARA_ARTIST), `n=${maraBookings.length}`);

// --- Musicians board ---
const C1 = '40000000-0000-0000-0000-000000000001';   // The Loose Ends want a singer
await asAdmin();
const board = async (artist, range, wants = null) =>
  (await db.query(`select * from collab_posts_in_reach($1, $2, $3)`, [artist, range, wants])).rows;
check('Mara / Town = 2 posts (Eli Park, The Loose Ends)', (await board(MARA_ARTIST, 'Town')).map(r => r.poster_name).sort().join(', ') === 'Eli Park, The Loose Ends');
check('Mara / Region = all 5 posts', (await board(MARA_ARTIST, 'Region')).length === 5);
check('Mara / Region / wants a singer = 2 (The Loose Ends, DJ Kestrel)',
  (await board(MARA_ARTIST, 'Region', 'Singer')).map(r => r.poster_name).sort().join(', ') === 'DJ Kestrel, The Loose Ends');
const kb = await board(KESTREL, 'Statewide');
check("Kestrel / Statewide = 3: not his own post, and Rosa Vale's post only draws from 75 mi",
  kb.length === 3 && !kb.some(r => ['DJ Kestrel', 'Rosa Vale'].includes(r.poster_name)), kb.map(r => `${r.poster_name} ${r.miles.toFixed(0)}`).join(', '));

await as(null);
check('anon can browse the 5 open posts', (await db.query(`select * from collab_cards`)).rows.length === 5);
await as(MARA);
await db.query(`insert into collab_responses (post_id, artist_id) values ($1, $2)`, [C1, MARA_ARTIST]);
check("Mara can say she's interested", true);
await expectError("Mara can't reply as DJ Kestrel", `insert into collab_responses (post_id, artist_id) values ($1, $2)`, [C1, KESTREL]);
const myPost = (await db.query(`insert into collab_posts (artist_id, wants, purpose, when_text, pay_text)
  values ($1, 'Band', 'Backing band', 'Sat', 'Split the door') returning id`, [MARA_ARTIST])).rows[0].id;
check('Mara can post on the board', !!myPost);
await expectError("Mara can't post as DJ Kestrel",
  `insert into collab_posts (artist_id, wants, purpose, when_text, pay_text) values ($1, 'Band', 'Backing band', 'Sat', 'x')`, [KESTREL]);
await expectError("Mara can't reply to her own post", `insert into collab_responses (post_id, artist_id) values ($1, $2)`, [myPost, MARA_ARTIST]);
check("Mara's own post isn't on her board", !(await board(MARA_ARTIST, 'Statewide')).some(r => r.post_id === myPost));
await db.query(`update collab_responses set status = 'withdrawn' where post_id = $1 and artist_id = $2`, [C1, MARA_ARTIST]);
await db.query(`update collab_responses set status = 'applied' where post_id = $1 and artist_id = $2`, [C1, MARA_ARTIST]);
check('Mara can take it back and be interested again', true);

const resp = async () => (await db.query(`select status::text s from collab_responses where post_id = $1 and artist_id = $2`, [C1, MARA_ARTIST])).rows[0]?.s;
await as(SAMPLE_ART);   // owns The Loose Ends
check('the poster sees 1 interested', (await db.query(`select interested_count::int n from collab_cards where id = $1`, [C1])).rows[0].n === 1);
await db.query(`update collab_responses set status = 'declined' where post_id = $1 and artist_id = $2`, [C1, MARA_ARTIST]);
await as(MARA);
await expectError("Mara can't undo the poster's pass", `update collab_responses set status = 'applied' where post_id = $1 and artist_id = $2`, [C1, MARA_ARTIST]);
await as(SAMPLE_ART);
await db.query(`update collab_responses set status = 'applied' where post_id = $1 and artist_id = $2`, [C1, MARA_ARTIST]);
check('the poster can pass and undo the pass', (await resp()) === 'applied');
await as(MARA);
await expectError("a responder can't team up", `select team_up($1, $2)`, [C1, MARA_ARTIST]);
await as(SAMPLE_ART);
await db.query(`select team_up($1, $2)`, [C1, MARA_ARTIST]);
await as(null);
check('team_up: the post leaves the public board', !(await db.query(`select id from collab_cards`)).rows.some(r => r.id === C1));
await as(MARA);
check('Mara sees "teaming up": response accepted, post still visible to her',
  (await resp()) === 'accepted' && (await db.query(`select status::text s from collab_cards where id = $1`, [C1])).rows[0]?.s === 'filled');
await expectError("Mara can't take it back once teamed up", `update collab_responses set status = 'withdrawn' where post_id = $1 and artist_id = $2`, [C1, MARA_ARTIST]);
await as(SAMPLE_ART);
await expectError("can't team up twice", `select team_up($1, $2)`, [C1, MARA_ARTIST]);
await db.query(`select undo_team_up($1)`, [C1]);
check('undo_team_up: post open again, Mara back to interested',
  (await resp()) === 'applied' && (await db.query(`select status::text s from collab_posts where id = $1`, [C1])).rows[0].s === 'open');
await as(null);
check('anon sees no replies', (await db.query(`select * from collab_responses`)).rows.length === 0);
const anonTeam = (await db.query(`select has_function_privilege('anon', 'team_up(uuid, uuid)', 'execute') a,
  has_function_privilege('anon', 'undo_team_up(uuid)', 'execute') b`)).rows[0];
check('signed-out visitors cannot call team_up or undo_team_up', !anonTeam.a && !anonTeam.b, JSON.stringify(anonTeam));

// --- Reels, likes, follows, saved venues, invitations, uploads ---
await as(null);
const reels = (await db.query(`select * from reel_cards where in_reels order by created_at`)).rows;
check('anon sees the 7 reels, each with its owner', reels.length === 7 && reels.every(r => r.name && r.town), reels.map(r => r.name).join(', '));
const rustyReel = reels.find(r => r.name === 'The Rusty Anchor');
check('a venue reel carries the venue kind, an artist reel the act', rustyReel.venue_kind === 'Bar with a small stage'
  && reels.find(r => r.name === 'DJ Kestrel').act_type === 'DJ');
await as(MARA);
await db.query(`insert into likes (profile_id, media_id) values ($1, $2)`, [MARA, rustyReel.id]);
await db.query(`insert into follows (profile_id, artist_id) values ($1, $2)`, [MARA, KESTREL]);
await db.query(`insert into saved_venues (profile_id, venue_id) values ($1, $2)`, [MARA, rustyReel.venue_id]);
check('Mara can like a reel, follow an artist and save a venue',
  (await db.query(`select (select count(*) from likes) + (select count(*) from follows) + (select count(*) from saved_venues) n`)).rows[0].n == 3);
await db.query(`delete from likes where media_id = $1`, [rustyReel.id]);
check('and unlike it again', (await db.query(`select count(*)::int n from likes`)).rows[0].n === 0);
await expectError("an artist can't send gig invitations",
  `insert into invitations (venue_id, artist_id) values ('10000000-0000-0000-0000-000000000001', $1)`, [KESTREL]);
const clip = (await db.query(`insert into media (artist_id, kind, title, storage_path, in_reels)
  values ($1, 'video', 'New clip', $2, true) returning id`, [MARA_ARTIST, MARA + '/clip.mp4'])).rows[0].id;
check('Mara can add a video to her portfolio and Reels', !!clip);
await expectError("Mara can't add media to DJ Kestrel's portfolio",
  `insert into media (artist_id, kind, storage_path) values ($1, 'video', 'x/y.mp4')`, [KESTREL]);
await as(CORNER);
await db.query(`insert into invitations (venue_id, artist_id) values ('10000000-0000-0000-0000-000000000001', $1)`, [MARA_ARTIST]);
check('a venue can invite an artist to a gig', (await db.query(`select count(*)::int n from invitations`)).rows[0].n === 1);
await as(MARA);
check('the artist sees the invitation', (await db.query(`select count(*)::int n from invitations`)).rows[0].n === 1);
await as(SAMPLE_ART);
check("others don't see it", (await db.query(`select count(*)::int n from invitations`)).rows[0].n === 0);
check("others can't delete Mara's media", (await db.query(`delete from media where id = $1`, [clip])).affectedRows === 0);
await as(MARA);
check('Mara can remove her own media', (await db.query(`delete from media where id = $1`, [clip])).affectedRows === 1);
await as(null);
check("anon sees nobody's follows or saved venues",
  (await db.query(`select (select count(*) from follows) + (select count(*) from saved_venues) n`)).rows[0].n == 0);

// --- RLS: messaging ---
await as(MARA);
const conv = (await db.query(`insert into conversations (created_by, gig_id) values ($1, $2) returning id`, [MARA, GIG_CORNER])).rows[0].id;
await db.query(`insert into conversation_members values ($1, $2), ($1, $3)`, [conv, MARA, CORNER]);
await db.query(`insert into messages (conversation_id, sender_id, body) values ($1, $2, 'Hi! Is there a PA?')`, [conv, MARA]);
check('Mara starts a conversation with the venue', true);
await as(CORNER);
check('venue reads the message', (await db.query(`select body from messages`)).rows.length === 1);
await expectError('venue cannot send a message as Mara',
  `insert into messages (conversation_id, sender_id, body) values ($1, $2, 'spoof')`, [conv, MARA]);
await as(SAMPLE_ART);
check('outsider sees no messages', (await db.query(`select * from messages`)).rows.length === 0);
await expectError('outsider cannot join the conversation',
  `insert into conversation_members values ($1, $2)`, [conv, SAMPLE_ART]);

// --- Personal lists ---
await as(MARA);
const reel = (await db.query(`select id from media where in_reels limit 1`)).rows[0].id;
await db.query(`insert into likes (profile_id, media_id) values ($1, $2)`, [MARA, reel]);
await expectError("can't like on someone else's behalf",
  `insert into likes (profile_id, media_id) values ($1, $2)`, [CORNER, reel]);
await as(null);
check('anon sees no applications', (await db.query(`select * from applications`)).rows.length === 0);

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
