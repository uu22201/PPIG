-- PPIG couple diary upgrade (non-destructive)
-- Run once in Supabase SQL Editor. Existing diary_entries/messages are preserved.

create or replace function public.ppig_is_couple_member(p_couple_id uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1 from public.diary_members
    where couple_id = p_couple_id and user_id = auth.uid()
  );
$$;

grant execute on function public.ppig_is_couple_member(uuid) to authenticated;

alter table public.diary_messages
  add column if not exists is_pinned boolean not null default false;

create table if not exists public.diary_message_replies (
  id uuid primary key default gen_random_uuid(),
  message_id uuid not null references public.diary_messages(id) on delete cascade,
  parent_id uuid references public.diary_message_replies(id) on delete cascade,
  couple_id uuid not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  content text not null check (length(trim(content)) between 1 and 500),
  created_at timestamptz not null default now()
);
alter table public.diary_message_replies add column if not exists parent_id uuid references public.diary_message_replies(id) on delete cascade;
alter table public.diary_message_replies enable row level security;
drop policy if exists "ppig replies read" on public.diary_message_replies;
drop policy if exists "ppig replies insert" on public.diary_message_replies;
create policy "ppig replies read" on public.diary_message_replies for select to authenticated
using (public.ppig_is_couple_member(couple_id));
create policy "ppig replies insert" on public.diary_message_replies for insert to authenticated
with check (user_id = auth.uid() and public.ppig_is_couple_member(couple_id));

create table if not exists public.diary_calendar_events (
  id uuid primary key default gen_random_uuid(),
  couple_id uuid not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null check (length(trim(title)) between 1 and 160),
  start_at timestamptz not null,
  end_at timestamptz not null,
  note text,
  created_at timestamptz not null default now(),
  constraint diary_calendar_events_time_check check (end_at > start_at)
);
alter table public.diary_calendar_events enable row level security;
drop policy if exists "ppig calendar read" on public.diary_calendar_events;
drop policy if exists "ppig calendar insert" on public.diary_calendar_events;
drop policy if exists "ppig calendar update own" on public.diary_calendar_events;
drop policy if exists "ppig calendar delete own" on public.diary_calendar_events;
create policy "ppig calendar read" on public.diary_calendar_events for select to authenticated
using (public.ppig_is_couple_member(couple_id));
create policy "ppig calendar insert" on public.diary_calendar_events for insert to authenticated
with check (user_id = auth.uid() and public.ppig_is_couple_member(couple_id));
create policy "ppig calendar update own" on public.diary_calendar_events for update to authenticated
using (user_id = auth.uid() and public.ppig_is_couple_member(couple_id))
with check (user_id = auth.uid() and public.ppig_is_couple_member(couple_id));
create policy "ppig calendar delete own" on public.diary_calendar_events for delete to authenticated
using (user_id = auth.uid() and public.ppig_is_couple_member(couple_id));

create table if not exists public.diary_emotion_comments (
  id uuid primary key default gen_random_uuid(),
  couple_id uuid not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  content text not null check (length(trim(content)) between 1 and 400),
  created_at timestamptz not null default now()
);
alter table public.diary_emotion_comments add column if not exists parent_id uuid references public.diary_emotion_comments(id) on delete cascade;
alter table public.diary_emotion_comments enable row level security;
drop policy if exists "ppig emotion comments read" on public.diary_emotion_comments;
drop policy if exists "ppig emotion comments insert" on public.diary_emotion_comments;
create policy "ppig emotion comments read" on public.diary_emotion_comments for select to authenticated
using (public.ppig_is_couple_member(couple_id));
create policy "ppig emotion comments insert" on public.diary_emotion_comments for insert to authenticated
with check (user_id = auth.uid() and public.ppig_is_couple_member(couple_id));

-- Grant authenticated access; RLS above restricts each row to the couple.
grant select, insert on public.diary_message_replies to authenticated;
grant select, insert, update, delete on public.diary_calendar_events to authenticated;
grant select, insert on public.diary_emotion_comments to authenticated;

-- Allow authors to manage their own sticky notes (pin/delete).
drop policy if exists "ppig messages update own" on public.diary_messages;
drop policy if exists "ppig messages delete own" on public.diary_messages;
create policy "ppig messages update own" on public.diary_messages for update to authenticated
using (user_id = auth.uid() and public.ppig_is_couple_member(couple_id))
with check (user_id = auth.uid() and public.ppig_is_couple_member(couple_id));
create policy "ppig messages delete own" on public.diary_messages for delete to authenticated
using (user_id = auth.uid() and public.ppig_is_couple_member(couple_id));
