begin;

-- M-1, corrected after adversarial re-read: the unique current-label index
-- does not stop an administrator from renaming the guarded completion row and
-- then recreating its former label as non-terminal. Keep a server-owned label
-- history on the guarded row so every former completion spelling stays
-- reserved for that identity.
alter table public.project_choice_options
  add column completion_label_history text[] not null default '{}'::text[];

update public.project_choice_options
set completion_label_history = array(
  select distinct lower(btrim(label_value))
  from unnest(array[label, 'Complete']) label_value
  where btrim(label_value) <> ''
  order by 1
)
where requires_savings_disposition;

do $$
begin
  if exists (
    select 1
    from public.project_choice_options ordinary
    join public.project_choice_options guarded
      on guarded.organization_id = ordinary.organization_id
     and guarded.choice_type = ordinary.choice_type
     and guarded.project_type is not distinct from ordinary.project_type
     and guarded.requires_savings_disposition
    where not ordinary.requires_savings_disposition
      and lower(btrim(ordinary.label)) = any(guarded.completion_label_history)
  ) then
    raise exception 'a non-terminal option already reuses a reserved completion label';
  end if;
end
$$;

comment on column public.project_choice_options.completion_label_history is
  'Server-owned lowercase labels ever used by the guarded Sourcing completion status. Former labels cannot be recreated as unguarded options.';

create or replace function public.protect_sourcing_completion_status()
returns trigger
language plpgsql
security invoker
set search_path to 'pg_catalog', 'public'
as $$
declare
  v_reserved boolean;
begin
  if current_user in ('postgres', 'service_role', 'supabase_admin') then
    return new;
  end if;

  if tg_op = 'INSERT' then
    if new.requires_savings_disposition then
      raise exception 'savings completion status metadata is system-managed' using errcode = '42501';
    end if;

    select exists (
      select 1
      from public.project_choice_options guarded
      where guarded.organization_id = new.organization_id
        and guarded.choice_type = new.choice_type
        and guarded.project_type is not distinct from new.project_type
        and guarded.requires_savings_disposition
        and lower(btrim(new.label)) = any(guarded.completion_label_history)
    ) into v_reserved;
    if v_reserved then
      raise exception 'that label is reserved for the guarded completion status' using errcode = '42501';
    end if;

    new.completion_label_history := '{}'::text[];
    return new;
  end if;

  if (
    (not old.requires_savings_disposition and new.requires_savings_disposition)
    or (
      old.requires_savings_disposition
      and (
        not new.requires_savings_disposition
        or not new.is_terminal
        or not new.active_flag
        or new.choice_type is distinct from old.choice_type
        or new.project_type is distinct from old.project_type
      )
    )
  ) then
    raise exception 'the required sourcing completion status may be renamed but not disabled' using errcode = '42501';
  end if;

  if old.requires_savings_disposition then
    select coalesce(array_agg(distinct lower(btrim(label_value)) order by lower(btrim(label_value))), '{}'::text[])
    into new.completion_label_history
    from unnest(
      coalesce(old.completion_label_history, '{}'::text[])
      || array[old.label, new.label, 'Complete']
    ) label_value
    where btrim(label_value) <> '';
  else
    new.completion_label_history := old.completion_label_history;
    if new.label is distinct from old.label
       or new.organization_id is distinct from old.organization_id
       or new.choice_type is distinct from old.choice_type
       or new.project_type is distinct from old.project_type then
      select exists (
        select 1
        from public.project_choice_options guarded
        where guarded.organization_id = new.organization_id
          and guarded.choice_type = new.choice_type
          and guarded.project_type is not distinct from new.project_type
          and guarded.requires_savings_disposition
          and guarded.id <> new.id
          and lower(btrim(new.label)) = any(guarded.completion_label_history)
      ) into v_reserved;
      if v_reserved then
        raise exception 'that label is reserved for the guarded completion status' using errcode = '42501';
      end if;
    end if;
  end if;

  return new;
end
$$;

commit;
