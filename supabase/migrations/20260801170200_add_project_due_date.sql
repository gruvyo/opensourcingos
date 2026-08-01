begin;

alter table public.sourcing_events
  add column if not exists project_due_date date;

-- Until this release, event_close_date was presented as the expected wrap-up
-- date (and even exported as "Due Date"). Preserve that intent in the new,
-- unambiguous field without deleting or rewriting the historical source value.
update public.sourcing_events
set project_due_date = event_close_date
where project_due_date is null
  and event_close_date is not null;

comment on column public.sourcing_events.project_due_date is
  'Planned date by which the project should be completed. Distinct from event_close_date, the actual completion/close date.';

commit;
