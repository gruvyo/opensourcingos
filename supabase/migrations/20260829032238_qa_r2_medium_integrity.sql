begin;

-- M-2, corrected scope: only project_choice_options is actually unstamped.
-- Five named governance tables already have dedicated actor triggers, while
-- suppliers and the three taxonomy tables have no provenance actor columns.
create trigger project_choice_options_actor
before insert or update on public.project_choice_options
for each row execute function public.stamp_money_record_actor();

-- M-3: finance validation metadata is a structural invariant, not only an RPC
-- convention. The stronger equivalence also prevents stale actor/date fields.
alter table public.realization_periods
  add constraint chk_realization_finance_validation_actor check (
    (
      finance_validated
      and finance_validated_by is not null
      and finance_validation_date is not null
    ) or (
      not finance_validated
      and finance_validated_by is null
      and finance_validation_date is null
    )
  ) not valid;

alter table public.realization_periods
  validate constraint chk_realization_finance_validation_actor;

-- M-4: deferred financial invariants must see their parent and sibling rows
-- even when caller RLS would hide them. These functions are trigger-only,
-- pinned, and already revoked from browser roles.
alter function public.enforce_savings_execution_invariant() security definer;
alter function public.enforce_savings_completion_invariant() security definer;

-- M-5: inspect JSON numbers before numeric(15,2) can silently round them.
create function public.assert_jsonb_money_cent_exact(
  p_items jsonb,
  p_fields text[]
)
returns void
language plpgsql
set search_path to 'pg_catalog'
as $$
declare
  v_item jsonb;
  v_field text;
  v_amount numeric;
begin
  if jsonb_typeof(p_items) is distinct from 'array' then
    raise exception 'money payload must be a JSON array';
  end if;

  for v_item in select value from jsonb_array_elements(p_items)
  loop
    if jsonb_typeof(v_item) is distinct from 'object' then
      raise exception 'money payload rows must be JSON objects';
    end if;
    foreach v_field in array p_fields
    loop
      if v_item ? v_field and v_item->v_field <> 'null'::jsonb then
        if jsonb_typeof(v_item->v_field) is distinct from 'number' then
          raise exception '% must be a JSON number or null', v_field;
        end if;
        v_amount := (v_item->>v_field)::numeric;
        if v_amount is distinct from round(v_amount, 2) then
          raise exception '% must have no more than two decimal places', v_field
            using errcode = '22003';
        end if;
      end if;
    end loop;
  end loop;
end
$$;

revoke all on function public.assert_jsonb_money_cent_exact(jsonb, text[])
  from public, anon, authenticated;
grant execute on function public.assert_jsonb_money_cent_exact(jsonb, text[])
  to service_role;

alter function public.replace_savings_schedule(uuid, integer, integer, text, jsonb)
  rename to replace_savings_schedule_unchecked;

revoke all on function public.replace_savings_schedule_unchecked(uuid, integer, integer, text, jsonb)
  from public, anon, authenticated;

create function public.replace_savings_schedule(
  p_savings_calculation_id uuid,
  p_schedule_start_month integer,
  p_schedule_start_year integer,
  p_schedule_period_type text,
  p_periods jsonb
)
returns void
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $$
begin
  perform public.assert_jsonb_money_cent_exact(
    p_periods,
    array[
      'baseline_amount', 'opening_amount', 'final_amount',
      'cost_reduction_amount', 'cost_avoidance_amount', 'total_savings_amount'
    ]
  );
  perform public.replace_savings_schedule_unchecked(
    p_savings_calculation_id,
    p_schedule_start_month,
    p_schedule_start_year,
    p_schedule_period_type,
    p_periods
  );
end
$$;

revoke all on function public.replace_savings_schedule(uuid, integer, integer, text, jsonb)
  from public, anon, authenticated;
grant execute on function public.replace_savings_schedule(uuid, integer, integer, text, jsonb)
  to authenticated;

create function public.save_estimated_savings_calculation(
  p_event_id uuid,
  p_calculation jsonb,
  p_calculation_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $$
declare
  v_user uuid := auth.uid();
  v_org uuid;
  v_role text;
  v_baseline_id uuid;
  v_baseline numeric;
  v_opening numeric;
  v_final numeric;
  v_reduction numeric;
  v_avoidance numeric;
  v_total numeric;
  v_percentage numeric;
  v_savings_type text;
  v_id uuid;
begin
  if v_user is null then raise exception 'authentication required'; end if;
  if jsonb_typeof(p_calculation) is distinct from 'object' then
    raise exception 'calculation must be a JSON object';
  end if;
  if exists (
    select 1 from jsonb_object_keys(p_calculation) key(field_name)
    where key.field_name not in (
      'baseline_id', 'calculation_name', 'savings_type',
      'baseline_total_amount', 'opening_proposal_amount', 'award_total_amount',
      'gross_savings_amount', 'cost_reduction_amount', 'cost_avoidance_amount',
      'savings_percentage', 'net_savings_amount', 'recognition_notes'
    )
  ) then
    raise exception 'calculation payload contains unsupported fields';
  end if;

  perform public.assert_jsonb_money_cent_exact(
    jsonb_build_array(p_calculation),
    array[
      'baseline_total_amount', 'opening_proposal_amount', 'award_total_amount',
      'gross_savings_amount', 'cost_reduction_amount', 'cost_avoidance_amount',
      'net_savings_amount', 'savings_percentage'
    ]
  );

  select organization_id, role into v_org, v_role
  from public.profiles where id = v_user;
  if v_org is null then raise exception 'workspace membership required'; end if;
  if v_role not in ('admin', 'procurement_user') then
    raise exception 'administrator or procurement role required';
  end if;

  perform 1 from public.sourcing_events
  where id = p_event_id and organization_id = v_org and project_type = 'Sourcing'
  for update;
  if not found then raise exception 'sourcing project not found'; end if;

  v_baseline_id := nullif(p_calculation->>'baseline_id', '')::uuid;
  if v_baseline_id is not null and not exists (
    select 1 from public.baselines
    where id = v_baseline_id and event_id = p_event_id and organization_id = v_org
  ) then
    raise exception 'selected baseline does not belong to the sourcing project';
  end if;

  v_baseline := (p_calculation->>'baseline_total_amount')::numeric;
  v_opening := (p_calculation->>'opening_proposal_amount')::numeric;
  v_final := (p_calculation->>'award_total_amount')::numeric;
  if v_final is null or v_final < 0 then raise exception 'final amount is required and cannot be negative'; end if;
  if v_baseline < 0 or v_opening < 0 then raise exception 'baseline and opening amounts cannot be negative'; end if;

  v_reduction := case when v_baseline is null then null else v_baseline - v_final end;
  v_avoidance := case
    when v_baseline is not null and v_opening is not null then v_opening - v_baseline
    when v_baseline is null and v_opening is not null then v_opening - v_final
    else 0
  end;
  v_total := coalesce(v_reduction, 0) + v_avoidance;
  v_percentage := case when v_baseline > 0 then round((v_total / v_baseline) * 100, 2) end;
  v_savings_type := case when coalesce(v_reduction, 0) >= v_avoidance
    then 'Cost Reduction' else 'Cost Avoidance' end;

  if (p_calculation->>'cost_reduction_amount')::numeric is distinct from v_reduction
    or (p_calculation->>'cost_avoidance_amount')::numeric is distinct from v_avoidance
    or (p_calculation->>'gross_savings_amount')::numeric is distinct from v_total
    or (p_calculation->>'net_savings_amount')::numeric is distinct from v_total
    or (p_calculation->>'savings_percentage')::numeric is distinct from v_percentage
    or p_calculation->>'savings_type' is distinct from v_savings_type then
    raise exception 'calculation payload does not match the approved savings chain';
  end if;

  if p_calculation_id is null then
    insert into public.savings_calculations (
      organization_id, event_id, baseline_id, calculation_name, savings_type,
      baseline_total_amount, opening_proposal_amount, award_total_amount,
      gross_savings_amount, cost_reduction_amount, cost_avoidance_amount,
      savings_percentage, net_savings_amount, recognition_notes,
      created_by, updated_by
    ) values (
      v_org, p_event_id, v_baseline_id,
      coalesce(nullif(btrim(p_calculation->>'calculation_name'), ''), 'Deal savings'),
      v_savings_type, v_baseline, v_opening, v_final,
      v_total, v_reduction, v_avoidance, v_percentage, v_total,
      p_calculation->>'recognition_notes', v_user, v_user
    ) returning id into v_id;
  else
    update public.savings_calculations
    set baseline_id = v_baseline_id,
        calculation_name = coalesce(nullif(btrim(p_calculation->>'calculation_name'), ''), calculation_name),
        savings_type = v_savings_type,
        baseline_total_amount = v_baseline,
        opening_proposal_amount = v_opening,
        award_total_amount = v_final,
        gross_savings_amount = v_total,
        cost_reduction_amount = v_reduction,
        cost_avoidance_amount = v_avoidance,
        savings_percentage = v_percentage,
        net_savings_amount = v_total,
        recognition_notes = p_calculation->>'recognition_notes',
        updated_by = v_user,
        updated_at = now()
    where id = p_calculation_id
      and event_id = p_event_id
      and organization_id = v_org
      and calculation_status = 'estimated'
    returning id into v_id;
    if v_id is null then raise exception 'editable savings calculation not found'; end if;
  end if;

  return v_id;
end
$$;

revoke all on function public.save_estimated_savings_calculation(uuid, jsonb, uuid)
  from public, anon, authenticated;
grant execute on function public.save_estimated_savings_calculation(uuid, jsonb, uuid)
  to authenticated;

-- The role matrix grants these at column scope. A table-scope REVOKE alone
-- does not remove column privileges, so revoke both forms explicitly.
do $$
declare
  v_columns text;
begin
  select string_agg(format('%I', column_name), ', ' order by ordinal_position)
  into v_columns
  from information_schema.columns
  where table_schema = 'public' and table_name = 'savings_calculations';

  execute format(
    'revoke insert (%s), update (%s) on table public.savings_calculations from authenticated',
    v_columns, v_columns
  );
  revoke insert, update on public.savings_calculations from authenticated;

  select string_agg(format('%I', column_name), ', ' order by ordinal_position)
  into v_columns
  from information_schema.columns
  where table_schema = 'public' and table_name = 'savings_periods';

  execute format(
    'revoke update (%s) on table public.savings_periods from authenticated',
    v_columns
  );
  revoke update on public.savings_periods from authenticated;
end
$$;

alter function public.correct_savings_execution(uuid, text, jsonb, jsonb)
  rename to correct_savings_execution_unchecked;

revoke all on function public.correct_savings_execution_unchecked(uuid, text, jsonb, jsonb)
  from public, anon, authenticated;

create function public.correct_savings_execution(
  p_calc_id uuid,
  p_note text,
  p_calculation jsonb,
  p_periods jsonb
)
returns void
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $$
begin
  perform public.assert_jsonb_money_cent_exact(
    jsonb_build_array(p_calculation),
    array[
      'baseline_total_amount', 'opening_proposal_amount', 'award_total_amount',
      'gross_savings_amount', 'net_savings_amount',
      'cost_reduction_amount', 'cost_avoidance_amount', 'savings_percentage'
    ]
  );
  perform public.assert_jsonb_money_cent_exact(
    p_periods,
    array[
      'baseline_amount', 'opening_amount', 'final_amount',
      'cost_reduction_amount', 'cost_avoidance_amount', 'total_savings_amount'
    ]
  );
  perform public.correct_savings_execution_unchecked(
    p_calc_id, p_note, p_calculation, p_periods
  );
end
$$;

revoke all on function public.correct_savings_execution(uuid, text, jsonb, jsonb)
  from public, anon, authenticated;
grant execute on function public.correct_savings_execution(uuid, text, jsonb, jsonb)
  to authenticated;

-- M-7: no deployment may silently hide legacy Support-project money. Current
-- production has zero such rows; a portable deployment with them stops here
-- with a reconciliation instruction instead of dropping them from headlines.
do $$
begin
  if exists (
    select 1
    from public.savings_calculations calculation
    join public.sourcing_events event on event.id = calculation.event_id
    where event.project_type <> 'Sourcing'
  ) then
    raise exception 'Support-project savings calculations require reconciliation before this migration';
  end if;
end
$$;

-- M-16: cloning is complete by construction. Every public table carrying an
-- organization_id must be cloned or deliberately excluded, and new tables make
-- the function fail loudly until classified.
create or replace function public.clone_org_data(p_source uuid, p_target uuid, p_owner uuid)
returns integer
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $_$
declare
  v_tables text[] := array[
    'categories', 'business_units', 'cost_centers', 'suppliers',
    'project_choice_options',
    'supplier_contacts', 'supplier_notes', 'supplier_certifications',
    'supplier_performance_reviews', 'supplier_risks',
    'sourcing_events', 'project_updates', 'event_scope_lines',
    'baselines', 'baseline_lines',
    'supplier_offers', 'supplier_offer_lines',
    'awards', 'award_lines',
    'savings_calculations', 'savings_calculation_lines',
    'savings_periods', 'realization_periods'
  ];
  v_excluded_tables text[] := array[
    'audit_log',
    'organization_settings',
    'profiles'
  ];
  v_metadata_person_cols text[] := array['created_by', 'updated_by'];
  v_conditional_person_cols text[] := array[
    'procurement_owner_id', 'business_owner_id', 'finance_owner_id',
    'relationship_owner_id',
    'hard_reduction_override_by', 'baseline_approved_by',
    'business_equivalency_confirmed_by',
    'executed_by', 'savings_disposition_by',
    'finance_validated_by', 'comparison_rebased_by', 'award_approved_by'
  ];
  v_known_person_cols text[];
  v_unknown_person_cols text;
  v_unknown_tables text;
  t text;
  v_cols text;
  v_total integer := 0;
  v_count integer;
begin
  if p_source is null or p_target is null or p_owner is null then
    raise exception 'demo clone requires source, target, and owner';
  end if;
  if p_source = p_target then
    raise exception 'demo clone source and target must differ';
  end if;

  perform 1
  from public.organizations organization
  where organization.id = p_source
    and organization.is_demo_template;
  if not found then
    raise exception 'demo clone source must be the designated template';
  end if;

  perform 1
  from public.organizations organization
  join public.profiles profile
    on profile.organization_id = organization.id
   and profile.id = p_owner
  where organization.id = p_target
    and not organization.is_demo_template;
  if not found then
    raise exception 'demo clone owner must belong to the non-template target';
  end if;

  select string_agg(table_name, ', ' order by table_name)
  into v_unknown_tables
  from (
    select distinct column_row.table_name
    from information_schema.columns column_row
    where column_row.table_schema = 'public'
      and column_row.column_name = 'organization_id'
      and not (column_row.table_name = any(v_tables || v_excluded_tables))
  ) unclassified;

  if v_unknown_tables is not null then
    raise exception 'unclassified organization-scoped table in demo clone: %', v_unknown_tables;
  end if;

  v_known_person_cols := v_metadata_person_cols || v_conditional_person_cols;
  select string_agg(
    format('%I.%I', relation.relname, attribute.attname),
    ', ' order by relation.relname, attribute.attname
  )
  into v_unknown_person_cols
  from pg_catalog.pg_constraint foreign_key
  join pg_catalog.pg_class relation on relation.oid = foreign_key.conrelid
  join pg_catalog.pg_namespace namespace on namespace.oid = relation.relnamespace
  cross join lateral unnest(foreign_key.conkey) key_column(attnum)
  join pg_catalog.pg_attribute attribute
    on attribute.attrelid = relation.oid
   and attribute.attnum = key_column.attnum
  where foreign_key.contype = 'f'
    and foreign_key.confrelid = 'public.profiles'::regclass
    and namespace.nspname = 'public'
    and relation.relname = any(v_tables)
    and pg_catalog.cardinality(foreign_key.conkey) = 1
    and not (attribute.attname = any(v_known_person_cols));

  if v_unknown_person_cols is not null then
    raise exception 'unclassified profile reference in demo clone: %', v_unknown_person_cols;
  end if;

  insert into public.organization_settings (organization_id, updated_by)
  values (p_target, p_owner)
  on conflict (organization_id) do nothing;

  create temp table _idmap (old uuid primary key, new uuid not null) on commit drop;

  foreach t in array v_tables loop
    execute format(
      'insert into _idmap (old, new) select id, gen_random_uuid() from public.%I where organization_id = $1',
      t
    ) using p_source;
  end loop;

  foreach t in array v_tables loop
    select string_agg(
      case
        when column_row.column_name = 'id'
          then '(select map.new from _idmap map where map.old = source.id)'
        when column_row.column_name = 'organization_id'
          then '$2'
        when column_row.column_name = any(v_metadata_person_cols)
          then '$3'
        when column_row.column_name = any(v_conditional_person_cols)
          then format('case when source.%I is null then null else $3 end', column_row.column_name)
        when column_row.data_type = 'uuid'
          then format('(select map.new from _idmap map where map.old = source.%I)', column_row.column_name)
        else format('source.%I', column_row.column_name)
      end,
      ', ' order by column_row.ordinal_position
    )
    into v_cols
    from information_schema.columns column_row
    where column_row.table_schema = 'public'
      and column_row.table_name = t;

    execute format(
      'insert into public.%I select %s from public.%I source where source.organization_id = $1',
      t, v_cols, t
    ) using p_source, p_target, p_owner;

    get diagnostics v_count = row_count;
    v_total := v_total + v_count;
  end loop;

  -- A demo clone has a present steward. Do not manufacture actorless-legacy
  -- warnings in every new workspace from a template's historical import flag.
  update public.savings_calculations
  set executed_by = p_owner,
      legacy_execution_actor_missing = false,
      updated_by = p_owner,
      updated_at = now()
  where organization_id = p_target
    and calculation_status = 'executed'
    and legacy_execution_actor_missing;

  drop table _idmap;
  return v_total;
end
$_$;

revoke all on function public.clone_org_data(uuid, uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.clone_org_data(uuid, uuid, uuid) to service_role;

-- M-17: a correction of an actorless legacy execution becomes attributable to
-- the correcting user. Unrelated edits do not rewrite historical attribution.
create function public.attribute_corrected_legacy_execution()
returns trigger
language plpgsql
set search_path to 'pg_catalog', 'public'
as $$
begin
  if old.legacy_execution_actor_missing and (
    new.baseline_total_amount is distinct from old.baseline_total_amount
    or new.opening_proposal_amount is distinct from old.opening_proposal_amount
    or new.award_total_amount is distinct from old.award_total_amount
    or new.cost_reduction_amount is distinct from old.cost_reduction_amount
    or new.cost_avoidance_amount is distinct from old.cost_avoidance_amount
    or new.gross_savings_amount is distinct from old.gross_savings_amount
  ) then
    new.executed_by := coalesce(new.executed_by, auth.uid());
    if new.executed_by is not null then
      new.legacy_execution_actor_missing := false;
    end if;
  end if;
  return new;
end
$$;

revoke all on function public.attribute_corrected_legacy_execution()
  from public, anon, authenticated;
grant execute on function public.attribute_corrected_legacy_execution()
  to service_role;

create trigger savings_calculations_attribute_legacy_correction
before update of baseline_total_amount, opening_proposal_amount, award_total_amount,
  cost_reduction_amount, cost_avoidance_amount, gross_savings_amount
on public.savings_calculations
for each row execute function public.attribute_corrected_legacy_execution();

-- Low register: viewers are read-only, and all stored HTTP(S) URL constraints
-- use the same case-insensitive scheme rule.
drop policy project_updates_insert_org_author on public.project_updates;
create policy project_updates_insert_org_author
on public.project_updates
for insert to authenticated
with check (
  organization_id = (select public.current_org_id())
  and created_by = (select auth.uid())
  and exists (
    select 1 from public.profiles profile
    where profile.id = (select auth.uid())
      and profile.organization_id = project_updates.organization_id
      and profile.role in ('admin', 'procurement_user')
  )
  and exists (
    select 1 from public.sourcing_events event
    where event.id = project_updates.event_id
      and event.organization_id = project_updates.organization_id
  )
);

alter table public.supplier_certifications
  drop constraint supplier_certifications_url_check,
  add constraint supplier_certifications_url_check check (
    evidence_url is null
    or (char_length(evidence_url) <= 2000 and evidence_url ~* '^https?://')
  ) not valid;
alter table public.supplier_certifications validate constraint supplier_certifications_url_check;

alter table public.supplier_risks
  drop constraint supplier_risks_url_check,
  add constraint supplier_risks_url_check check (
    evidence_url is null
    or (char_length(evidence_url) <= 2000 and evidence_url ~* '^https?://')
  ) not valid;
alter table public.supplier_risks validate constraint supplier_risks_url_check;

commit;
