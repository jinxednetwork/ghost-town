-- Ghost Town invite requests. Visitors can only insert; reading happens in the Supabase dashboard.
create table public.requests (
  id         bigint generated always as identity primary key,
  received   timestamptz not null default now(),
  name       text not null check (char_length(name) between 1 and 200),
  phone      text not null check (char_length(phone) between 1 and 200),
  instagram  text check (char_length(instagram) <= 200),
  referrer   text check (char_length(referrer) <= 200),
  status     text not null default 'Pending' check (status in ('Pending', 'Approved', 'Paid', 'Declined')),
  notes      text
);

alter table public.requests enable row level security;
create policy "anyone can request" on public.requests for insert to anon with check (true);

-- anon may only fill these four columns, never status/notes/received, and can't read anything back.
revoke all on public.requests from anon, authenticated;
grant insert (name, phone, instagram, referrer) on public.requests to anon;
