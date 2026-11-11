-- ---------------------------------------------------------------
-- 006: reel_cards view for the Reels feed and portfolios.
--
-- For a database that already ran 005. A fresh setup gets the same
-- result from schema.sql. File storage rules are in db/storage.sql.
-- ---------------------------------------------------------------
begin;

-- ---------------------------------------------------------------
-- Reels feed and portfolios: each media item with its owner's name,
-- act or venue kind, and town. The file itself is in Storage, in the
-- "media" bucket at storage_path ("sample/..." paths have no file).
-- ---------------------------------------------------------------
create view reel_cards with (security_invoker = true) as
select m.id, m.kind, m.title, m.caption, m.storage_path, m.in_reels, m.created_at,
       case when m.artist_id is not null then 'artist' else 'venue' end as owner_kind,
       m.artist_id, m.venue_id,
       coalesce(a.name, v.name) as name,
       a.act_type, a.genres,
       v.kind as venue_kind,
       coalesce(a.town, v.town) as town,
       coalesce(a.lat, v.lat) as lat,
       coalesce(a.lng, v.lng) as lng
from media m
left join artists a on a.id = m.artist_id
left join venues v on v.id = m.venue_id;

commit;
