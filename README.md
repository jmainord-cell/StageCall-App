# Stagecall (prototype)

A clickable prototype of a gig marketplace for musicians, DJs, singers, and venues, built for small towns and whole states, not just big cities.

- **Venues** pick what they need (DJ, Band, Solo musician, Singer), set the date, pay, style, how far to reach (town, region, statewide), and whether they can help with travel.
- **Artists** browse gigs in reach, filter by type, and apply. Gigs show distance and travel help. "My applications" shows where each one stands: waiting, booked, or not selected.
- **Musicians find each other** (Artist → Gigs → **Musicians**): a band can post that it needs a singer or a solo act (a fill-in, an opener, a new member), and a solo artist or singer can post that they need a band. Others tap "I'm interested"; the poster reviews them and picks one with **Team up** or **Pass**.
- **Venues review applicants**: tap one of "Your open gigs" to see who applied, then Decline or Book. Booking fills the gig, and every other applicant sees "Not selected".
- **Map** is a real, zoomable map of Arkansas (home is Fayetteville). Open gigs are amber and live shows are teal (a live show is a gig where an artist is booked). Zoomed out you see one bubble per town with counts; zoom in, or tap a town, to see a pin for each venue, and tap a pin for details. Dashed rings mark 15 and 75 mi from you. The layers button switches between **Dark** and **Streets**. Booking an artist in the app turns that gig into a live show on the map.
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

Open `index.html` in a browser. No build step and nothing to install. It loads two Google Fonts and [Leaflet](https://leafletjs.com) (the open-source map library) from the web, and the map tiles come from Esri's free basemaps, so the Map tab needs an internet connection (everything else works offline). No API keys are needed.

## Put it on GitHub Pages

1. Create a repo and add these files (`index.html`, `README.md`).
2. In the repo go to **Settings → Pages**.
3. Set **Source** to "Deploy from a branch", choose `main` and `/ (root)`, and save.
4. After a minute the site is live at `https://<your-username>.github.io/<repo-name>/`.

## Easy things to change

All in `index.html`:

- The look is "punk show flyers": photocopy white and black, plus a few loud colors at full strength. All colors are tokens in the CSS `:root` block. `--accent` (hot pink) is the main color, `--teal` (toxic green) marks live shows and bookings, `--hi` is acid yellow, and `--blue` is the red marker used for handwritten notes and stamps. Image blocks use hot pink, acid yellow, toxic green, cherry red and electric cyan, and the map is shown in black and white like a photocopy. Fonts are Anton (poster headlines), Archivo (body), Space Mono (dates, prices, tags) and Caveat (handwritten notes), all from Google Fonts.
- The screens sit on a punk club wall: old poster scraps, marker X's, pink spray flecks and photocopy grit (`--scraps`), edged with hazard tape. Titles and the logo are ransom-note letters cut from different "magazines" (`ransom()`; screen readers get the plain words). Section headings are label-maker tape, and stickers (starbursts, a smiley, a barcode) are slapped around the margins by `wallStickers()`. Flyers cast hot pink, yellow or white shadows, and pop-up sheets stay paper for easy reading.
- Flyers get random wear and tear from `deco()`: a fold crease or a coffee ring, and duct tape, masking tape, a safety pin or a staple.
- It's meant to look handmade: ink outlines wobble slightly (an SVG "rough" filter in `<body>`), and each flyer's tilt, tape, or push pin comes from its id (`paper()`), so no two hang the same way.
- Motion: flyers lift off the wall on hover, buttons press like stamps, stickers wiggle, confirmations slap on, sheets slide up like paper, and cards pin themselves up when a screen opens. Hover effects only run with a mouse, and everything switches off when the device asks for reduced motion.
- `RANGE_MILES` sets how many miles "My town", "My region", and "Statewide" cover.
- `HOME` is where "you" are (Fayetteville). Each sample gig has a `town`, `lat` and `lng`, and distances are worked out from those (straight-line miles), so moving a venue on the map also changes its distance in Gigs.
- `TOWNS` lists the towns used for the map's town bubbles and the **By area** list. Add a town here if you give a gig a new `town`.
- `state.gigs` and `REELS` hold the sample gigs and reels.

## Not built yet

Accounts and login, real uploads (video, audio, photos), messaging, payments and deposits, and a fan/listener role. The app does not use a database yet; the schema for one is in [`db/`](db/README.md) (Supabase/PostgreSQL), ready to connect. **To hook the UI up to it, start with [`BACKEND_SETUP.md`](BACKEND_SETUP.md)**: every button and the database call it needs, field conversions, updated sample locations, and what the schema doesn't cover yet.
