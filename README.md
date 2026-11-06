# Stagecall (prototype)

A clickable prototype of a gig marketplace for musicians, DJs, singers, and venues, built for small towns and whole states, not just big cities.

- **Venues** pick what they need (DJ, Band, Solo musician, Singer), set the date, pay, style, how far to reach (town, region, statewide), and whether they can help with travel.
- **Artists** browse gigs in reach, filter by type, and apply. Gigs show distance and travel help. "My applications" shows where each one stands: waiting, booked, or not selected.
- **Musicians find each other** (Artist → Gigs → **Musicians**): a band can post that it needs a singer or a solo act (a fill-in, an opener, a new member), and a solo artist or singer can post that they need a band. Others tap "I'm interested"; the poster reviews them and picks one with **Team up** or **Pass**.
- **Venues review applicants**: tap one of "Your open gigs" to see who applied, then Decline or Book. Booking fills the gig, and every other applicant sees "Not selected".
- **Reels** is a scrolling feed to discover artists (video) and venues (photos).
- **Profiles**: artists get a portfolio and linkable socials; venues get a photo grid and stage details.

Everything is sample data. There is no backend, accounts, or real uploads yet. What you do is saved in this browser (localStorage) so a refresh keeps it; **Profile → Reset demo data** starts over.

## Demo the full flow (about 1 minute)

1. **Venue** → tap **Band** → set pay and travel (the preview updates) → **Post gig**.
2. Switch to **Artist** → **Apply** to "The Corner Stage" gigs.
3. Switch to **Venue** → tap **Singer wanted** → you'll see two sample applicants plus yourself → **Book** one.
4. Switch to **Artist** → that gig now says "You're booked" or "Not selected this time".
5. Still as **Artist**, tap **Musicians** at the top → **Post what you're looking for** → pick **Band** → **Post**. Two sample bands reply; tap your post and **Team up** with one. You can also tap **I'm interested** on a band's "Looking for a singer" post.

The Musicians board has no table in `db/` yet. It needs either artist-posted gigs or a separate posts table plus a "responses" table (see `applications`).

## Accessibility

- Every control is a real button with a visible focus ring, so the whole app works with a keyboard.
- Toggles (chips, Venue/Artist, likes) report on/off to screen readers; the current tab is marked.
- Sheets are dialogs: focus moves into them, the page behind is inert, **Esc** closes, and focus returns to the button that opened it.
- Confirmations ("Booked June Harlow.") are announced through a live region.

## Run it

Open `index.html` in a browser. No build step, no dependencies (it only loads two Google Fonts).

## Put it on GitHub Pages

1. Create a repo and add these files (`index.html`, `README.md`).
2. In the repo go to **Settings → Pages**.
3. Set **Source** to "Deploy from a branch", choose `main` and `/ (root)`, and save.
4. After a minute the site is live at `https://<your-username>.github.io/<repo-name>/`.

## Easy things to change

All in `index.html`:

- `--accent` in the CSS `:root` block sets the main color.
- `RANGE_MILES` sets how many miles "My town", "My region", and "Statewide" cover.
- `state.gigs` and `REELS` hold the sample gigs and reels.

## Not built yet

Accounts and login, real uploads (video, audio, photos), messaging, payments and deposits, and a fan/listener role. The app does not use a database yet; the schema for one is in [`db/`](db/README.md) (Supabase/PostgreSQL), ready to connect.
