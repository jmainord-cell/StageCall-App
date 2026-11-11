// ---------------------------------------------------------------
// api.js: every database call Stagecall makes, in one place.
//
// index.html never builds queries itself. It calls api.* and gets back
// objects in the same shape the app always used (gig.when = 'Fri · 8 PM',
// gig.pay = '$180', gig.genre = 'Any', ...), so the screens didn't change.
//
// The anon key below is public by design: Supabase's row-level security
// (db/policies.sql) is what decides who can read and change what.
// Never put the service_role key in this file.
// ---------------------------------------------------------------
(function () {
  var SUPABASE_URL = 'https://nzampioybjpizulyckzp.supabase.co';
  var SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im56YW1waW95YmpwaXp1bHlja3pwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTQwODAxNTgsImV4cCI6MjEwOTY1NjE1OH0.EIx71hCZ2o9YM-GpXFM1anyZz48N0uaI6xYanz2RRJk';

  if (!window.supabase) {
    window.api = null;   // offline or blocked CDN: index.html shows a message
    return;
  }
  var sb = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

  function check(res) { if (res.error) throw res.error; return res.data; }

  // ---------------------------------------------------------------
  // Conversions between the database and the app
  // ---------------------------------------------------------------
  var DAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

  function payText(cents) { return cents == null ? '' : '$' + Math.round(cents / 100); }
  function payCents(text) { return Math.round(parseFloat(String(text).replace(/[^0-9.]/g, '')) * 100); }

  function clock(d) {
    var h = d.getHours(), m = d.getMinutes();
    return ((h % 12) || 12) + (m ? ':' + String(m).padStart(2, '0') : '') + ' ' + (h < 12 ? 'AM' : 'PM');
  }
  function dayStart(d) { var x = new Date(d); x.setHours(0, 0, 0, 0); return x; }
  // '2026-11-13T02:00:00Z' -> 'Tonight · 8 PM', 'Sat · 7 PM', or 'Nov 20 · 8 PM' further out / in the past
  function whenText(iso) {
    var d = new Date(iso);
    var days = Math.round((dayStart(d) - dayStart(new Date())) / 864e5);
    var day;
    if (days === 0) day = d.getHours() >= 17 ? 'Tonight' : 'Today';
    else if (days === 1) day = 'Tomorrow';
    else if (days > 1 && days < 7) day = DAYS[d.getDay()];
    else day = d.toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
    return day + ' · ' + clock(d);
  }
  // Post-sheet chips -> a real time: 'Tonight' = today, 'Tomorrow', 'Fri' = the next Friday
  function startsAt(dayChip, timeChip) {
    var d = dayStart(new Date());
    if (dayChip === 'Tomorrow') d.setDate(d.getDate() + 1);
    else if (dayChip !== 'Tonight') {
      var want = DAYS.indexOf(dayChip);
      d.setDate(d.getDate() + (((want - d.getDay()) + 7) % 7 || 7));
    }
    var m = /^(\d+)(?::(\d+))?\s*(AM|PM)$/i.exec(timeChip);
    d.setHours((+m[1] % 12) + (m[3].toUpperCase() === 'PM' ? 12 : 0), +(m[2] || 0));
    return d.toISOString();
  }

  function artistLine(actType, genres) {
    return (TYPE_LABEL[actType] || actType) + (genres && genres.length ? ' · ' + genres.join(' & ') : '');
  }
  function bgFor(id) { return THUMBS[hash(String(id)) % THUMBS.length]; }
  function milesFrom(lat, lng) {
    if (lat == null) return '';
    var mi = milesBetween(HOME, { lat: lat, lng: lng });
    return (mi < 10 ? mi.toFixed(1) : Math.round(mi)) + ' mi away';
  }
  // an artists row -> the applicant shape the review sheet uses
  function applicant(a) {
    return { id: a.id, name: a.name, line: artistLine(a.act_type, a.genres), where: milesFrom(a.lat, a.lng), bg: bgFor(a.id) };
  }
  var SHOW_FOR = 4 * 3600e3;   // a show counts as current until 4 hours after it starts (same as live_shows)

  var api = {
    sb: sb,
    me: null,   // { userId, email, role, displayName, artist, venue } once signed in
    whenText: whenText,
    payText: payText,

    // -------------------------------------------------------------
    // Accounts
    // -------------------------------------------------------------
    session: function () {
      return sb.auth.getSession().then(function (r) { return r.data.session; });
    },
    signIn: function (email, password) {
      return sb.auth.signInWithPassword({ email: email, password: password }).then(check);
    },
    // role ('artist' | 'venue') and display name go into the account; the
    // sign-up trigger copies them into profiles.
    signUp: function (email, password, role, displayName) {
      return sb.auth.signUp({ email: email, password: password, options: { data: { role: role, display_name: displayName } } })
        .then(check)
        .then(function (data) {
          if (!data.session) throw new Error('Check your email to confirm your account, then sign in.');
          return data;
        });
    },
    signOut: function () { return sb.auth.signOut(); },

    // Who is signed in, and their artist or venue profile (null until they make one)
    loadMe: function () {
      return sb.auth.getUser().then(check).then(function (data) {
        var user = data.user;
        return Promise.all([
          sb.from('profiles').select('role, display_name').eq('id', user.id).single().then(check),
          sb.from('artists').select('*').eq('owner_id', user.id).order('created_at').limit(1).then(check),
          sb.from('venues').select('*').eq('owner_id', user.id).order('created_at').limit(1).then(check)
        ]).then(function (r) {
          api.me = { userId: user.id, email: user.email, role: r[0].role, displayName: r[0].display_name, artist: r[1][0] || null, venue: r[2][0] || null,
                     socials: [], media: [] };
          var a = api.me.artist, v = api.me.venue;
          // your linked socials and your own portfolio / photos
          return Promise.all([
            a ? sb.from('social_links').select('platform, url').eq('artist_id', a.id).then(check) : [],
            a || v ? sb.from('media').select('id, kind, title, caption, storage_path, in_reels').eq(a ? 'artist_id' : 'venue_id', (a || v).id).order('created_at').then(check) : []
          ]).then(function (m) {
            api.me.socials = m[0];
            api.me.media = m[1].map(function (x) { x.url = api.mediaUrl(x.storage_path); return x; });
            return api.me;
          });
        });
      });
    },
    // the account's display name follows the artist / venue name you pick
    setDisplayName: function (name) {
      return sb.from('profiles').update({ display_name: name }).eq('id', api.me.userId).then(check);
    },
    createArtist: function (p) {
      return api.setDisplayName(p.name).then(function () { return sb.from('artists').insert({
        owner_id: api.me.userId, name: p.name, act_type: p.actType, genres: p.genres, bio: p.bio || null,
        town: p.town, state: 'AR', lat: TOWNS[p.town].lat, lng: TOWNS[p.town].lng
      }).select().single(); }).then(check);
    },
    createVenue: function (p) {
      return api.setDisplayName(p.name).then(function () { return sb.from('venues').insert({
        owner_id: api.me.userId, name: p.name, kind: p.kind || null, about: p.about || null,
        equipment: p.equipment, books: p.books,
        town: p.town, state: 'AR', lat: TOWNS[p.town].lat, lng: TOWNS[p.town].lng
      }).select().single(); }).then(check);
    },

    // -------------------------------------------------------------
    // Everything the screens show, in the app's own shapes:
    //   gigs     venue gigs + Musicians board posts + live shows (state.gigs)
    //   pool     gig/post id -> applicants or replies (POOL)
    //   applied  gig/post id -> true if I applied / replied (state.applied)
    //   bookings gig/post id -> booked artist id, or 'me' (state.bookings)
    //   declined 'id:artistId' or 'id:me' -> true (state.declined)
    // -------------------------------------------------------------
    loadAll: function () {
      var me = api.me;
      var myArtist = me.artist ? me.artist.id : null;
      var myVenue = me.venue ? me.venue.id : null;
      var since = new Date(Date.now() - SHOW_FOR).toISOString();
      var out = { gigs: [], pool: {}, applied: {}, bookings: {}, declined: {} };
      var who = function (artistId) { return artistId === myArtist ? 'me' : artistId; };
      var none = Promise.resolve([]);

      return Promise.all([
        sb.from('gig_cards').select('*').gte('starts_at', since).order('starts_at').then(check),
        sb.from('live_shows').select('*').then(check),
        sb.from('collab_cards').select('*').order('created_at', { ascending: false }).then(check),
        myArtist ? sb.from('applications').select('gig_id, status').eq('artist_id', myArtist).then(check) : none,
        myArtist ? sb.from('bookings').select('gig_id').eq('artist_id', myArtist).then(check) : none,
        myArtist ? sb.from('collab_responses').select('post_id, status').eq('artist_id', myArtist).then(check) : none
      ]).then(function (r) {
        var cards = r[0], live = r[1], posts = r[2], myApps = r[3], myBookings = r[4], myReplies = r[5];

        cards.forEach(function (c) {
          out.gigs.push(withDist({
            id: c.id, venue: c.venue_name, type: c.act_type, when: whenText(c.starts_at), pay: payText(c.pay_cents),
            genre: c.genre || 'Any', reach: c.reach, travel: c.travel === 'None' ? '' : c.travel,
            town: c.venue_town, lat: c.venue_lat, lng: c.venue_lng, mine: c.venue_id === myVenue,
            applicants: c.applicant_count, startsAt: c.starts_at, status: c.status
          }));
        });
        // live shows I can't otherwise see (someone else's booked gig) still go on the map
        live.forEach(function (s) {
          var known = out.gigs.filter(function (g) { return g.id === s.gig_id; })[0];
          if (known && known.mine) return;   // my own venue's gig: its applicants and booking load below
          if (!known) {
            out.gigs.push(withDist({
              id: s.gig_id, venue: s.venue_name, type: s.act_type, when: whenText(s.starts_at), pay: '', genre: '',
              town: s.venue_town, lat: s.venue_lat, lng: s.venue_lng, mine: false, startsAt: s.starts_at, status: 'filled'
            }));
          }
          out.bookings[s.gig_id] = who(s.artist_id);
          if (s.artist_id !== myArtist) out.pool[s.gig_id] = [{ id: s.artist_id, name: s.artist_name, line: TYPE_LABEL[s.act_type] || '', where: '', bg: bgFor(s.artist_id) }];
        });
        posts.forEach(function (p) {
          out.gigs.push(withDist({
            id: p.id, kind: 'collab', venue: p.poster_name, byLine: artistLine(p.poster_act_type, p.poster_genres), bg: bgFor(p.artist_id),
            type: p.wants, purpose: p.purpose, when: p.when_text, pay: p.pay_text, genre: p.genre || 'Any', reach: p.reach,
            town: p.poster_town, lat: p.poster_lat, lng: p.poster_lng, note: p.note || '', mine: p.artist_id === myArtist,
            responders: [], status: p.status
          }));
        });

        // my side as an artist
        myApps.forEach(function (a) {
          if (a.status === 'withdrawn') return;
          out.applied[a.gig_id] = true;
          if (a.status === 'declined') out.declined[a.gig_id + ':me'] = true;
        });
        myBookings.forEach(function (b) { out.bookings[b.gig_id] = 'me'; });
        myReplies.forEach(function (x) {
          if (x.status === 'withdrawn') return;
          out.applied[x.post_id] = true;
          if (x.status === 'declined') out.declined[x.post_id + ':me'] = true;
          if (x.status === 'accepted') out.bookings[x.post_id] = 'me';
        });

        // my side as a venue / poster: who applied to my gigs and replied to my posts
        var myGigIds = out.gigs.filter(function (g) { return g.mine && !g.kind; }).map(function (g) { return g.id; });
        var myPostIds = out.gigs.filter(function (g) { return g.mine && g.kind === 'collab'; }).map(function (g) { return g.id; });
        var ART = 'artist:artists(id, name, act_type, genres, lat, lng)';
        return Promise.all([
          myGigIds.length ? sb.from('applications').select('gig_id, status, ' + ART).in('gig_id', myGigIds).neq('status', 'withdrawn').then(check) : none,
          myGigIds.length ? sb.from('bookings').select('gig_id, artist_id').in('gig_id', myGigIds).then(check) : none,
          myPostIds.length ? sb.from('collab_responses').select('post_id, status, ' + ART).in('post_id', myPostIds).neq('status', 'withdrawn').then(check) : none
        ]).then(function (r2) {
          r2[0].forEach(function (a) {
            (out.pool[a.gig_id] = out.pool[a.gig_id] || []).push(applicant(a.artist));
            if (a.status === 'declined') out.declined[a.gig_id + ':' + a.artist.id] = true;
          });
          r2[1].forEach(function (b) { out.bookings[b.gig_id] = b.artist_id; });
          r2[2].forEach(function (x) {
            var post = out.gigs.filter(function (g) { return g.id === x.post_id; })[0];
            post.responders.push(applicant(x.artist));
            if (x.status === 'declined') out.declined[x.post_id + ':' + x.artist.id] = true;
            if (x.status === 'accepted') out.bookings[x.post_id] = x.artist.id;
          });
          return out;
        });
      });
    },

    // -------------------------------------------------------------
    // Reels: the feed, and what you've liked / followed / saved / invited
    // -------------------------------------------------------------
    // Public link to an uploaded file. Sample rows ("sample/...") have no file.
    mediaUrl: function (path) {
      if (!path || /^sample\//.test(path)) return null;
      return sb.storage.from('media').getPublicUrl(path).data.publicUrl;
    },
    loadReels: function () {
      var me = api.me, none = Promise.resolve([]);
      return Promise.all([
        sb.from('reel_cards').select('*').eq('in_reels', true).order('created_at', { ascending: false }).then(check),
        sb.from('likes').select('media_id').eq('profile_id', me.userId).then(check),
        sb.from('follows').select('artist_id').eq('profile_id', me.userId).then(check),
        sb.from('saved_venues').select('venue_id').eq('profile_id', me.userId).then(check),
        me.venue ? sb.from('invitations').select('artist_id').eq('venue_id', me.venue.id).then(check) : none
      ]).then(function (r) {
        var set = function (rows, key) { var o = {}; rows.forEach(function (x) { o[x[key]] = true; }); return o; };
        return {
          reels: r[0].map(function (m) {
            var artist = m.owner_kind === 'artist';
            return {
              id: m.id, kind: m.owner_kind, mediaKind: m.kind, ownerId: artist ? m.artist_id : m.venue_id,
              mine: artist ? !!(me.artist && me.artist.id === m.artist_id) : !!(me.venue && me.venue.id === m.venue_id),
              name: m.name, line: artist ? artistLine(m.act_type, m.genres) : (m.venue_kind || 'Venue'),
              where: null, town: m.town || '', lat: m.lat, lng: m.lng, caption: m.caption || m.title || '',
              bg: bgFor(m.id), url: api.mediaUrl(m.storage_path)
            };
          }).map(function (x) { x.where = x.mine ? x.town : (milesFrom(x.lat, x.lng) || x.town); return x; }),
          liked: set(r[1], 'media_id'), following: set(r[2], 'artist_id'), saved: set(r[3], 'venue_id'), invited: set(r[4], 'artist_id')
        };
      });
    },
    like: function (mediaId, on) {
      return (on ? sb.from('likes').insert({ profile_id: api.me.userId, media_id: mediaId })
                 : sb.from('likes').delete().eq('profile_id', api.me.userId).eq('media_id', mediaId)).then(check);
    },
    follow: function (artistId, on) {
      return (on ? sb.from('follows').insert({ profile_id: api.me.userId, artist_id: artistId })
                 : sb.from('follows').delete().eq('profile_id', api.me.userId).eq('artist_id', artistId)).then(check);
    },
    saveVenue: function (venueId, on) {
      return (on ? sb.from('saved_venues').insert({ profile_id: api.me.userId, venue_id: venueId })
                 : sb.from('saved_venues').delete().eq('profile_id', api.me.userId).eq('venue_id', venueId)).then(check);
    },
    invite: function (artistId) {
      return sb.from('invitations').insert({ venue_id: api.me.venue.id, artist_id: artistId }).then(check);
    },

    // -------------------------------------------------------------
    // Profile: social links and uploads
    // -------------------------------------------------------------
    setSocial: function (platform, url) {
      return sb.from('social_links').upsert({ artist_id: api.me.artist.id, platform: platform, url: url }, { onConflict: 'artist_id,platform' }).then(check);
    },
    removeSocial: function (platform) {
      return sb.from('social_links').delete().eq('artist_id', api.me.artist.id).eq('platform', platform).then(check);
    },
    // file goes to media/<your user id>/<random>.<ext>, then a media row points at it
    upload: function (file, kind, title, caption, inReels) {
      var ext = (file.name.split('.').pop() || 'bin').toLowerCase().replace(/[^a-z0-9]/g, '');
      var path = api.me.userId + '/' + (crypto.randomUUID ? crypto.randomUUID() : Date.now().toString(36)) + '.' + ext;
      var owner = api.me.artist ? { artist_id: api.me.artist.id } : { venue_id: api.me.venue.id };
      return sb.storage.from('media').upload(path, file, { contentType: file.type, upsert: false }).then(check).then(function () {
        return sb.from('media').insert(Object.assign({ kind: kind, title: title || null, caption: caption || null, storage_path: path, in_reels: inReels }, owner)).then(function (res) {
          if (res.error) {   // don't leave an orphan file behind
            return sb.storage.from('media').remove([path]).then(function () { throw res.error; });
          }
          return res.data;
        });
      });
    },
    removeMedia: function (item) {
      return sb.from('media').delete().eq('id', item.id).then(check).then(function () {
        if (api.mediaUrl(item.storage_path)) return sb.storage.from('media').remove([item.storage_path]).then(check);
      });
    },

    // "My events" on the Profile tab (db: my_events())
    myEvents: function () { return sb.rpc('my_events').then(check); },

    // -------------------------------------------------------------
    // Venue gigs
    // -------------------------------------------------------------
    postGig: function (type, f) {
      return sb.from('gigs').insert({
        venue_id: api.me.venue.id, act_type: type, starts_at: startsAt(f.date, f.time), pay_cents: payCents(f.pay),
        genre: f.genre === 'Any' ? null : f.genre, reach: f.reach, travel: f.travel
      }).select('id').single().then(check);
    },
    apply: function (gigId) {
      return sb.from('applications').upsert({ gig_id: gigId, artist_id: api.me.artist.id, status: 'applied' }, { onConflict: 'gig_id,artist_id' }).then(check);
    },
    withdraw: function (gigId) {
      return sb.from('applications').update({ status: 'withdrawn' }).eq('gig_id', gigId).eq('artist_id', api.me.artist.id).then(check);
    },
    book: function (gigId, artistId) { return sb.rpc('book_artist', { p_gig_id: gigId, p_artist_id: artistId }).then(check); },
    cancelBooking: function (gigId) { return sb.rpc('cancel_booking', { p_gig_id: gigId }).then(check); },
    setApplication: function (gigId, artistId, status) {   // 'declined', or back to 'applied' (undo)
      return sb.from('applications').update({ status: status }).eq('gig_id', gigId).eq('artist_id', artistId).then(check);
    },

    // -------------------------------------------------------------
    // Musicians board
    // -------------------------------------------------------------
    postCollab: function (f) {
      return sb.from('collab_posts').insert({
        artist_id: api.me.artist.id, wants: f.want, purpose: f.purpose, when_text: f.date, pay_text: f.pay,
        genre: f.genre === 'Any' ? null : f.genre, reach: f.reach
      }).select('id').single().then(check);
    },
    reply: function (postId) {
      return sb.from('collab_responses').upsert({ post_id: postId, artist_id: api.me.artist.id, status: 'applied' }, { onConflict: 'post_id,artist_id' }).then(check);
    },
    unreply: function (postId) {
      return sb.from('collab_responses').update({ status: 'withdrawn' }).eq('post_id', postId).eq('artist_id', api.me.artist.id).then(check);
    },
    teamUp: function (postId, artistId) { return sb.rpc('team_up', { p_post_id: postId, p_artist_id: artistId }).then(check); },
    undoTeamUp: function (postId) { return sb.rpc('undo_team_up', { p_post_id: postId }).then(check); },
    setReply: function (postId, artistId, status) {
      return sb.from('collab_responses').update({ status: status }).eq('post_id', postId).eq('artist_id', artistId).then(check);
    }
  };

  window.api = api;
})();
