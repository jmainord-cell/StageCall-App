-- ---------------------------------------------------------------
-- 003: book in one step, undo a booking, undo a decline.
--
-- For a database that already ran 002. A fresh setup gets the same
-- result from policies.sql, so it doesn't need this.
--
-- 1. New application rules: each side gets clear one-step changes,
--    the venue can undo a decline or a booking, and an artist can no
--    longer re-apply after being declined or withdraw once booked.
-- 2. book_artist() and cancel_booking(), plus a policy letting the venue
--    delete an unpaid booking.
-- ---------------------------------------------------------------
begin;

create or replace function private.check_application_update() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  is_artist boolean;
  is_venue  boolean;
  step      text;
begin
  if auth.uid() is null then
    return new;
  end if;
  if new.gig_id <> old.gig_id or new.artist_id <> old.artist_id then
    raise exception 'An application cannot be moved to another gig or artist';
  end if;
  if new.status <> old.status then
    is_artist := private.owns_artist(new.artist_id);
    is_venue  := private.owns_gig(new.gig_id);
    step := old.status || '>' || new.status;
    if is_artist and step in ('applied>withdrawn', 'withdrawn>applied') then
      null;  -- withdraw / apply again
    elsif is_venue and step in ('applied>accepted', 'applied>declined', 'declined>applied', 'accepted>applied') then
      null;  -- accept / decline / undo decline / undo booking
    elsif step in ('applied>withdrawn', 'withdrawn>applied') then
      raise exception 'Only the artist can apply or withdraw';
    elsif step in ('applied>accepted', 'applied>declined', 'declined>applied', 'accepted>applied') then
      raise exception 'Only the venue can accept, decline or undo';
    else
      raise exception 'An application cannot go from % to %', old.status, new.status;
    end if;
  end if;
  new.updated_at := now();
  return new;
end $$;

-- ---------------------------------------------------------------
-- Booking in one step, and undoing it. Both run with the caller's own
-- permissions (security invoker), so the policies above still decide:
-- only the venue that posted the gig can book or undo. Each runs as one
-- transaction, so it either fully happens or doesn't happen at all.
--   sb.rpc('book_artist', { p_gig_id, p_artist_id })
--   sb.rpc('cancel_booking', { p_gig_id })
-- Other applicants stay 'applied' while the gig is booked (the app shows
-- them as "Not selected"), so undoing a booking gives them their chance
-- back; anyone the venue declined stays declined.
-- ---------------------------------------------------------------
create policy "venue cancels unpaid booking" on bookings for delete
  using (private.owns_gig(gig_id) and payment_status = 'unpaid');

create function book_artist(p_gig_id uuid, p_artist_id uuid) returns void
language plpgsql security invoker set search_path = public as $$
declare
  v_pay integer;
begin
  if not private.owns_gig(p_gig_id) then
    raise exception 'Only the venue that posted this gig can book it';
  end if;
  select pay_cents into v_pay from gigs where id = p_gig_id and status = 'open' for update;
  if not found then
    raise exception 'This gig is not open for booking';
  end if;
  if not exists (select 1 from applications
                 where gig_id = p_gig_id and artist_id = p_artist_id and status = 'applied') then
    raise exception 'This artist has no open application for this gig';
  end if;
  insert into bookings (gig_id, artist_id, agreed_pay_cents) values (p_gig_id, p_artist_id, v_pay);
  update applications set status = 'accepted' where gig_id = p_gig_id and artist_id = p_artist_id;
  update gigs set status = 'filled' where id = p_gig_id;
end $$;

create function cancel_booking(p_gig_id uuid) returns void
language plpgsql security invoker set search_path = public as $$
declare
  b bookings;
begin
  if not private.owns_gig(p_gig_id) then
    raise exception 'Only the venue that posted this gig can undo its booking';
  end if;
  select * into b from bookings where gig_id = p_gig_id for update;
  if not found then
    raise exception 'This gig has no booking to undo';
  end if;
  if b.payment_status <> 'unpaid' then
    raise exception 'This booking has a payment on it. Refund it before undoing the booking';
  end if;
  delete from bookings where id = b.id;
  update applications set status = 'applied'
    where gig_id = p_gig_id and artist_id = b.artist_id and status = 'accepted';
  update gigs set status = 'open' where id = p_gig_id;
end $$;

-- Signed-in users only (Supabase grants new functions to anon by default).
revoke execute on function book_artist(uuid, uuid) from public, anon;
revoke execute on function cancel_booking(uuid) from public, anon;
grant execute on function book_artist(uuid, uuid) to authenticated;
grant execute on function cancel_booking(uuid) to authenticated;

commit;
