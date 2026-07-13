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
