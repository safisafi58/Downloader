create table if not exists public.download_events (
 id bigint generated always as identity primary key,
 platform text not null check (platform in ('TikTok','Facebook','Instagram','Direct link')),
 bytes bigint not null default 0 check (bytes >= 0),
 created_at timestamptz not null default now()
);
alter table public.download_events enable row level security;
grant insert on public.download_events to anon;
grant usage, select on sequence public.download_events_id_seq to anon;
drop policy if exists "anonymous clients can record download events" on public.download_events;
create policy "anonymous clients can record download events"
on public.download_events for insert to anon
with check (platform in ('TikTok','Facebook','Instagram','Direct link') and bytes >= 0);
