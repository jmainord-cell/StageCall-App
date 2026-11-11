-- ---------------------------------------------------------------
-- Stagecall file storage (Supabase only; run after policies.sql).
--
-- Uploads (portfolio videos and audio, venue photos, reels) go in the
-- public "media" bucket. Anyone can view a file by its public URL, but
-- you can only add or delete files in your own folder:
--   media/<your user id>/<file>
-- The media table row (db/schema.sql) points at the file.
-- 50 MB per file is the Supabase free-plan maximum.
-- ---------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('media', 'media', true, 52428800, array[
  'video/mp4', 'video/quicktime', 'video/webm',
  'audio/mpeg', 'audio/mp4', 'audio/x-m4a', 'audio/aac', 'audio/wav', 'audio/x-wav', 'audio/webm', 'audio/ogg',
  'image/jpeg', 'image/png', 'image/webp', 'image/gif'])
on conflict (id) do update set public = excluded.public, file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

create policy "media: upload to own folder" on storage.objects for insert to authenticated
  with check (bucket_id = 'media' and (storage.foldername(name))[1] = (select auth.uid()::text));
create policy "media: see own files"        on storage.objects for select to authenticated
  using (bucket_id = 'media' and (storage.foldername(name))[1] = (select auth.uid()::text));
create policy "media: delete own files"     on storage.objects for delete to authenticated
  using (bucket_id = 'media' and (storage.foldername(name))[1] = (select auth.uid()::text));
