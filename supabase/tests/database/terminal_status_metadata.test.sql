begin;

create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public, pg_catalog;

select plan(8);

select col_not_null(
  'public',
  'project_choice_options',
  'is_terminal',
  'terminal metadata is required on every managed choice'
);

select col_not_null(
  'public',
  'project_choice_options',
  'requires_savings_disposition',
  'the completion-decision flag is required on every managed choice'
);

select is(
  (select count(*)::bigint
   from public.project_choice_options
   where choice_type = 'event_status'
     and label in ('Complete', 'Cancelled')
     and not is_terminal),
  0::bigint,
  'all seeded Complete and Cancelled statuses are terminal'
);

select is(
  (select count(*)::bigint
   from public.project_choice_options
   where requires_savings_disposition
     and not (
       choice_type = 'event_status'
       and project_type = 'Sourcing'
       and label = 'Complete'
       and is_terminal
     )),
  0::bigint,
  'only the seeded Sourcing completion status requires a savings decision'
);

select is(
  (select count(*)::bigint
   from public.project_choice_options
   where choice_type <> 'event_status'
     and is_terminal),
  0::bigint,
  'non-status choices are not terminal'
);

insert into public.project_choice_options (
  organization_id, choice_type, project_type, label, sort_order
) values (
  '00000000-0000-4000-8000-000000000001',
  'event_status',
  'Sourcing',
  'Custom terminal test',
  9999
);

select is(
  (select not is_terminal and not requires_savings_disposition
   from public.project_choice_options
   where organization_id = '00000000-0000-4000-8000-000000000001'
     and choice_type = 'event_status'
     and project_type = 'Sourcing'
     and label = 'Custom terminal test'),
  true,
  'a new custom status defaults to non-terminal without a savings decision'
);

update public.project_choice_options
set is_terminal = true
where organization_id = '00000000-0000-4000-8000-000000000001'
  and choice_type = 'event_status'
  and project_type = 'Sourcing'
  and label = 'Custom terminal test';

update public.sourcing_events
set event_status = 'Complete'
where id = '00000000-0000-4000-8000-000000000021';

update public.project_choice_options
set label = 'Closed by metadata test'
where organization_id = '00000000-0000-4000-8000-000000000001'
  and choice_type = 'event_status'
  and project_type = 'Sourcing'
  and label = 'Complete';

select ok(
  (select is_terminal and requires_savings_disposition
   from public.project_choice_options
   where organization_id = '00000000-0000-4000-8000-000000000001'
     and choice_type = 'event_status'
     and project_type = 'Sourcing'
     and label = 'Closed by metadata test')
  and not exists (
    select 1 from public.sourcing_events
    where organization_id = '00000000-0000-4000-8000-000000000001'
      and project_type = 'Sourcing'
      and event_status = 'Complete'
  )
  and exists (
    select 1 from public.sourcing_events
    where id = '00000000-0000-4000-8000-000000000021'
      and event_status = 'Closed by metadata test'
  ),
  'renaming the completion status preserves both flags and cascades historical projects'
);

select throws_ok(
  $$
    update public.sourcing_events
    set savings_disposition = null
    where id = '00000000-0000-4000-8000-000000000021'
  $$,
  'P0001',
  'Choose whether scheduled savings were executed before completing this project',
  'renaming the completion status does not disable its savings-decision guard'
);

select * from finish();
rollback;
