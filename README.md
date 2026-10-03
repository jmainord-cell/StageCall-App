# Stagecall (prototype)

A clickable prototype of a gig marketplace for musicians, DJs, singers, and venues, built for small towns and whole states, not just big cities.

- **Venues** pick what they need (DJ, Band, Solo musician, Singer), set the date, pay, style, how far to reach (town, region, statewide), and whether they can help with travel.
- **Artists** browse gigs in reach, filter by type, and apply. Gigs show distance and travel help.
- **Reels** is a scrolling feed to discover artists (video) and venues (photos).
- **Profiles**: artists get a portfolio and linkable socials; venues get a photo grid and stage details.

Everything is sample data held in memory. There is no backend, accounts, or real uploads yet, so a refresh resets it.

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

Accounts and login, real uploads (video, audio, photos), messaging, payments and deposits, a fan/listener role, and a real database.
