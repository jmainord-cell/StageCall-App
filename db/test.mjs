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
`);

for (const f of ['schema.sql', 'policies.sql', 'seed.sql']) {
  try { await db.exec(readFileSync(new URL(f, DB), 'utf8')); check(`load ${f}`, true); }
  catch (e) { check(`load ${f}`, false, e.message); process.exit(1); }
}
await db.exec(`
  grant usage on schema public, auth to anon, authenticated;
  grant all on all tables in schema public to anon, authenticated;
  grant execute on all functions in schema public, auth to anon, authenticated;
`);

// --- Data loaded ---
const counts = (await db.query(`select
  (select count(*) from profiles)::int p, (select count(*) from venues)::int v,
  (select count(*) from artists)::int a, (select count(*) from gigs)::int g,
  (select count(*) from media where in_reels)::int r`)).rows[0];
check('signup trigger made 4 profiles', counts.p === 4, JSON.stringify(counts));
check('10 venues, 4 artists, 10 gigs, 7 reels', counts.v === 10 && counts.a === 4 && counts.g === 10 && counts.r === 7);
const roles = (await db.query(`select role::text from profiles where id = $1`, [CORNER])).rows[0].role;
check('profile role comes from sign-up metadata', roles === 'venue', roles);

// --- Distance filters: same counts the prototype shows for Mara ---
const reach = async (artist, range, act = null) =>
  (await db.query(`select * from gigs_in_reach($1, $2, $3)`, [artist, range, act])).rows;
const town = await reach(MARA_ARTIST, 'Town');
check('Mara / Town = 6 gigs (matches prototype)', town.length === 6, town.map(r => r.venue_name).join(', '));
check('Mara / Region = 8 gigs (matches prototype)', (await reach(MARA_ARTIST, 'Region')).length === 8);
check('Mara / Statewide = 10 gigs (matches prototype)', (await reach(MARA_ARTIST, 'Statewide')).length === 10);
check('nearest gig is listed first', town[0].venue_name === 'The Corner Stage', `${town[0].venue_name} ${town[0].miles.toFixed(2)} mi`);
const miles = (await db.query(`select miles_between(38, -92, 38 + 38/69.09, -92) m`)).rows[0].m;
check('Grain Elevator is ~38 mi away', Math.abs(miles - 38) < 0.1, miles.toFixed(2));
const kes = await reach(KESTREL, 'Statewide');
check('Kestrel (55 mi out) / Statewide = 6: venue Town/Region limits respected', kes.length === 6, kes.map(r => r.venue_name).join(', '));
check('Kestrel / Statewide / DJ only = 2', (await reach(KESTREL, 'Statewide', 'DJ')).length === 2);

// --- RLS: browsing ---
await as(null);
check('anon can browse open gigs', (await db.query(`select * from gig_cards`)).rows.length === 10);
await asAdmin();
await db.query(`insert into applications (gig_id, artist_id) values ($1, $2)`, [GIG_RUSTY, ELI]);

// --- RLS: applying ---
await as(MARA);
await db.query(`insert into applications (gig_id, artist_id) values ($1, $2)`, [GIG_CORNER, MARA_ARTIST]);
check('Mara can apply as her own act', true);
await expectError('Mara cannot apply as DJ Kestrel', `insert into applications (gig_id, artist_id) values ($1, $2)`, [GIG_CORNER, KESTREL]);
check("Mara cannot see other artists' applications", (await db.query(`select * from applications`)).rows.length === 1);
await expectError('Mara cannot accept her own application',
  `update applications set status = 'accepted' where artist_id = $1`, [MARA_ARTIST]);
await expectError('Mara cannot move her application to another gig',
  `update applications set gig_id = $1 where artist_id = $2`, [GIG_RUSTY, MARA_ARTIST]);
await db.query(`update applications set status = 'withdrawn' where artist_id = $1`, [MARA_ARTIST]);
await db.query(`update applications set status = 'applied' where artist_id = $1`, [MARA_ARTIST]);
check('Mara can withdraw and re-apply', true);

// --- RLS: venue side ---
await as(CORNER);
const cards = (await db.query(`select applicant_count::int n from gig_cards where id = $1`, [GIG_CORNER])).rows[0];
check('venue sees applicant count on its gig', cards.n === 1, `n=${cards.n}`);
check("Corner Stage can't see applications to other venues' gigs", (await db.query(`select * from applications`)).rows.length === 1);
await db.query(`update applications set status = 'accepted' where gig_id = $1`, [GIG_CORNER]);
check('venue can accept an applicant', (await db.query(`select status::text s from applications where gig_id = $1`, [GIG_CORNER])).rows[0].s === 'accepted');
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
check('artist can see her booking', (await db.query(`select * from bookings`)).rows.length === 1);

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
