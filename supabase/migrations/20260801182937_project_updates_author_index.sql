-- Follow-up for environments where project_updates_timeline was already
-- applied before the author index was added to that migration.
create index if not exists idx_project_updates_created_by
  on public.project_updates (created_by);
