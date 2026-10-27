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
  guests      jsonb not null default '[]'::jsonb check (jsonb_typeof(guests) = 'array' and jsonb_array_length(guests) <= 3),
  status      text not null default 'Pending' check (status in ('Pending', 'Paid', 'Mismatch', 'Refunded', 'Declined')),
  notes       text
);

alter table public.payments enable row level security;
drop policy if exists "guests can add a payment" on public.payments;
create policy "guests can add a payment" on public.payments for insert to anon with check (status = 'Pending');

revoke all on public.payments from anon, authenticated;
grant insert (guest_no, code, name, phone, passes, price_each, amount, upi_to, utr, proof_path, guests) on public.payments to anon;

-- A guest can check their own pass by phone number. Returns one line: what's cleared, or what's waiting.
create or replace function public.pass_status(p_phone text)
returns table (code text, name text, passes int, status text)
language sql stable security definer set search_path = public as $$
  select min(p.code), min(p.name),
         coalesce(sum(p.passes) filter (where p.status = 'Paid'), sum(p.passes))::int,
         case when bool_or(p.status = 'Paid') then 'Paid'
              when bool_or(p.status = 'Pending') then 'Pending'
              else min(p.status) end
  from public.payments p
  where length(regexp_replace(p_phone, '\D', '', 'g')) >= 10
    and right(regexp_replace(p.phone, '\D', '', 'g'), 10) = right(regexp_replace(p_phone, '\D', '', 'g'), 10)
    and p.status <> 'Declined'
  having count(*) > 0;
$$;
revoke all on function public.pass_status(text) from public;
grant execute on function public.pass_status(text) to anon;

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
revoke all on public.payments_to_check, public.door_list from anon, authenticated;
