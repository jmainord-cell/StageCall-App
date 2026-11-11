# Backend setup guide (for Member B)

This is the handoff from the UI side. It explains what the app in `index.html` does today, which parts are fake, and exactly which database call each button needs, so you can connect the UI to Supabase without having to read all of the front-end code.

**Status (Nov 7, 2026):** the UI is finished for the Nov 8 build. Every screen works on sample data in the browser. Nothing talks to the database yet. Your schema in `db/` covers most of it; the gaps are listed in [What the database doesn't cover yet](#what-the-database-doesnt-cover-yet).

---

## 1. Quick start (about 30 minutes)

1. **Create the Supabase project** and run `db/schema.sql`, `db/policies.sql`, then `db/seed.sql`, as described in [`db/README.md`](db/README.md).
2. **Update the seed to the new locations first** (see [section 6](#6-sample-data-needs-new-locations)). The UI moved from made-up Missouri towns to real Arkansas towns, so the old seed won't match what the app shows.
3. **Add the Supabase client** to `index.html`, just above the main `<script>` (keep the version pinned):
   ```html
   <script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.45.4/dist/umd/supabase.min.js"></script>
   ```
4. **Create `api.js`** next to `index.html` (a starter is in [section 4](#4-suggested-apijs)) and load it after the Supabase script. Put the project URL and the **anon** key in it. The anon key is meant to be public. **Never** put the `service_role` key in the front end or in git.
5. **Swap the sample data for real data** one action at a time, using the table in [section 3](#3-every-button-and-the-database-call-it-needs). Start with the gig list, then apply, then review and book.
6. Run through the demo flow in the main [README](README.md#demo-the-full-flow-about-1-minute) to check each step against the database.

---

## 2. How the UI is built

Everything is in **`index.html`**: no build step and no framework.

| Piece | Where | What it does |
|---|---|---|
| `state` | top of the script | All app data: gigs, applications, bookings, likes, the current tab, filters. |
| `view()` and the `...View()` functions | middle | Turn `state` into HTML. They only read `state`. |
| `act(name, el)` | near the bottom | **The one place where things change.** Every button has a `data-act="..."` name, and `act()` has a `case` for each. **This is where your database calls go.** |
| `render()` | after `view()` | Redraws the screen from `state`. Call it after you change `state`. |
| `save()` / `load()` | after `state` | Keep the demo in the browser (`localStorage`). Remove or turn off once real data loads, or keep only for UI settings (tab, filters). |

**The pattern for every action:** call the database, update `state` with what comes back, then `render()`. If the call fails, show the error with `showToast('...')` and leave `state` as it was.

```js
case 'apply': {
  api.apply(id).then(function () {
    state.applied[id] = true;
    showToast('Applied.');
    render();
  }).catch(function (e) { showToast('Could not apply: ' + e.message); render(); });
  return;   // return, not break: render() happens when the call finishes
}
```

### Sample-only data to replace

| In the code | What it fakes | Real source |
|---|---|---|
| `state.gigs` (ids `g1`–`g10`) | venue gigs | `gig_cards` view / `gigs_in_reach()` |
| `state.gigs` (ids `c1`–`c5`, `kind: 'collab'`) | Musicians board posts | **no table yet** (see below) |
| `ME` | "you" as an artist (Mara Voss) | the signed-in user's `artists` row |
| `POOL` | sample applicants per gig, and the artists booked for the sample live shows | `applications` + `artists`, `bookings` + `artists` |
| `RESPONDERS` | fake replies when you post on the Musicians board | **no table yet** |
| `state.bookings` start value (`g2`, `g6`, `g8`, `g9`) | the 4 sample "live shows" on the map | `bookings` |
| `REELS` | the Reels feed | `media` where `in_reels = true` |
| `HOME` | your location (Fayetteville) | the signed-in user's artist or venue `lat`/`lng` |
| The **Venue / Artist** switch in the header | which kind of user you are | `profiles.role` after sign-in |

---

## 3. Every button and the database call it needs

`act()` case names are in `code` font. "Policy OK" means your row-level security already allows it.

### Gigs (artist side)

| Action (`act` case) | Database | Notes |
|---|---|---|
| Load "Gigs near you" | `rpc('gigs_in_reach', { p_artist_id, p_range, p_act })` | `p_range` is `state.range` (`'Town'`, `'Region'`, `'Statewide'`). `p_act` is `state.filter` or `null` for `'All'`. Returns `miles` already. |
| Filter "Applied (N)" (`filter` = `'Mine'`) | `applications` where `artist_id = me` and `status <> 'withdrawn'`, joined to `gig_cards` | |
| **Apply** (`apply`) | `insert into applications (gig_id, artist_id)` | Policy OK. If a withdrawn row exists, `update ... set status = 'applied'` instead (the table has `unique (gig_id, artist_id)`). |
| **Withdraw** (`apply` again) | `update applications set status = 'withdrawn'` | Policy OK. The UI never deletes. |

### Gigs (venue side)

| Action | Database | Notes |
|---|---|---|
| Load "Your gigs" | `gig_cards` where `venue_id` is one of my venues | `applicant_count` is already in the view. |
| **Post gig** (`post`) | `insert into gigs (venue_id, act_type, starts_at, pay_cents, genre, reach, travel)` | Policy OK. See [field conversions](#5-field-conversions) for the date, pay and "Any" style. |
| Open a gig (`review`) | `applications` where `gig_id = X` and `status <> 'withdrawn'`, joined to `artists` | Policy OK (the venue owns the gig). |
| **Book** (`book`) | 1) `insert into bookings (gig_id, artist_id, agreed_pay_cents)` 2) `update applications set status = 'accepted'` for that artist and `'declined'` for the rest 3) `update gigs set status = 'filled'` | Policy OK, but it is 3 writes. Better as one function so it can't half-finish (suggested SQL below). |
| **Undo booking** (`unbook`) | delete the booking, set the gig back to `open`, applications back to `applied` | ⚠️ **Not allowed yet**: no delete policy on `bookings`, and the trigger only lets the *artist* set `applied`. Either add a `cancel_booking` function or hide the button in the real app. |
| **Decline** (`decline`) | `update applications set status = 'declined'` | Policy OK. |
| **Undo decline** (`undecline`) | set it back to `applied` | ⚠️ **Blocked by the trigger** (only the artist may set `applied`). Allow the venue to go `declined → applied`, or hide the Undo link. |

Suggested booking function (not in `db/` yet; your call):

```sql
create function book_artist(p_gig_id uuid, p_artist_id uuid) returns void
language plpgsql security invoker as $$
begin
  insert into bookings (gig_id, artist_id, agreed_pay_cents)
    select id, p_artist_id, pay_cents from gigs where id = p_gig_id;
  update applications set status = case when artist_id = p_artist_id then 'accepted' else 'declined' end::application_status
    where gig_id = p_gig_id and status = 'applied';
  update gigs set status = 'filled' where id = p_gig_id;
end $$;
```
`security invoker` keeps your policies in charge: it only works for the venue that owns the gig.

### Map

| What it shows | Database | Notes |
|---|---|---|
| Open gigs (pink pins) | `gig_cards` where `status = 'open'` | Uses `venue_lat`, `venue_lng`, `venue_town`. |
| Live shows (green pins) | gigs with a booking, plus the booked artist's name | ⚠️ **Not visible to the public yet**: `bookings` is only visible to the two sides, and filled gigs are hidden by "open gigs are public". Add a view, e.g. `live_shows`, that exposes only gig time, venue, town, lat/lng and artist name for `status = 'filled'` gigs. |
| Town bubbles and "By area" list | group the above by `venue_town` | The UI's `TOWNS` list gives each town's center point. Add a town there when a venue is in a new one. |

The map itself needs no backend work: it uses Leaflet and free Esri map tiles, with no API key.

### Musicians board (artist side → Musicians)

⚠️ **No tables yet.** Bands post "looking for a singer or solo act", solo artists post "looking for a band", others tap "I'm interested", and the poster picks one with **Team up** or **Pass**. Suggested tables:

```sql
create type collab_purpose as enum ('Fill-in for a show', 'Opening act', 'Backing band', 'Join my act', 'Jam / session');

create table collab_posts (
  id         uuid primary key default gen_random_uuid(),
  artist_id  uuid not null references artists (id) on delete cascade,  -- who posted
  wants      act_type not null,                                        -- who they're looking for
  purpose    collab_purpose not null,
  when_text  text not null,            -- 'Sat', 'Flexible', 'Ongoing' (free text on purpose)
  pay_text   text not null,            -- '$150', 'Split the door', 'Unpaid'
  genre      text,
  reach      reach_level not null default 'Region',
  note       text,
  status     gig_status not null default 'open',
  created_at timestamptz not null default now()
);

create table collab_responses (
  post_id    uuid not null references collab_posts (id) on delete cascade,
  artist_id  uuid not null references artists (id) on delete cascade,  -- who's interested
  status     application_status not null default 'applied',            -- reuse: applied / withdrawn / accepted / declined
  created_at timestamptz not null default now(),
  primary key (post_id, artist_id)
);
```
Policies would mirror `gigs` and `applications`: open posts are public, the poster manages their post and accepts or declines, the responder applies or withdraws.

| Action (`act` case) | Database |
|---|---|
| Post (`postCollab`) | `insert into collab_posts` |
| I'm interested / Take it back (`apply` on a `c...` id) | `insert into collab_responses` / set `withdrawn` |
| Open your post (`review`) | `collab_responses` + `artists` for that post |
| Team up / Pass (`book` / `decline` on a `c...` id) | set `accepted` / `declined`, post `status = 'filled'` |

### Reels and profiles

| Action (`act` case) | Database | Notes |
|---|---|---|
| Load Reels | `media` where `in_reels`, newest first | Files come from the `media` storage bucket. |
| Heart (`like`) | `insert` / `delete` on `likes` | Policy OK. |
| Follow (`cta`, artist reel, artist side) | `follows` | Policy OK. |
| Invite to a gig (`cta`, artist reel, venue side) | `insert into invitations (venue_id, artist_id)` | Policy OK. |
| Save venue (`cta`, venue reel) | `saved_venues` | Policy OK. |
| Link a social (`social`) | `social_links` | The UI only toggles linked/not linked. A real version needs a URL input (I can add it). |
| + Add video / audio / photo | upload to the `media` bucket, then `insert into media` | Buttons exist; no upload screen yet (I can add it). |

---

## 4. Suggested `api.js`

A thin layer so `index.html` never builds queries itself. Fill these in one at a time.

```js
// api.js: every database call the UI makes, in one place.
var sb = supabase.createClient('https://YOUR-PROJECT.supabase.co', 'YOUR-ANON-KEY');

var api = {
  me: null, // { userId, role, artistId, venueId, lat, lng } after sign-in

  gigsInReach: function (range, act) {
    return sb.rpc('gigs_in_reach', { p_artist_id: api.me.artistId, p_range: range, p_act: act === 'All' ? null : act })
      .then(check);
  },
  myGigs: function () {
    return sb.from('gig_cards').select('*').eq('venue_id', api.me.venueId).then(check);
  },
  postGig: function (row) { return sb.from('gigs').insert(row).select().single().then(check); },
  apply: function (gigId) {
    return sb.from('applications').upsert({ gig_id: gigId, artist_id: api.me.artistId, status: 'applied' }, { onConflict: 'gig_id,artist_id' }).then(check);
  },
  withdraw: function (gigId) {
    return sb.from('applications').update({ status: 'withdrawn' }).eq('gig_id', gigId).eq('artist_id', api.me.artistId).then(check);
  },
  applicants: function (gigId) {
    return sb.from('applications').select('status, artist:artists(id, name, act_type, genres, town)').eq('gig_id', gigId).neq('status', 'withdrawn').then(check);
  },
  book: function (gigId, artistId) { return sb.rpc('book_artist', { p_gig_id: gigId, p_artist_id: artistId }).then(check); },
  decline: function (gigId, artistId) {
    return sb.from('applications').update({ status: 'declined' }).eq('gig_id', gigId).eq('artist_id', artistId).then(check);
  }
};

function check(res) { if (res.error) throw res.error; return res.data; }
```

---

## 5. Field conversions

The UI and the database store a few things differently. Convert in `api.js` so the UI code stays as it is.

| UI (`state.gigs` item) | Database | Convert |
|---|---|---|
| `venue` | `venue_name` | |
| `type` (`'DJ'`, `'Band'`, `'Solo'`, `'Singer'`) | `act_type` | Same strings. |
| `when` (`'Fri · 8 PM'`, `'Tonight · 9 PM'`) | `starts_at` (timestamptz) | **Saving:** the post sheet gives a day (`Tonight`, `Tomorrow`, `Fri`, `Sat`, `Sun`) and a time (`7 PM`–`10 PM`); turn that into the next matching date. **Showing:** "Tonight" if today, else the short weekday, then the time. |
| `pay` (`'$180'`) | `pay_cents` (`18000`) | ×100 / ÷100. |
| `genre` (`'Any'` means no preference) | `genre` (`null` means any) | `'Any'` ↔ `null`. |
| `reach` | `reach` | Same strings. |
| `travel` (`''` means none) | `travel` (`'None'`) | `''` ↔ `'None'`. ⚠️ The sample gigs say `'Gas covered'` and `'Lodging included'`; the enum has `'Gas'` and `'Lodging'`. Use the enum values; the UI shows whatever string it gets. |
| `town`, `lat`, `lng` | `venue_town`, `venue_lat`, `venue_lng` | |
| `dist` (`'33 mi · Eureka Springs'`) | `miles` (from `gigs_in_reach`) | The UI's `withDist()` builds this string from `lat`/`lng`; you can keep that, or format `miles` the same way. |
| `mine: true` | the gig's `venue_id` is one of mine | |
| `state.applied[gigId] = true` | an `applications` row for me with `status = 'applied'` | |
| `state.declined[gigId + ':' + artistId]` | `applications.status = 'declined'` | |
| `state.bookings[gigId] = artistId` | a `bookings` row | |
| applicant `{ id, name, line, where }` | `artists` row | `line` = `"Singer · Jazz & soul"` (act type · genres); `where` = `"12 mi away"`. |

---

## 6. Sample data needs new locations

The UI now uses **real Arkansas places, with home in Fayetteville** (`HOME = 36.0626, -94.1574`). `db/seed.sql` still uses made-up towns around `(38, -92)` in Missouri. Please update the venues to these so the map, distances and range counts match the app:

| Venue (seed id ends in) | Town | lat | lng | Miles from home |
|---|---|---|---|---|
| The Corner Stage (…01) | Fayetteville | 36.0660 | -94.1608 | 0.3 |
| The Rusty Anchor (…02) | Fayetteville | 36.0768 | -94.1612 | 1.0 |
| Velvet Room (…03) | Fayetteville | 36.0905 | -94.1690 | 2.0 |
| Café Lune (…04) | Fayetteville | 36.0545 | -94.1702 | 0.9 |
| Harbor House (…05) | Springdale | 36.1867 | -94.1288 | 8.7 |
| Brick & Barrel (…06) | Fayetteville | 36.0398 | -94.1405 | 1.8 |
| The Grain Elevator (…07) | Eureka Springs | 36.4012 | -93.7379 | 33 |
| Lakeside Lodge (…08) | Harrison | 36.2298 | -93.1077 | 60 |
| Depot Taproom (…09) | Conway | 35.0887 | -92.4421 | 118 |
| County Fair Stage (…10) | Little Rock | 34.7465 | -92.2896 | 139 |

Set `state` to `'AR'`. Mara Voss (the sample artist) lives in Fayetteville; put her at `HOME`.

The range counts stay the same as before (**6** within 15 mi, **8** within 75 mi, **10** statewide), so the checks in `db/test.mjs` should still pass. Run `npm test` in `db/` after editing to make sure.

Musicians board posters (only once those tables exist): The Loose Ends in Springdale (36.1750, -94.1350), Brass Tacks Trio in Rogers (36.3320, -94.1185), Eli Park in Fayetteville (36.0720, -94.1300), Rosa Vale in Harrison (36.2350, -93.1150), DJ Kestrel in Fort Smith (35.3859, -94.3985).

**Sample bookings for the map.** The UI starts with 4 live shows. To match, add bookings (and set those gigs to `filled`):

| Gig | Artist booked |
|---|---|
| The Rusty Anchor, Band, tonight 9 PM (…02) | The Loose Ends |
| Brick & Barrel, Band, Sun 4 PM (…06) | Brass Tacks Trio |
| Lakeside Lodge, Solo, Fri 6 PM (…08) | Eli Park |
| Depot Taproom, DJ, Sat 10 PM (…09) | DJ Kestrel |

The seed only has Mara Voss plus a "sample artists" owner, so these artists need `artists` rows too.

---

## What the database doesn't cover yet

In order of importance for the demo:

1. **Live shows on the map** need a public view (bookings and filled gigs are private today).
2. **Booking in one step:** a `book_artist` function, so a booking can't half-finish.
3. **Undo** for bookings and declines: allow it in the database, or I'll hide the Undo buttons. Tell me which.
4. **Musicians board** tables (`collab_posts`, `collab_responses`).
5. **Sign-in:** the header's Venue/Artist switch is a demo toggle. With accounts, the role comes from `profiles.role`. Supabase email magic links are the easiest fit; I'll design the sign-in screen once you pick the method.
6. **Uploads** (videos, audio, photos) to the `media` bucket.

## Who to ask

UI questions (screens, what a button should do, field formats): Member A. If an action needs a different screen to work with the real data (for example, a URL box for socials, or a sign-in screen), tell me and I'll build it.
