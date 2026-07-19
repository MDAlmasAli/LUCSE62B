-- Records which students the CR has bulk-generated a cover page for.
-- Read + written directly from the browser with the anon key (same pattern as
-- public.cover_page_topics), so RLS must allow anon SELECT + INSERT.

create table if not exists public.cr_cover_pages (
  id           bigint generated always as identity primary key,
  course_code  text not null,
  doc_type     text not null,               -- 'assignment' | 'lab'
  doc_no       text not null,               -- normalised (no leading zeros)
  student_id   text not null,
  topic        text default '',
  generated_by text default '',             -- CR student id
  created_at   timestamptz not null default now(),
  unique (course_code, doc_type, doc_no, student_id)
);

comment on table public.cr_cover_pages is
  'One row per student the CR bulk-generated a cover page for. Drives the "your CR already made this" notice on the cover page generator.';

alter table public.cr_cover_pages enable row level security;

-- Anyone (anon) may read — the notice check queries by the student''s own id.
create policy "cr_cover_pages_read"
  on public.cr_cover_pages for select
  to anon
  using (true);

-- Anyone (anon) may insert — the CR''s browser writes these when generating.
create policy "cr_cover_pages_insert"
  on public.cr_cover_pages for insert
  to anon
  with check (true);

-- Allow the upsert (Prefer: resolution=merge-duplicates) to update existing rows.
create policy "cr_cover_pages_update"
  on public.cr_cover_pages for update
  to anon
  using (true)
  with check (true);
