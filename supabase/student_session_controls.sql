-- NOT YET RUN. Checked on 2026-10-05: this table does not exist in the
-- database, so "Logout other devices" in Profile reports success and does
-- nothing. The Worker's isSessionAllowed() queries it and fails open when the
-- read fails, which is why nobody is wrongly signed out -- the feature is
-- simply inert.
--
-- Run it in the Supabase SQL editor. Only the Worker touches this table, with
-- the service_role key, so RLS with no policy is correct: it shuts the anon
-- key out entirely.

create table if not exists public.student_session_controls (
  student_id text primary key,
  revoke_before timestamptz not null default now(),
  keep_session_id text,
  updated_at timestamptz not null default now()
);

alter table public.student_session_controls enable row level security;

comment on table public.student_session_controls is
  'Per-student session revocation marker used by the portal logout-other-devices feature.';

comment on column public.student_session_controls.revoke_before is
  'Sessions issued before this timestamp are rejected unless their session id matches keep_session_id.';
