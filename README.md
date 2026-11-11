# Stagecall (prototype)

**Open the app:** https://jmainord-cell.github.io/StageCall-App/

A clickable prototype of a gig marketplace for musicians, DJs, singers, and venues, built for small towns and whole states, not just big cities.

- **Venues** pick what they need (DJ, Band, Solo musician, Singer), set the date, pay, style, how far to reach (town, region, statewide), and whether they can help with travel.
- **Artists** browse gigs in reach, filter by type, and apply. Gigs show distance and travel help. "My applications" shows where each one stands: waiting, booked, or not selected.
- **Musicians find each other** (Artist → Gigs → **Musicians**): a band can post that it needs a singer or a solo act (a fill-in, an opener, a new member), and a solo artist or singer can post that they need a band. Others tap "I'm interested"; the poster reviews them and picks one with **Team up** or **Pass**.
- **Venues review applicants**: tap one of "Your open gigs" to see who applied, then Decline or Book. Booking fills the gig, and every other applicant sees "Not selected".
- **Map** is a real, zoomable map of Arkansas (home is Fayetteville). Open gigs are amber and live shows are teal (a live show is a gig where an artist is booked). Zoomed out you see one bubble per town with counts; zoom in, or tap a town, to see a pin for each venue, and tap a pin for details. Dashed rings mark 15 and 75 mi from you. The layers button switches between **Dark** and **Streets**. Booking an artist in the app turns that gig into a live show on the map.
- **Reels** is a scrolling feed to discover artists (video) and venues (photos).
- **Profiles**: artists get a portfolio and linkable socials; venues get a photo grid and stage details.
- **Accounts**: sign up as an artist or a venue (email + password), then create your profile (name, what you do or book, styles, town). **Profile → My events** shows your upcoming bookings, past events, and what's still waiting (your applications, or your open gigs and how many applied).

Everything is stored in Supabase (see [`db/`](db/README.md)); `api.js` holds every database call. Uploads (videos, audio, venue photos, up to 50 MB each) go to Supabase Storage; choose **Show in Reels** to put one in the feed. Likes, Follow, Save venue, Invite to a gig and social links are saved to your account. The sample reels from the demo have no files, so they show a colored card instead of a video.

## Demo the full flow (about 2 minutes)

Two demo accounts come with history: **Mara Voss** (artist, `mara-voss@example.com`) and **The Corner Stage** (venue, `corner-stage@example.com`). They share one demo password; ask the backend owner for it (it isn't kept in the repo). Use two browsers (or a normal and a private window) to be both at once.

1. As **Mara**: **Profile** shows 1 upcoming show and 2 past ones. In **Gigs**, **Apply** to The Corner Stage's Singer gig.
2. As **The Corner Stage**: **Gigs** → tap **Singer wanted** → Mara is there → **Book** her (or **Decline**, then **Undo**).
3. As **Mara**: refresh. The gig now says "You're booked", and it's under **Upcoming** in Profile.
4. As **Mara**, tap **Musicians** → **I'm interested** on The Loose Ends' "Looking for a singer" post, or **Post what you need**.
5. Or **Create account** to start fresh as a new artist or venue.

The sample gigs move themselves to the coming Fri / Sat / Sun every night at 3 AM (a scheduled job in Supabase, see `db/schedule.sql`), so the demo is always current.

## Accessibility

- Every control is a real button with a visible focus ring, so the whole app works with a keyboard.
- Toggles (chips, likes) report on/off to screen readers; the current tab is marked. Form fields have visible labels.
- Sheets are dialogs: focus moves into them, the page behind is inert, **Esc** closes, and focus returns to the button that opened it.
- Confirmations ("Booked June Harlow.") are announced through a live region.

## Run it

The live version is at https://jmainord-cell.github.io/StageCall-App/ (GitHub Pages publishes the `main` branch).

To run it on your own computer, serve the folder and open it, for example `python3 -m http.server` then http://localhost:8000 (the server has to be running in that folder). No build step and nothing to install. It loads Google Fonts, [Leaflet](https://leafletjs.com) (the map), and [supabase-js](https://supabase.com/docs/reference/javascript) (the database) from the web, so it needs an internet connection. The Supabase anon key in `api.js` is public by design; the database's row-level security protects the data.

## Put it on GitHub Pages

1. Create a repo and add these files (`index.html`, `api.js`, `README.md`).
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
- `HOME` is where "you" are: your profile's town, set when you sign in. Distances are worked out from each venue's `lat` and `lng` (straight-line miles).
- `TOWNS` lists the towns you can pick on your profile, and the map's town bubbles and **By area** list. Add a town here (with its center) to offer it.
- Everything on screen (gigs, applicants, bookings, the Musicians board, Reels, profiles) comes from the database through `api.js`.

## Not built yet

Editing your profile after sign-up, seeing gig invitations as an artist, messaging, payments and deposits, and a fan/listener role. The database is in [`db/`](db/README.md); [`BACKEND_SETUP.md`](BACKEND_SETUP.md) is the original UI-to-database handoff.
