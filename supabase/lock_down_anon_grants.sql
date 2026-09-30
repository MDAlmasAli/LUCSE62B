-- Run this in the Supabase SQL editor (Dashboard -> SQL Editor -> New query).
--
-- Why: the anon key is published in the site's JavaScript (assets/js, sw.js,
-- index.html). Anything the `anon` role is allowed to do, any visitor can do
-- with curl, logged in or not, in the Student Info sheet or not. These grants
-- were far wider than the portal needs.
--
-- Everything the portal actually does with these tables goes through the
-- Cloudflare Worker, which uses the service_role key. service_role bypasses
-- RLS and keeps its own grants, so the Worker is unaffected by all of this.

-- ── attendance_records ────────────────────────────────────────────────────
-- This is the real hole, and the only one of these tables with RLS switched
-- off. Every other table default-denies anything without a matching policy;
-- this one has no such net, and anon holds SELECT, INSERT, UPDATE, DELETE and
-- TRUNCATE. Verified with nothing but the key that ships in the site's
-- JavaScript: all 393 rows read back, and an empty INSERT got past permission
-- to fail on a NOT NULL constraint (23502) rather than being refused (42501).
-- So anyone can read the whole register, mark people present, or wipe it.
-- No client-side code touches this table; the site and the app both go through
-- the Worker's /attendance endpoint, which uses the service_role key and is
-- unaffected by any of this.
alter table public.attendance_records enable row level security;
revoke all on public.attendance_records from anon, authenticated;

-- ── notifications ─────────────────────────────────────────────────────────
-- Tidying up, not a hole. anon holds INSERT/UPDATE/DELETE/TRUNCATE here too,
-- but this table has RLS enabled with a read-only policy, so the writes are
-- already refused -- an anon INSERT comes back 42501, verified. The grants are
-- simply unused, and leaving them means a permissive policy added later would
-- silently open writing to everyone. The site, the app and the service worker
-- READ this table with the anon key, so SELECT has to stay.
revoke all on public.notifications from anon, authenticated;
grant select on public.notifications to anon, authenticated;


-- ── student_passwords: stop handing out everyone's date of birth ──────────
-- anon could read student_id, name, dob and h_dob for all 38 students with no
-- login at all. A date of birth is not just private here: it is the second
-- factor the portal and the app use to pull a result from Leading University.
--
-- The birthday features are the only reason the columns were readable, so this
-- replaces them with a function that answers the one question the site asks -
-- "whose birthday is today?" - and keeps the dates inside the database.
--
-- IMPORTANT: run this together with the matching site deploy (index.html and
-- pages/profile.html now call the RPCs). Run the SQL first: until the site is
-- deployed the birthday greeting just will not appear, which is harmless,
-- whereas deploying first would leave it reading columns it can no longer see.
create or replace function public.birthdays_today()
returns table (student_id text, name text)
language sql
security definer
set search_path to 'public'
as $$
  select sp.student_id,
         coalesce(nullif(btrim(sp.name), ''), sp.student_id) as name
  from public.student_passwords sp
  cross join lateral (
    select case
      -- h_dob is the real birthday and wins over dob, the certificate one,
      -- but only when it is actually usable as a date.
      when sp.h_dob ~ '^\d{4}-\d{2}-\d{2}' then sp.h_dob
      when sp.dob   ~ '^\d{4}-\d{2}-\d{2}' then sp.dob
      else null
    end as birth
  ) picked
  where upper(sp.student_id) <> 'DEMO'
    and picked.birth is not null
    and substring(picked.birth from 6 for 5)
        = to_char((now() at time zone 'Asia/Dhaka')::date, 'MM-DD');
$$;

revoke execute on function public.birthdays_today() from public;
grant execute on function public.birthdays_today() to anon, authenticated;

-- Postgres cannot carve columns out of a table-wide SELECT grant, so drop the
-- table grant and hand back only the two columns the site legitimately reads
-- (analytics counts registered students by student_id; names are already
-- public in the Student Info sheet).
revoke select on public.student_passwords from anon, authenticated;
grant select (student_id, name) on public.student_passwords to anon, authenticated;


-- ══════════════════════════════════════════════════════════════════════════
-- LATER: only once every phone is on v1.1.43 or newer. NOT part of the run
-- above — running it early breaks working installs.
--
-- v1.1.43 is the first build that registers its push token and reads and
-- writes its retake/improve courses through the Worker. Anything older still
-- talks to these two tables with the anon key, so revoking now would stop push
-- registration and empty My Courses for anyone who has not updated. Give it a
-- couple of weeks, check that nobody is left on an older build, then run:
--
--   revoke all on public.fcm_tokens from anon, authenticated;
--   revoke all on public.student_retake_enrollments from anon, authenticated;
--
-- Until then: anyone holding the published anon key can read every device push
-- token and re-point one at their own student id, and can list or edit anybody's
-- enrolled courses.
-- ══════════════════════════════════════════════════════════════════════════


-- ── Check afterwards ──────────────────────────────────────────────────────
-- attendance_records should list no anon row at all; notifications should list
-- anon with SELECT only.
select table_name, grantee,
       string_agg(distinct privilege_type, ', ' order by privilege_type) as privileges
from information_schema.role_table_grants
where table_schema = 'public'
  and table_name in ('attendance_records', 'notifications')
  and grantee in ('anon', 'authenticated')
group by table_name, grantee
order by table_name, grantee;

-- student_passwords should now show anon with SELECT on student_id and name
-- only - no dob, no h_dob, no password_hash.
select column_name, privilege_type
from information_schema.column_privileges
where table_schema = 'public' and table_name = 'student_passwords'
  and grantee = 'anon' and privilege_type = 'SELECT'
order by column_name;
