-- Ghost Town passes. Run this once in Supabase: SQL Editor > New query > paste > Run.
-- Guests can add a payment and upload a screenshot. They can't read anyone's rows or screenshots.
-- You review everything in Table Editor > payments, and screenshots in Storage > payment-proofs.

create table if not exists public.payments (
  id          bigint generated always as identity primary key,
  received    timestamptz not null default now(),
  guest_no    int,
  code        text check (char_length(code) <= 20),
  name        text not null check (char_length(name) between 1 and 200),
  phone       text not null check (char_length(phone) between 1 and 40),
  passes      int not null check (passes between 1 and 4),
  price_each  int not null check (price_each between 1 and 10000),
  amount      int not null check (amount between 1 and 40000),
  upi_to      text check (char_length(upi_to) <= 100),
  utr         text check (char_length(utr) <= 30),
  proof_path  text check (char_length(proof_path) <= 300),
  lookup_hash text check (lookup_hash ~ '^[0-9a-f]{64}$'),
  guests      jsonb not null default '[]'::jsonb check (jsonb_typeof(guests) = 'array' and jsonb_array_length(guests) <= 3),
  status      text not null default 'Pending' check (status in ('Pending', 'Paid', 'Mismatch', 'Refunded', 'Declined')),
  notes       text
);

alter table public.payments add column if not exists lookup_hash text check (lookup_hash ~ '^[0-9a-f]{64}$');

alter table public.payments enable row level security;
drop policy if exists "guests can add a payment" on public.payments;
create policy "guests can add a payment" on public.payments for insert to anon with check (status = 'Pending');

revoke all on public.payments from anon, authenticated;
grant insert (guest_no, code, name, phone, passes, price_each, amount, upi_to, utr, proof_path, guests, lookup_hash) on public.payments to anon;

-- The database decides the price, not the page. A guest keeps the price they saw for 6 hours
-- (same window pay.html uses), so the lowest allowed price is the tier that was on 6 hours ago.
-- Keep these dates and prices in sync with TIERS in pay.html.
create or replace function public.payments_set_price() returns trigger
language plpgsql set search_path = public as $$
declare
  t timestamptz := now() - interval '6 hours';
  floor_price int := case
    when t < '2026-10-28T23:59:59+05:30' then 800
    when t < '2026-10-29T23:59:59+05:30' then 1200
    when t < '2026-10-30T18:00:00+05:30' then 1500
    else 2000 end;
begin
  new.price_each := greatest(coalesce(new.price_each, 0), floor_price);
  new.amount := new.price_each * new.passes;
  new.status := 'Pending';
  return new;
end $$;
drop trigger if exists payments_set_price on public.payments;
create trigger payments_set_price before insert on public.payments
  for each row execute function public.payments_set_price();

-- Passes and the door. Every booking gets an unguessable pass_token (the QR on the pass);
-- checked_in counts how many of its passes have walked in.
alter table public.payments add column if not exists pass_token uuid not null default gen_random_uuid() unique;
alter table public.payments add column if not exists checked_in int not null default 0;
alter table public.payments add column if not exists checked_in_at timestamptz;

-- A guest checks their own bookings with the phone number plus a random token their browser made when
-- they paid (only its hash is stored). Knowing someone's number alone shows nothing.
-- Code, name, passes and the pass link come only from rows you've marked Paid, so a pending row can't fake a pass.
drop function if exists public.pass_status(text);
drop function if exists public.pass_status(text, text);
create function public.pass_status(p_phone text, p_token text)
returns table (code text, name text, passes int, status text, pass_token uuid)
language sql stable security definer set search_path = public as $$
  select case when p.status = 'Paid' then p.code end,
         case when p.status = 'Paid' then p.name end,
         case when p.status = 'Paid' then p.passes end,
         p.status,
         case when p.status = 'Paid' then p.pass_token end
  from public.payments p
  where length(regexp_replace(p_phone, '\D', '', 'g')) >= 10
    and right(regexp_replace(p.phone, '\D', '', 'g'), 10) = right(regexp_replace(p_phone, '\D', '', 'g'), 10)
    and length(coalesce(p_token, '')) >= 32
    and p.lookup_hash = encode(sha256(convert_to(p_token, 'UTF8')), 'hex')
    and p.status <> 'Declined'
  order by (p.status = 'Paid') desc, p.id;
$$;
revoke all on function public.pass_status(text, text) from public;
grant execute on function public.pass_status(text, text) to anon;

-- The pass page (pass.html#<pass_token>). Whoever holds the link sees the pass, nothing more.
create or replace function public.get_pass(p_pass uuid)
returns table (code text, name text, guests text[], passes int, checked_in int, status text)
language sql stable security definer set search_path = public as $$
  select case when p.status = 'Paid' then p.code end,
         case when p.status = 'Paid' then p.name end,
         case when p.status = 'Paid' then array(select g->>'name' from jsonb_array_elements(p.guests) g) end,
         case when p.status = 'Paid' then p.passes end,
         case when p.status = 'Paid' then p.checked_in end,
         p.status
  from public.payments p
  where p.pass_token = p_pass and p.status <> 'Declined';
$$;
revoke all on function public.get_pass(uuid) from public;
grant execute on function public.get_pass(uuid) to anon;

-- Door staff. The scanner holds a door key; only its hash lives here. No policies, so the page can't read it.
create table if not exists public.door_keys (
  key_hash text primary key check (key_hash ~ '^[0-9a-f]{64}$'),
  label    text,
  created  timestamptz not null default now()
);
alter table public.door_keys enable row level security;
revoke all on public.door_keys from anon, authenticated;

-- Look up a pass by its QR token or its code (GT-105), and optionally admit p_admit people.
-- Never admits more than the booking paid for, even if two doors scan at once.
create or replace function public.door_check(p_key text, p_pass text, p_admit int default 0)
returns table (code text, name text, guests text[], passes int, checked_in int, status text, checked_in_at timestamptz)
language plpgsql volatile security definer set search_path = public as $$
#variable_conflict use_column
declare v_id bigint;
begin
  if not exists (select 1 from door_keys k where k.key_hash = encode(sha256(convert_to(coalesce(p_key, ''), 'UTF8')), 'hex')) then
    raise exception 'bad door key' using errcode = '28000';
  end if;
  -- Codes come from the invite link, so two bookings can share one. A typed code only works if it's unique;
  -- otherwise the door must scan the QR (pass_token is always unique).
  if (select count(*) from payments p where upper(p.code) = upper(trim(p_pass)) and p.status <> 'Declined') > 1 then
    raise exception 'code matches more than one booking' using errcode = 'P0001', hint = 'ambiguous';
  end if;
  select p.id into v_id from payments p
  where (p.pass_token::text = lower(trim(p_pass)) or upper(p.code) = upper(trim(p_pass))) and p.status <> 'Declined'
  limit 1;
  if v_id is not null and coalesce(p_admit, 0) > 0 then
    update payments p set checked_in = p.checked_in + least(p_admit, p.passes - p.checked_in), checked_in_at = now()
    where p.id = v_id and p.status = 'Paid' and p.checked_in < p.passes;
  end if;
  return query
    select p.code, p.name, array(select g->>'name' from jsonb_array_elements(p.guests) g),
           p.passes, p.checked_in, p.status, p.checked_in_at
    from payments p where p.id = v_id;
end $$;
revoke all on function public.door_check(text, text, int) from public;
grant execute on function public.door_check(text, text, int) to anon;

-- Private bucket for payment screenshots (8 MB max, images only). Guests can upload, never list or read.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('payment-proofs', 'payment-proofs', false, 8388608,
        array['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif'])
on conflict (id) do nothing;

drop policy if exists "guests can upload payment proofs" on storage.objects;
create policy "guests can upload payment proofs" on storage.objects
  for insert to anon with check (bucket_id = 'payment-proofs');

-- Handy views for you (dashboard only; guests can't see them).
create or replace view public.payments_to_check with (security_invoker = true) as
  select id, received, code, name, phone, passes, amount, upi_to, utr, proof_path, status
  from public.payments where status = 'Pending' order by received;

create or replace view public.door_list with (security_invoker = true) as
  select p.code, p.name as person, p.phone, 'booked ' || p.passes as role
  from public.payments p where p.status = 'Paid'
  union all
  select p.code, g->>'name', g->>'phone', 'guest of ' || p.name
  from public.payments p cross join lateral jsonb_array_elements(p.guests) g where p.status = 'Paid'
  order by 1, 4;
-- Paid bookings with the link to send each guest on WhatsApp, and how many have arrived.
create or replace view public.pass_links with (security_invoker = true) as
  select p.code, p.name, p.phone, p.passes, p.checked_in,
         'https://jinxednetwork.github.io/ghost-town/pass.html#' || p.pass_token as pass_link
  from public.payments p where p.status = 'Paid' order by p.received;
revoke all on public.payments_to_check, public.door_list, public.pass_links from anon, authenticated;
