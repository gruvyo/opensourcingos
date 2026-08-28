-- =====================================================================
-- supabase/schema.sql -- GENERATED. Do not edit by hand.
--
--   regenerate:  npm run db:reset && npm run db:schema
--
-- This structure-only public-schema snapshot is generated from a clean
-- local rebuild of every committed migration. CI repeats that rebuild
-- and rejects drift between the migrations and this file.
--
-- Supabase-managed schemas (auth, storage, realtime, ...) are excluded.
-- public.handle_new_user() is called by a trigger on auth.users, which is
-- deliberately outside this snapshot.
-- =====================================================================




SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


CREATE SCHEMA IF NOT EXISTS "public";


ALTER SCHEMA "public" OWNER TO "pg_database_owner";


COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE OR REPLACE FUNCTION "public"."capture_workspace_audit"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'public'
    AS $$
declare
  v_org uuid;
  v_entity_id uuid;
  v_entity_type text;
begin
  if tg_table_name = 'organizations' then
    v_org := case when tg_op = 'DELETE' then old.id else new.id end;
    v_entity_id := v_org;
    v_entity_type := 'organization';
  elsif tg_table_name = 'organization_settings' then
    v_org := case when tg_op = 'DELETE' then old.organization_id else new.organization_id end;
    v_entity_id := v_org;
    v_entity_type := 'organization_settings';
  else
    v_org := case when tg_op = 'DELETE' then old.organization_id else new.organization_id end;
    v_entity_id := case when tg_op = 'DELETE' then old.id else new.id end;
    case tg_table_name
      when 'suppliers' then v_entity_type := 'supplier';
      when 'supplier_contacts' then v_entity_type := 'supplier_contact';
      when 'supplier_certifications' then v_entity_type := 'supplier_certification';
      when 'supplier_performance_reviews' then v_entity_type := 'supplier_performance_review';
      when 'supplier_risks' then v_entity_type := 'supplier_risk';
      when 'project_choice_options' then v_entity_type := 'project_choice_option';
      when 'categories' then v_entity_type := 'category';
      when 'business_units' then v_entity_type := 'business_unit';
      when 'cost_centers' then v_entity_type := 'cost_center';
      when 'savings_calculations' then v_entity_type := 'savings_calculation';
      when 'savings_periods' then v_entity_type := 'savings_period';
      when 'realization_periods' then v_entity_type := 'realization_period';
      when 'sourcing_events' then v_entity_type := 'sourcing_event';
      else raise exception 'unsupported workspace audit table: %', tg_table_name;
    end case;
  end if;

  insert into public.audit_log (
    organization_id, actor_id, entity_type, entity_id, action, before_data, after_data
  ) values (
    v_org,
    auth.uid(),
    v_entity_type,
    v_entity_id,
    lower(tg_op),
    case when tg_op in ('UPDATE', 'DELETE') then to_jsonb(old) end,
    case when tg_op in ('INSERT', 'UPDATE') then to_jsonb(new) end
  );

  if tg_op = 'DELETE' then return old; end if;
  return new;
end
$$;


ALTER FUNCTION "public"."capture_workspace_audit"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."cascade_project_choice_rename"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'pg_catalog', 'public'
    AS $$
begin
  if new.label is not distinct from old.label then
    return new;
  end if;

  if new.choice_type = 'event_type' then
    update public.sourcing_events
    set event_type = new.label
    where organization_id = new.organization_id
      and project_type = new.project_type
      and lower(btrim(event_type)) = lower(btrim(old.label));
  elsif new.choice_type = 'event_status' then
    update public.sourcing_events
    set event_status = new.label
    where organization_id = new.organization_id
      and project_type = new.project_type
      and lower(btrim(event_status)) = lower(btrim(old.label));
  else
    update public.sourcing_events
    set buyer_name = new.label
    where organization_id = new.organization_id
      and lower(btrim(buyer_name)) = lower(btrim(old.label));
  end if;

  return new;
end
$$;


ALTER FUNCTION "public"."cascade_project_choice_rename"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."clone_org_data"("p_source" "uuid", "p_target" "uuid", "p_owner" "uuid") RETURNS integer
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'public'
    AS $_$
declare
  v_tables text[] := array[
    'categories', 'business_units', 'cost_centers', 'suppliers',
    'project_choice_options',
    'sourcing_events', 'project_updates', 'event_scope_lines',
    'baselines', 'baseline_lines',
    'supplier_offers', 'supplier_offer_lines',
    'savings_calculations', 'savings_periods'
  ];
  -- Metadata always belongs to the new workspace owner. Ownership and
  -- decision actors preserve null (no assignment/decision) and otherwise
  -- move to that owner so no template profile can leak into the clone.
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

  -- A direct service invocation receives the same fresh settings guarantee as
  -- the signup trigger. ON CONFLICT deliberately preserves any explicit target
  -- settings instead of importing the template's preferences.
  insert into public.organization_settings (organization_id, updated_by)
  values (p_target, p_owner)
  on conflict (organization_id) do nothing;

  create temp table _idmap (old uuid primary key, new uuid not null) on commit drop;

  foreach t in array v_tables loop
    execute format(
      'insert into _idmap (old, new) select id, gen_random_uuid() from public.%I where organization_id = $1',
      t) using p_source;
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

  drop table _idmap;
  return v_total;
end
$_$;


ALTER FUNCTION "public"."clone_org_data"("p_source" "uuid", "p_target" "uuid", "p_owner" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."clone_org_data"("p_source" "uuid", "p_target" "uuid", "p_owner" "uuid") IS 'Copy every business row from one organization into another, allocating fresh ids and repointing references. Used to seed a new tester workspace.';



CREATE OR REPLACE FUNCTION "public"."complete_sourcing_project"("p_event_id" "uuid", "p_disposition" "text", "p_reason" "text" DEFAULT NULL::"text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'public'
    AS $$
declare
  v_user uuid := auth.uid();
  v_org uuid;
  v_role text;
  v_status text;
  v_completion_status text;
  v_reason text := nullif(btrim(p_reason), '');
begin
  if v_user is null then raise exception 'authentication required'; end if;

  select organization_id, role into v_org, v_role
  from public.profiles where id = v_user;
  if v_org is null then raise exception 'workspace membership required'; end if;
  if v_role not in ('admin', 'procurement_user') then
    raise exception 'administrator or procurement role required';
  end if;
  if p_disposition not in ('executed', 'no_executed_savings') then
    raise exception 'valid savings disposition required';
  end if;

  select event_status into v_status
  from public.sourcing_events
  where id = p_event_id
    and organization_id = v_org
    and project_type = 'Sourcing'
  for update;
  if not found then raise exception 'sourcing project not found'; end if;

  select label into v_completion_status
  from public.project_choice_options
  where organization_id = v_org
    and choice_type = 'event_status'
    and project_type = 'Sourcing'
    and requires_savings_disposition
    and active_flag;
  if not found then raise exception 'active sourcing completion status not found'; end if;
  if lower(btrim(v_status)) = lower(btrim(v_completion_status)) then
    raise exception 'project already complete';
  end if;

  if p_disposition = 'executed' then
    if not exists (
      select 1 from public.savings_calculations calculation
      where calculation.event_id = p_event_id
        and calculation.organization_id = v_org
        and calculation.calculation_status = 'executed'
    ) then
      raise exception 'executed savings schedule required';
    end if;
    v_reason := coalesce(v_reason, 'Savings schedule was marked executed before completion.');
  else
    if coalesce(length(v_reason), 0) < 10 then
      raise exception 'completion reason must contain at least 10 characters';
    end if;
    if exists (
      select 1 from public.savings_calculations calculation
      where calculation.event_id = p_event_id
        and calculation.organization_id = v_org
        and calculation.calculation_status = 'executed'
    ) then
      raise exception 'executed savings must use the executed disposition';
    end if;
  end if;

  update public.sourcing_events
  set event_status = v_completion_status,
      savings_disposition = p_disposition,
      savings_disposition_reason = v_reason,
      savings_disposition_at = now(),
      savings_disposition_by = v_user,
      updated_by = v_user,
      updated_at = now()
  where id = p_event_id and organization_id = v_org;
end
$$;


ALTER FUNCTION "public"."complete_sourcing_project"("p_event_id" "uuid", "p_disposition" "text", "p_reason" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."confirm_business_equivalency"("p_scope_line_id" "uuid", "p_confirmed" boolean) RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'public'
    AS $$
declare
  v_user uuid := auth.uid();
  v_org uuid;
  v_role text;
begin
  if v_user is null then raise exception 'authentication required'; end if;
  if p_confirmed is null then raise exception 'confirmed is required'; end if;

  select organization_id, role into v_org, v_role
  from public.profiles where id = v_user;
  if v_org is null then raise exception 'workspace membership required'; end if;
  if v_role not in ('admin', 'procurement_user') then
    raise exception 'administrator or procurement role required';
  end if;

  perform 1 from public.event_scope_lines
  where id = p_scope_line_id and organization_id = v_org
  for update;
  if not found then raise exception 'scope line not found'; end if;

  update public.event_scope_lines
  set business_equivalency_confirmed = p_confirmed,
      business_equivalency_confirmed_by = case when p_confirmed then v_user end,
      updated_by = v_user,
      updated_at = now()
  where id = p_scope_line_id and organization_id = v_org;
end
$$;


ALTER FUNCTION "public"."confirm_business_equivalency"("p_scope_line_id" "uuid", "p_confirmed" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."correct_savings_execution"("p_calc_id" "uuid", "p_note" "text", "p_calculation" "jsonb", "p_periods" "jsonb") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'public'
    AS $$
declare
  v_user uuid := auth.uid();
  v_org uuid;
  v_role text;
  v_event uuid;
  v_status text;
  v_existing_note text;
  v_existing_period_type text;
  v_count integer;
  v_existing_period_count integer;
  v_realization_count integer;
  v_has_evidence boolean;
  v_baseline numeric;
  v_opening numeric;
  v_final numeric;
  v_reduction numeric;
  v_avoidance numeric;
  v_total numeric;
  v_months numeric;
  v_first_month integer;
  v_first_year integer;
  v_period_type text;
  v_start_date date;
  v_end_date date;
  v_savings_type text;
begin
  if v_user is null then
    raise exception 'authentication required';
  end if;
  if nullif(btrim(p_note), '') is null then
    raise exception 'a correction note is required';
  end if;
  if jsonb_typeof(p_calculation) is distinct from 'object' then
    raise exception 'calculation must be a JSON object';
  end if;
  if jsonb_typeof(p_periods) is distinct from 'array' then
    raise exception 'periods must be a JSON array';
  end if;

  if exists (
    select 1
    from jsonb_object_keys(p_calculation) as calculation_key(field_name)
    where calculation_key.field_name not in (
      'calculation_name', 'savings_type', 'baseline_total_amount',
      'opening_proposal_amount', 'award_total_amount', 'gross_savings_amount',
      'net_savings_amount', 'cost_reduction_amount',
      'cost_avoidance_amount', 'savings_percentage', 'recognition_notes',
      'savings_start_date', 'savings_end_date', 'schedule_start_month',
      'schedule_start_year', 'schedule_period_type', 'schedule_period_count'
    )
  ) then
    raise exception 'calculation payload contains unsupported fields';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(p_periods) as period_item(value)
    cross join lateral jsonb_object_keys(period_item.value) as period_key(field_name)
    where period_key.field_name not in (
      'id', 'period_number', 'period_month', 'period_year', 'period_months',
      'baseline_amount', 'opening_amount', 'final_amount',
      'cost_reduction_amount', 'cost_avoidance_amount',
      'total_savings_amount', 'is_edited', 'notes'
    )
  ) then
    raise exception 'period payload contains unsupported fields';
  end if;

  v_count := jsonb_array_length(p_periods);
  if v_count not between 1 and 600 then
    raise exception 'correction must contain between 1 and 600 periods';
  end if;

  select organization_id, role into v_org, v_role
  from public.profiles
  where id = v_user;

  if v_org is null then
    raise exception 'workspace membership required';
  end if;
  if v_role not in ('admin', 'procurement_user') then
    raise exception 'administrator or procurement role required';
  end if;

  select event_id, calculation_status, execution_note, schedule_period_type
  into v_event, v_status, v_existing_note, v_existing_period_type
  from public.savings_calculations
  where id = p_calc_id
    and organization_id = v_org
  for update;

  if v_event is null then
    raise exception 'savings calculation not found';
  end if;
  if v_status <> 'executed' then
    raise exception 'only executed savings can be corrected';
  end if;

  perform 1
  from public.sourcing_events
  where id = v_event and organization_id = v_org
  for update;

  perform 1
  from public.savings_periods
  where savings_calculation_id = p_calc_id
    and organization_id = v_org
  order by id
  for update;

  select count(*) into v_existing_period_count
  from public.savings_periods
  where savings_calculation_id = p_calc_id
    and organization_id = v_org;

  perform 1
  from public.realization_periods
  where savings_calculation_id = p_calc_id
    and organization_id = v_org
  order by id
  for update;

  select
    count(*),
    coalesce(bool_or(
      actual_amount is not null
      or realized_savings is not null
      or coalesce(finance_validated, false)
    ), false)
  into v_realization_count, v_has_evidence
  from public.realization_periods
  where savings_calculation_id = p_calc_id
    and organization_id = v_org;

  if v_has_evidence and v_role <> 'admin' then
    raise exception 'an administrator must correct savings after realization evidence exists';
  end if;

  -- Parsing below also performs strict scalar type validation. Required
  -- fields must be present; nullable methodology anchors may explicitly be null.
  if exists (
    select 1
    from jsonb_array_elements(p_periods) as item(value)
    where not (item.value ? 'period_number')
      or not (item.value ? 'period_month')
      or not (item.value ? 'period_year')
      or not (item.value ? 'period_months')
      or not (item.value ? 'baseline_amount')
      or not (item.value ? 'opening_amount')
      or not (item.value ? 'final_amount')
      or not (item.value ? 'cost_reduction_amount')
      or not (item.value ? 'cost_avoidance_amount')
      or not (item.value ? 'total_savings_amount')
  ) then
    raise exception 'every corrected period must include its identity and complete value chain';
  end if;

  if (
    select count(*) <> v_count
      or count(distinct row.period_number) <> v_count
      or min(row.period_number) <> 1
      or max(row.period_number) <> v_count
    from jsonb_to_recordset(p_periods) as row(period_number integer)
  ) then
    raise exception 'period numbers must be unique and contiguous from 1';
  end if;

  if exists (
    select 1
    from jsonb_to_recordset(p_periods) as row(
      baseline_amount numeric,
      opening_amount numeric,
      final_amount numeric,
      cost_reduction_amount numeric,
      cost_avoidance_amount numeric,
      total_savings_amount numeric
    )
    where row.final_amount is null
      or row.cost_avoidance_amount is null
      or row.total_savings_amount is null
      or row.cost_reduction_amount is distinct from case
        when row.baseline_amount is null then null
        else row.baseline_amount - row.final_amount
      end
      or row.cost_avoidance_amount is distinct from case
        when row.opening_amount is not null and row.baseline_amount is not null
          then row.opening_amount - row.baseline_amount
        when row.opening_amount is not null
          then row.opening_amount - row.final_amount
        else 0
      end
      or row.total_savings_amount is distinct from case
        when row.opening_amount is not null then row.opening_amount - row.final_amount
        when row.baseline_amount is not null then row.baseline_amount - row.final_amount
        else 0
      end
  ) then
    raise exception 'corrected periods must satisfy the approved savings equations';
  end if;

  if exists (
    select 1
    from jsonb_to_recordset(p_periods) as row(id uuid)
    join public.savings_periods existing on existing.id = row.id
    where existing.savings_calculation_id <> p_calc_id
      or existing.organization_id <> v_org
  ) then
    raise exception 'a supplied period ID belongs to another savings calculation';
  end if;

  if v_has_evidence then
    -- Evidence freezes schedule identity and shape. Only business values may
    -- change; historical actuals are never moved to a different period.
    if (
      select count(row.id) <> v_count
        or count(distinct row.id) <> v_count
      from jsonb_to_recordset(p_periods) as row(id uuid)
    ) then
      raise exception 'every corrected period requires its existing ID once realization evidence exists';
    end if;

    if v_count <> v_existing_period_count or exists (
      select 1
      from public.savings_periods existing
      full join jsonb_to_recordset(p_periods) as row(
        id uuid,
        period_number integer,
        period_month integer,
        period_year integer,
        period_months numeric
      ) on row.id = existing.id
      where existing.savings_calculation_id = p_calc_id
        and existing.organization_id = v_org
        and (
          row.id is null
          or row.period_number is distinct from existing.period_number
          or row.period_month is distinct from existing.period_month
          or row.period_year is distinct from existing.period_year
          or row.period_months is distinct from existing.period_months
        )
    ) then
      raise exception 'schedule identity and dates cannot change after realization evidence exists';
    end if;

    update public.savings_periods as period
    set
      baseline_amount = row.baseline_amount,
      opening_amount = row.opening_amount,
      final_amount = row.final_amount,
      cost_reduction_amount = row.cost_reduction_amount,
      cost_avoidance_amount = row.cost_avoidance_amount,
      total_savings_amount = row.total_savings_amount,
      is_edited = coalesce(row.is_edited, true),
      notes = row.notes,
      executed_baseline_amount = row.baseline_amount,
      executed_opening_amount = row.opening_amount,
      executed_final_amount = row.final_amount,
      executed_cost_reduction_amount = row.cost_reduction_amount,
      executed_cost_avoidance_amount = row.cost_avoidance_amount,
      executed_total_savings_amount = row.total_savings_amount,
      updated_by = v_user,
      updated_at = now()
    from jsonb_to_recordset(p_periods) as row(
      id uuid,
      baseline_amount numeric,
      opening_amount numeric,
      final_amount numeric,
      cost_reduction_amount numeric,
      cost_avoidance_amount numeric,
      total_savings_amount numeric,
      is_edited boolean,
      notes text
    )
    where period.id = row.id
      and period.savings_calculation_id = p_calc_id
      and period.organization_id = v_org;

    update public.realization_periods as realization
    set
      baseline_amount = period.executed_baseline_amount,
      projected_savings = period.executed_total_savings_amount,
      leakage_amount = case
        when realization.realized_savings is null then null
        else period.executed_total_savings_amount - realization.realized_savings
      end,
      realization_status = case
        when realization.actual_amount is not null then
          case
            when realization.realized_savings is null then 'In Progress'
            when period.executed_total_savings_amount - realization.realized_savings <= 0 then 'Realized'
            when period.executed_total_savings_amount - realization.realized_savings < period.executed_total_savings_amount then 'Partially Realized'
            else 'Leaked'
          end
        when realization.realized_savings is not null then
          case
            when realization.realized_savings <= 0 then 'Not Realized'
            when period.executed_total_savings_amount - realization.realized_savings <= 0 then 'Realized'
            else 'Partially Realized'
          end
        else 'Pending'
      end,
      finance_validated = false,
      finance_validated_by = null,
      finance_validation_date = null,
      comparison_rebased_at = now(),
      comparison_rebased_by = v_user,
      updated_at = now(),
      updated_by = v_user
    from public.savings_periods as period
    where realization.savings_period_id = period.id
      and period.savings_calculation_id = p_calc_id
      and realization.organization_id = v_org;
  else
    -- No entered evidence: empty sync shells are auditably replaced along with
    -- the schedule and then recreated against the new period identities.
    delete from public.realization_periods
    where savings_calculation_id = p_calc_id
      and organization_id = v_org;

    delete from public.savings_periods
    where savings_calculation_id = p_calc_id
      and organization_id = v_org;

    insert into public.savings_periods (
      id, organization_id, event_id, savings_calculation_id,
      period_number, period_month, period_year, period_months,
      baseline_amount, opening_amount, final_amount,
      cost_reduction_amount, cost_avoidance_amount, total_savings_amount,
      is_edited, notes,
      executed_baseline_amount, executed_opening_amount, executed_final_amount,
      executed_cost_reduction_amount, executed_cost_avoidance_amount,
      executed_total_savings_amount,
      created_by, updated_by
    )
    select
      coalesce(row.id, gen_random_uuid()), v_org, v_event, p_calc_id,
      row.period_number, row.period_month, row.period_year, row.period_months,
      row.baseline_amount, row.opening_amount, row.final_amount,
      row.cost_reduction_amount, row.cost_avoidance_amount,
      row.total_savings_amount, coalesce(row.is_edited, true), row.notes,
      row.baseline_amount, row.opening_amount, row.final_amount,
      row.cost_reduction_amount, row.cost_avoidance_amount,
      row.total_savings_amount,
      v_user, v_user
    from jsonb_to_recordset(p_periods) as row(
      id uuid,
      period_number integer,
      period_month integer,
      period_year integer,
      period_months numeric,
      baseline_amount numeric,
      opening_amount numeric,
      final_amount numeric,
      cost_reduction_amount numeric,
      cost_avoidance_amount numeric,
      total_savings_amount numeric,
      is_edited boolean,
      notes text
    );

    if v_realization_count > 0 then
      insert into public.realization_periods (
        organization_id, event_id, savings_calculation_id, savings_period_id,
        period_name, period_start_date, period_end_date,
        baseline_amount, projected_savings, actual_amount, realized_savings,
        leakage_amount, realization_status, finance_validated,
        comparison_rebased_at, comparison_rebased_by,
        created_by, updated_by
      )
      select
        v_org, v_event, p_calc_id, period.id,
        to_char(make_date(period.period_year, period.period_month, 1), 'Mon YYYY'),
        make_date(period.period_year, period.period_month, 1),
        (
          make_date(period.period_year, period.period_month, 1)
          + (greatest(1, round(period.period_months))::text || ' months')::interval
          - interval '1 day'
        )::date,
        period.executed_baseline_amount,
        period.executed_total_savings_amount,
        null, null, null, 'Pending', false,
        now(), v_user, v_user, v_user
      from public.savings_periods as period
      where period.savings_calculation_id = p_calc_id
        and period.organization_id = v_org;
    end if;
  end if;

  select
    coalesce(sum(period_months), 0),
    coalesce(sum(baseline_amount), 0),
    coalesce(sum(opening_amount), 0),
    coalesce(sum(final_amount), 0),
    case when count(cost_reduction_amount) = 0 then null
         else sum(cost_reduction_amount) end,
    coalesce(sum(cost_avoidance_amount), 0),
    coalesce(sum(total_savings_amount), 0),
    (array_agg(period_month order by period_number))[1],
    (array_agg(period_year order by period_number))[1]
  into v_months, v_baseline, v_opening, v_final, v_reduction,
       v_avoidance, v_total, v_first_month, v_first_year
  from public.savings_periods
  where savings_calculation_id = p_calc_id
    and organization_id = v_org;

  v_period_type := coalesce(nullif(p_calculation->>'schedule_period_type', ''), v_existing_period_type, 'monthly');
  if v_period_type not in ('monthly', 'annual', 'one_time') then
    raise exception 'unsupported schedule period type';
  end if;

  v_start_date := make_date(v_first_year, v_first_month, 1);
  v_end_date := (
    v_start_date
    + (greatest(1, round(v_months))::text || ' months')::interval
    - interval '1 day'
  )::date;
  v_savings_type := case when coalesce(v_reduction, 0) >= v_avoidance
    then 'Cost Reduction' else 'Cost Avoidance' end;

  if p_calculation ? 'baseline_total_amount'
    and (p_calculation->>'baseline_total_amount')::numeric is distinct from v_baseline then
    raise exception 'calculation baseline total does not match corrected periods';
  end if;
  if p_calculation ? 'opening_proposal_amount'
    and (p_calculation->>'opening_proposal_amount')::numeric is distinct from v_opening then
    raise exception 'calculation opening total does not match corrected periods';
  end if;
  if p_calculation ? 'award_total_amount'
    and (p_calculation->>'award_total_amount')::numeric is distinct from v_final then
    raise exception 'calculation final total does not match corrected periods';
  end if;
  if p_calculation ? 'cost_reduction_amount'
    and (p_calculation->>'cost_reduction_amount')::numeric is distinct from v_reduction then
    raise exception 'calculation reduction total does not match corrected periods';
  end if;
  if p_calculation ? 'cost_avoidance_amount'
    and (p_calculation->>'cost_avoidance_amount')::numeric is distinct from v_avoidance then
    raise exception 'calculation avoidance total does not match corrected periods';
  end if;
  if p_calculation ? 'gross_savings_amount'
    and (p_calculation->>'gross_savings_amount')::numeric is distinct from v_total then
    raise exception 'calculation savings total does not match corrected periods';
  end if;
  if p_calculation ? 'net_savings_amount'
    and (p_calculation->>'net_savings_amount')::numeric is distinct from v_total then
    raise exception 'calculation net savings does not match corrected periods';
  end if;
  if p_calculation ? 'savings_type'
    and p_calculation->>'savings_type' is distinct from v_savings_type then
    raise exception 'calculation savings type does not match corrected periods';
  end if;
  if p_calculation ? 'schedule_period_count'
    and (p_calculation->>'schedule_period_count')::integer is distinct from v_count then
    raise exception 'calculation period count does not match corrected periods';
  end if;
  if p_calculation ? 'schedule_start_month'
    and (p_calculation->>'schedule_start_month')::integer is distinct from v_first_month then
    raise exception 'calculation start month does not match corrected periods';
  end if;
  if p_calculation ? 'schedule_start_year'
    and (p_calculation->>'schedule_start_year')::integer is distinct from v_first_year then
    raise exception 'calculation start year does not match corrected periods';
  end if;
  if p_calculation ? 'savings_start_date'
    and (p_calculation->>'savings_start_date')::date is distinct from v_start_date then
    raise exception 'calculation start date does not match corrected periods';
  end if;
  if p_calculation ? 'savings_end_date'
    and (p_calculation->>'savings_end_date')::date is distinct from v_end_date then
    raise exception 'calculation end date does not match corrected periods';
  end if;
  if p_calculation ? 'calculation_name'
    and nullif(btrim(p_calculation->>'calculation_name'), '') is null then
    raise exception 'calculation name cannot be blank';
  end if;

  update public.savings_calculations
  set
    calculation_name = coalesce(
      nullif(btrim(p_calculation->>'calculation_name'), ''),
      v_count || '-period savings schedule'
    ),
    savings_type = v_savings_type,
    baseline_total_amount = v_baseline,
    opening_proposal_amount = v_opening,
    award_total_amount = v_final,
    gross_savings_amount = v_total,
    net_savings_amount = v_total,
    cost_reduction_amount = v_reduction,
    cost_avoidance_amount = v_avoidance,
    savings_percentage = case when v_baseline > 0
      then round((v_total / v_baseline) * 100, 2) else null end,
    recognition_notes = coalesce(
      p_calculation->>'recognition_notes',
      'Corrected executed schedule: ' || v_count || ' periods.'
    ),
    savings_start_date = v_start_date,
    savings_end_date = v_end_date,
    schedule_start_month = v_first_month,
    schedule_start_year = v_first_year,
    schedule_period_type = v_period_type,
    schedule_period_count = v_count,
    execution_note = concat_ws(
      E'\n',
      nullif(v_existing_note, ''),
      '[' || to_char(now(), 'YYYY-MM-DD HH24:MI:SSOF') || '] Correction: ' || btrim(p_note)
    ),
    updated_by = v_user,
    updated_at = now()
  where id = p_calc_id
    and organization_id = v_org;
end
$$;


ALTER FUNCTION "public"."correct_savings_execution"("p_calc_id" "uuid", "p_note" "text", "p_calculation" "jsonb", "p_periods" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."current_org_id"() RETURNS "uuid"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'public'
    AS $$
  select organization_id from public.profiles where id = auth.uid()
$$;


ALTER FUNCTION "public"."current_org_id"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."derive_realization_period_fields"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'pg_catalog', 'public'
    AS $$
declare
  v_period public.savings_periods%rowtype;
begin
  if new.savings_period_id is not null then
    select * into v_period
    from public.savings_periods
    where id = new.savings_period_id;

    if found then
      new.baseline_amount := v_period.executed_baseline_amount;
      new.projected_reduction_amount := v_period.executed_cost_reduction_amount;
      new.projected_avoidance_amount := v_period.executed_cost_avoidance_amount;
    end if;
  end if;

  if new.actual_amount is not null and (
    tg_op = 'INSERT'
    or new.actual_amount is distinct from old.actual_amount
  ) then
    if new.projected_reduction_amount is null or new.baseline_amount is null then
      raise exception 'actual spend requires an executed reduction comparator' using errcode = '23514';
    end if;
    new.realized_reduction_amount := new.baseline_amount - new.actual_amount;
  end if;

  new.projected_savings := case
    when new.projected_reduction_amount is null and new.projected_avoidance_amount is null then null
    else coalesce(new.projected_reduction_amount, 0) + coalesce(new.projected_avoidance_amount, 0)
  end;
  new.realized_savings := case
    when new.realized_reduction_amount is null and new.realized_avoidance_amount is null then null
    else coalesce(new.realized_reduction_amount, 0) + coalesce(new.realized_avoidance_amount, 0)
  end;
  new.leakage_amount := case
    when new.projected_reduction_amount is null or new.realized_reduction_amount is null then null
    else greatest(new.projected_reduction_amount - new.realized_reduction_amount, 0)
  end;
  new.realization_status := public.derive_realization_status(
    new.projected_reduction_amount,
    new.projected_avoidance_amount,
    new.realized_reduction_amount,
    new.realized_avoidance_amount
  );

  return new;
end
$$;


ALTER FUNCTION "public"."derive_realization_period_fields"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."derive_realization_status"("p_projected_reduction" numeric, "p_projected_avoidance" numeric, "p_realized_reduction" numeric, "p_realized_avoidance" numeric) RETURNS "text"
    LANGUAGE "plpgsql" IMMUTABLE
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  v_reduction_expected boolean := p_projected_reduction is not null and p_projected_reduction <> 0;
  v_avoidance_expected boolean := p_projected_avoidance is not null and p_projected_avoidance <> 0;
  v_realized_total numeric := coalesce(p_realized_reduction, 0) + coalesce(p_realized_avoidance, 0);
  v_reduction_leakage numeric := case
    when p_projected_reduction is null or p_realized_reduction is null then null
    else greatest(p_projected_reduction - p_realized_reduction, 0)
  end;
begin
  if p_realized_reduction is null and p_realized_avoidance is null then
    return 'Pending';
  end if;

  if (v_reduction_expected and p_realized_reduction is null)
    or (v_avoidance_expected and p_realized_avoidance is null) then
    return 'In Progress';
  end if;

  if v_realized_total <= 0 then
    return case when coalesce(v_reduction_leakage, 0) > 0 then 'Leaked' else 'Not Realized' end;
  end if;

  if (not v_reduction_expected or p_realized_reduction >= p_projected_reduction)
    and (not v_avoidance_expected or p_realized_avoidance >= p_projected_avoidance) then
    return 'Realized';
  end if;

  return 'Partially Realized';
end
$$;


ALTER FUNCTION "public"."derive_realization_status"("p_projected_reduction" numeric, "p_projected_avoidance" numeric, "p_realized_reduction" numeric, "p_realized_avoidance" numeric) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."enforce_completed_project_savings_disposition"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'pg_catalog', 'public'
    AS $$
begin
  if new.project_type = 'Sourcing' and exists (
    select 1
    from public.project_choice_options choice
    where choice.organization_id = new.organization_id
      and choice.choice_type = 'event_status'
      and choice.project_type = new.project_type
      and choice.requires_savings_disposition
      and lower(btrim(choice.label)) = lower(btrim(new.event_status))
  ) then
    if new.savings_disposition is null then
      raise exception 'Choose whether scheduled savings were executed before completing this project';
    end if;

    if new.savings_disposition = 'executed' and not exists (
      select 1
      from public.savings_calculations as calculation
      where calculation.event_id = new.id
        and calculation.calculation_status = 'executed'
    ) then
      raise exception 'The project cannot be completed as executed until its savings schedule is marked executed';
    end if;

    if new.savings_disposition = 'no_executed_savings'
      and length(btrim(coalesce(new.savings_disposition_reason, ''))) < 10 then
      raise exception 'Explain why the project completed without executed savings';
    end if;
  end if;
  return new;
end
$$;


ALTER FUNCTION "public"."enforce_completed_project_savings_disposition"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."enforce_project_business_unit_setting"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'pg_catalog', 'public'
    AS $$
begin
  if coalesce(
    (
      select settings.project_business_units_enabled
      from public.organization_settings as settings
      where settings.organization_id = new.organization_id
    ),
    true
  ) then
    return new;
  end if;

  if tg_op = 'INSERT' then
    if new.business_unit_id is not null then
      raise exception 'Project Business Units are disabled for this workspace'
        using errcode = '23514';
    end if;

    return new;
  end if;

  if new.business_unit_id is distinct from old.business_unit_id then
    raise exception 'Project Business Units are disabled for this workspace'
      using errcode = '23514';
  end if;

  return new;
end
$$;


ALTER FUNCTION "public"."enforce_project_business_unit_setting"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."enforce_project_category_setting"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'pg_catalog', 'public'
    AS $$
begin
  if coalesce(
    (
      select settings.project_categories_enabled
      from public.organization_settings as settings
      where settings.organization_id = new.organization_id
    ),
    true
  ) then
    return new;
  end if;

  if tg_op = 'INSERT' then
    if new.category_id is not null then
      raise exception 'Project Categories are disabled for this workspace'
        using errcode = '23514';
    end if;

    return new;
  end if;

  if new.category_id is distinct from old.category_id then
    raise exception 'Project Categories are disabled for this workspace'
      using errcode = '23514';
  end if;

  return new;
end
$$;


ALTER FUNCTION "public"."enforce_project_category_setting"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."enforce_project_choice_options"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'pg_catalog', 'public'
    AS $$
begin
  if tg_op = 'INSERT'
    or new.project_type is distinct from old.project_type
    or new.event_type is distinct from old.event_type then
    if not exists (
      select 1 from public.project_choice_options choice
      where choice.organization_id = new.organization_id
        and choice.choice_type = 'event_type'
        and choice.project_type = new.project_type
        and choice.active_flag
        and lower(btrim(choice.label)) = lower(btrim(new.event_type))
    ) then
      raise exception 'Project type is not an active workspace choice' using errcode = '23514';
    end if;
  end if;

  if tg_op = 'INSERT'
    or new.project_type is distinct from old.project_type
    or new.event_status is distinct from old.event_status then
    if not exists (
      select 1 from public.project_choice_options choice
      where choice.organization_id = new.organization_id
        and choice.choice_type = 'event_status'
        and choice.project_type = new.project_type
        and choice.active_flag
        and lower(btrim(choice.label)) = lower(btrim(new.event_status))
    ) then
      raise exception 'Project status is not an active workspace choice' using errcode = '23514';
    end if;
  end if;

  if (tg_op = 'INSERT' or new.buyer_name is distinct from old.buyer_name)
    and nullif(btrim(new.buyer_name), '') is not null then
    if not exists (
      select 1 from public.project_choice_options choice
      where choice.organization_id = new.organization_id
        and choice.choice_type = 'owner'
        and choice.project_type is null
        and choice.active_flag
        and lower(btrim(choice.label)) = lower(btrim(new.buyer_name))
    ) then
      raise exception 'Project owner is not an active workspace choice' using errcode = '23514';
    end if;
  end if;

  if (tg_op = 'INSERT' or new.category_id is distinct from old.category_id)
    and new.category_id is not null
    and not exists (
      select 1 from public.categories category
      where category.id = new.category_id
        and category.organization_id = new.organization_id
        and category.active_flag
    ) then
    raise exception 'Project Category is not an active workspace choice' using errcode = '23514';
  end if;

  if (tg_op = 'INSERT' or new.business_unit_id is distinct from old.business_unit_id)
    and new.business_unit_id is not null
    and not exists (
      select 1 from public.business_units unit
      where unit.id = new.business_unit_id
        and unit.organization_id = new.organization_id
        and unit.active_flag
    ) then
    raise exception 'Project Business Unit is not an active workspace choice' using errcode = '23514';
  end if;

  if (tg_op = 'INSERT' or new.cost_center_id is distinct from old.cost_center_id)
    and new.cost_center_id is not null
    and not exists (
      select 1 from public.cost_centers center
      where center.id = new.cost_center_id
        and center.organization_id = new.organization_id
        and center.active_flag
    ) then
    raise exception 'Project Cost Center is not an active workspace choice' using errcode = '23514';
  end if;

  return new;
end
$$;


ALTER FUNCTION "public"."enforce_project_choice_options"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."enforce_project_cost_center_setting"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'pg_catalog', 'public'
    AS $$
begin
  if coalesce(
    (
      select settings.project_cost_centers_enabled
      from public.organization_settings as settings
      where settings.organization_id = new.organization_id
    ),
    true
  ) then
    return new;
  end if;

  if tg_op = 'INSERT' then
    if new.cost_center_id is not null then
      raise exception 'Project Cost Centers are disabled for this workspace'
        using errcode = '23514';
    end if;

    return new;
  end if;

  if new.cost_center_id is distinct from old.cost_center_id then
    raise exception 'Project Cost Centers are disabled for this workspace'
      using errcode = '23514';
  end if;

  return new;
end
$$;


ALTER FUNCTION "public"."enforce_project_cost_center_setting"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."enforce_project_description_setting"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'pg_catalog', 'public'
    AS $$
begin
  if coalesce(
    (
      select settings.project_descriptions_enabled
      from public.organization_settings as settings
      where settings.organization_id = new.organization_id
    ),
    true
  ) then
    return new;
  end if;

  if tg_op = 'INSERT' then
    if nullif(btrim(new.event_description), '') is not null then
      raise exception 'Project descriptions are disabled for this workspace'
        using errcode = '23514';
    end if;

    return new;
  end if;

  if new.event_description is distinct from old.event_description then
    raise exception 'Project descriptions are disabled for this workspace'
      using errcode = '23514';
  end if;

  return new;
end
$$;


ALTER FUNCTION "public"."enforce_project_description_setting"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."enforce_project_incumbent_supplier_setting"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'pg_catalog', 'public'
    AS $$
begin
  if coalesce(
    (
      select settings.project_incumbent_suppliers_enabled
      from public.organization_settings as settings
      where settings.organization_id = new.organization_id
    ),
    true
  ) then
    return new;
  end if;

  if (tg_op = 'INSERT' and new.incumbent_supplier_id is not null)
    or (tg_op = 'UPDATE' and new.incumbent_supplier_id is distinct from old.incumbent_supplier_id) then
    raise exception 'Project Incumbent Supplier is disabled for this workspace'
      using errcode = '23514';
  end if;

  return new;
end
$$;


ALTER FUNCTION "public"."enforce_project_incumbent_supplier_setting"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."enforce_project_owner_setting"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'pg_catalog', 'public'
    AS $$
begin
  if coalesce(
    (
      select settings.project_owners_enabled
      from public.organization_settings as settings
      where settings.organization_id = new.organization_id
    ),
    true
  ) then
    return new;
  end if;

  if tg_op = 'INSERT' then
    if nullif(btrim(new.buyer_name), '') is not null then
      raise exception 'Project owners are disabled for this workspace'
        using errcode = '23514';
    end if;

    return new;
  end if;

  if new.buyer_name is distinct from old.buyer_name then
    raise exception 'Project owners are disabled for this workspace'
      using errcode = '23514';
  end if;

  return new;
end
$$;


ALTER FUNCTION "public"."enforce_project_owner_setting"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."enforce_project_updates_setting"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'pg_catalog', 'public'
    AS $$
begin
  if coalesce(
    (
      select settings.project_updates_enabled
      from public.organization_settings as settings
      where settings.organization_id = new.organization_id
    ),
    true
  ) then
    return new;
  end if;

  raise exception 'Project Updates are disabled for this workspace'
    using errcode = '23514';
end
$$;


ALTER FUNCTION "public"."enforce_project_updates_setting"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."enforce_savings_completion_invariant"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'pg_catalog', 'public'
    AS $$
declare
  v_event_id uuid;
  v_organization_id uuid;
  v_project_type text;
  v_event_status text;
  v_disposition text;
  v_reason text;
begin
  if tg_table_name = 'sourcing_events' then
    v_event_id := case when tg_op = 'DELETE' then old.id else new.id end;
  else
    v_event_id := case when tg_op = 'DELETE' then old.event_id else new.event_id end;
  end if;

  select organization_id, project_type, event_status, savings_disposition, savings_disposition_reason
  into v_organization_id, v_project_type, v_event_status, v_disposition, v_reason
  from public.sourcing_events
  where id = v_event_id;

  if not found then
    return case when tg_op = 'DELETE' then old else new end;
  end if;

  if v_project_type = 'Sourcing' and exists (
    select 1
    from public.project_choice_options choice
    where choice.organization_id = v_organization_id
      and choice.choice_type = 'event_status'
      and choice.project_type = v_project_type
      and choice.requires_savings_disposition
      and lower(btrim(choice.label)) = lower(btrim(v_event_status))
  ) then
    if v_disposition is null then
      raise exception 'completed sourcing projects require a savings disposition';
    end if;

    if v_disposition = 'executed' and not exists (
      select 1
      from public.savings_calculations
      where event_id = v_event_id
        and calculation_status = 'executed'
    ) then
      raise exception 'an executed disposition requires an executed savings calculation';
    end if;

    if v_disposition = 'no_executed_savings'
      and length(btrim(coalesce(v_reason, ''))) < 10 then
      raise exception 'completed projects without executed savings require a reason';
    end if;
  end if;

  return case when tg_op = 'DELETE' then old else new end;
end
$$;


ALTER FUNCTION "public"."enforce_savings_completion_invariant"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."enforce_savings_execution_invariant"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'pg_catalog', 'public'
    AS $$
declare
  v_calculation_id uuid;
  v_status text;
  v_executed_at timestamptz;
  v_executed_by uuid;
  v_execution_note text;
  v_legacy_actor_missing boolean;
begin
  if tg_table_name = 'savings_calculations' then
    v_calculation_id := case when tg_op = 'DELETE' then old.id else new.id end;
  else
    v_calculation_id := case
      when tg_op = 'DELETE' then old.savings_calculation_id
      else new.savings_calculation_id
    end;
  end if;

  select
    calculation_status,
    executed_at,
    executed_by,
    execution_note,
    legacy_execution_actor_missing
  into
    v_status,
    v_executed_at,
    v_executed_by,
    v_execution_note,
    v_legacy_actor_missing
  from public.savings_calculations
  where id = v_calculation_id;

  -- A parent delete removes the calculation, so there is no calculation state
  -- left to validate. Retention and completion have their own guards below.
  if not found then
    return case when tg_op = 'DELETE' then old else new end;
  end if;

  if v_status = 'executed' then
    if v_executed_at is null
      or (v_executed_by is null and not v_legacy_actor_missing) then
      raise exception 'executed savings require an execution time and actor';
    end if;

    if not exists (
      select 1 from public.savings_periods
      where savings_calculation_id = v_calculation_id
    ) then
      raise exception 'executed savings require at least one schedule period';
    end if;

    if exists (
      select 1
      from public.savings_periods
      where savings_calculation_id = v_calculation_id
        and (
          executed_total_savings_amount is null
          or executed_final_amount is null
          or executed_cost_avoidance_amount is null
        )
    ) then
      raise exception 'every executed schedule period requires a complete snapshot';
    end if;
  elsif v_status = 'estimated' then
    if v_executed_at is not null
      or v_executed_by is not null
      or v_execution_note is not null
      or v_legacy_actor_missing then
      raise exception 'estimated savings cannot retain execution metadata';
    end if;

    if exists (
      select 1
      from public.savings_periods
      where savings_calculation_id = v_calculation_id
        and (
          executed_baseline_amount is not null
          or executed_opening_amount is not null
          or executed_final_amount is not null
          or executed_cost_reduction_amount is not null
          or executed_cost_avoidance_amount is not null
          or executed_total_savings_amount is not null
        )
    ) then
      raise exception 'estimated savings cannot retain executed schedule snapshots';
    end if;
  end if;

  return case when tg_op = 'DELETE' then old else new end;
end
$$;


ALTER FUNCTION "public"."enforce_savings_execution_invariant"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."enforce_savings_realization_setting"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'pg_catalog', 'public'
    AS $$
declare
  v_org uuid := case when tg_op = 'DELETE' then old.organization_id else new.organization_id end;
begin
  if tg_op = 'DELETE'
    and old.actual_amount is null
    and old.realized_savings is null
    and not coalesce(old.finance_validated, false)
    and exists (
      select 1 from public.profiles profile
      where profile.id = auth.uid()
        and profile.organization_id = v_org
        and profile.role in ('admin', 'procurement_user')
    ) then
    return old;
  end if;

  if not coalesce((
    select settings.savings_realization_enabled
    from public.organization_settings as settings
    where settings.organization_id = v_org
  ), false) then
    raise exception 'Savings Realization is disabled for this workspace';
  end if;

  return case when tg_op = 'DELETE' then old else new end;
end
$$;


ALTER FUNCTION "public"."enforce_savings_realization_setting"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."enforce_sourcing_project_savings"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'pg_catalog', 'public'
    AS $$
declare
  v_event_id uuid;
  v_calculation_event_id uuid;
  v_event_organization_id uuid;
  v_project_type text;
begin
  if tg_table_name = 'sourcing_events' then
    if new.project_type = 'Sourcing' or new.project_type is not distinct from old.project_type then
      return new;
    end if;

    if exists (
      select 1 from public.savings_calculations savings_row where savings_row.event_id = new.id
    ) or exists (
      select 1 from public.savings_calculation_lines savings_row where savings_row.event_id = new.id
    ) or exists (
      select 1 from public.savings_periods savings_row where savings_row.event_id = new.id
    ) or exists (
      select 1 from public.realization_periods savings_row where savings_row.event_id = new.id
    ) then
      raise exception 'Projects with savings records cannot be changed to Support / Non-Commercial'
        using errcode = '23514';
    end if;

    return new;
  end if;

  if tg_table_name = 'savings_calculations' then
    v_event_id := new.event_id;
  elsif tg_table_name = 'savings_calculation_lines' then
    if new.savings_calculation_id is null then
      raise exception 'Savings detail requires a project calculation'
        using errcode = '23514';
    end if;

    select calculation.event_id
      into v_calculation_event_id
    from public.savings_calculations calculation
    where calculation.id = new.savings_calculation_id;

    if not found or v_calculation_event_id is null then
      raise exception 'Savings detail requires a linked project calculation'
        using errcode = '23514';
    end if;

    if new.event_id is distinct from v_calculation_event_id then
      raise exception 'Savings detail must use its calculation project'
        using errcode = '23514';
    end if;

    v_event_id := v_calculation_event_id;
  elsif tg_table_name = 'savings_periods' then
    select calculation.event_id
      into v_calculation_event_id
    from public.savings_calculations calculation
    where calculation.id = new.savings_calculation_id;

    if not found or v_calculation_event_id is null then
      raise exception 'Savings schedule requires a linked project calculation'
        using errcode = '23514';
    end if;

    if new.event_id is distinct from v_calculation_event_id then
      raise exception 'Savings schedule must use its calculation project'
        using errcode = '23514';
    end if;

    v_event_id := v_calculation_event_id;
  elsif tg_table_name = 'realization_periods' then
    v_event_id := new.event_id;

    if new.savings_calculation_id is not null then
      select calculation.event_id
        into v_calculation_event_id
      from public.savings_calculations calculation
      where calculation.id = new.savings_calculation_id;

      if not found or v_calculation_event_id is distinct from v_event_id then
        raise exception 'Savings realization must use its calculation project'
          using errcode = '23514';
      end if;
    end if;
  else
    raise exception 'Unsupported savings guard table: %', tg_table_name;
  end if;

  -- event_id remains nullable for a narrow legacy/invariant-test path. Unlinked
  -- rows are excluded by every reporting population and cannot be schedules or
  -- realization evidence. Linked project savings are the boundary enforced here.
  if tg_table_name = 'savings_calculations' and v_event_id is null then
    return new;
  end if;

  if v_event_id is null then
    raise exception 'Savings records require a linked Sourcing Project'
      using errcode = '23514';
  end if;

  -- The parent lock serializes savings creation against a simultaneous attempt
  -- to convert this project to Support / Non-Commercial.
  select event.organization_id, event.project_type
    into v_event_organization_id, v_project_type
  from public.sourcing_events event
  where event.id = v_event_id
  for key share;

  if not found or v_project_type is distinct from 'Sourcing' then
    raise exception 'Savings records require a Sourcing Project'
      using errcode = '23514';
  end if;

  if new.organization_id is distinct from v_event_organization_id then
    raise exception 'Savings records must use the project workspace'
      using errcode = '23514';
  end if;

  return new;
end
$$;


ALTER FUNCTION "public"."enforce_sourcing_project_savings"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."enforce_support_project_setting"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'pg_catalog', 'public'
    AS $$
begin
  if new.project_type is distinct from 'Support' then
    return new;
  end if;

  if tg_op = 'UPDATE'
    and old.project_type is not distinct from new.project_type then
    return new;
  end if;

  if coalesce(
    (
      select settings.support_projects_enabled
      from public.organization_settings as settings
      where settings.organization_id = new.organization_id
    ),
    true
  ) then
    return new;
  end if;

  raise exception 'Support / Non-Commercial projects are disabled for this workspace'
    using errcode = '23514';
end
$$;


ALTER FUNCTION "public"."enforce_support_project_setting"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."handle_new_user"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'public'
    AS $$
declare
  v_org uuid;
  v_template uuid;
  v_name text := coalesce(new.raw_user_meta_data->>'full_name', new.email);
begin
  insert into public.organizations (name)
  values (v_name || ' (workspace)')
  returning id into v_org;

  insert into public.profiles (id, email, full_name, organization_id, role)
  values (new.id, new.email, v_name, v_org, 'admin');

  -- Settings are outside the best-effort clone block: even a missing or broken
  -- demo must not leave the new workspace with implicit, divergent fallbacks.
  insert into public.organization_settings (organization_id, updated_by)
  values (v_org, new.id);

  begin
    select organization.id into v_template
    from public.organizations organization
    where organization.is_demo_template
    order by organization.id
    limit 1;

    if v_template is not null then
      perform public.clone_org_data(v_template, v_org, new.id);
    end if;
  exception when others then
    raise warning 'demo seed failed for %: %', new.email, sqlerrm;
  end;

  return new;
end
$$;


ALTER FUNCTION "public"."handle_new_user"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."mark_savings_schedule_executed"("p_savings_calculation_id" "uuid", "p_execution_note" "text" DEFAULT NULL::"text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'public'
    AS $$
declare
  v_user uuid := auth.uid();
  v_org uuid;
  v_role text;
  v_event uuid;
  v_status text;
begin
  if v_user is null then
    raise exception 'authentication required';
  end if;

  select organization_id, role into v_org, v_role
  from public.profiles
  where id = v_user;

  if v_org is null then
    raise exception 'workspace membership required';
  end if;
  if v_role not in ('admin', 'procurement_user') then
    raise exception 'administrator or procurement role required';
  end if;

  select event_id, calculation_status into v_event, v_status
  from public.savings_calculations
  where id = p_savings_calculation_id
    and organization_id = v_org
  for update;

  if v_event is null then
    raise exception 'savings calculation not found';
  end if;
  if v_status = 'executed' then
    raise exception 'savings schedule is already executed';
  end if;
  if v_status <> 'estimated' then
    raise exception 'only an estimated savings schedule can be executed';
  end if;

  perform 1
  from public.sourcing_events
  where id = v_event
    and organization_id = v_org
    and project_type = 'Sourcing'
  for update;

  if not found then
    raise exception 'sourcing project not found';
  end if;

  perform 1
  from public.savings_periods
  where savings_calculation_id = p_savings_calculation_id
    and organization_id = v_org
  order by id
  for update;

  if not found then
    raise exception 'generate the savings schedule before marking it executed';
  end if;

  update public.savings_periods
  set
    executed_baseline_amount = baseline_amount,
    executed_opening_amount = opening_amount,
    executed_final_amount = final_amount,
    executed_cost_reduction_amount = cost_reduction_amount,
    executed_cost_avoidance_amount = cost_avoidance_amount,
    executed_total_savings_amount = total_savings_amount,
    updated_by = v_user,
    updated_at = now()
  where savings_calculation_id = p_savings_calculation_id
    and organization_id = v_org;

  update public.savings_calculations
  set
    calculation_status = 'executed',
    executed_at = now(),
    executed_by = v_user,
    execution_note = nullif(btrim(p_execution_note), ''),
    updated_by = v_user,
    updated_at = now()
  where id = p_savings_calculation_id
    and organization_id = v_org;

  update public.sourcing_events
  set
    savings_disposition = 'executed',
    savings_disposition_reason = coalesce(
      nullif(btrim(p_execution_note), ''),
      'Savings schedule explicitly marked executed.'
    ),
    savings_disposition_at = now(),
    savings_disposition_by = v_user,
    updated_by = v_user,
    updated_at = now()
  where id = v_event
    and organization_id = v_org;
end
$$;


ALTER FUNCTION "public"."mark_savings_schedule_executed"("p_savings_calculation_id" "uuid", "p_execution_note" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."normalize_project_choice_option"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'pg_catalog', 'public'
    AS $$
begin
  new.label := btrim(new.label);

  if tg_op = 'UPDATE' and (
    new.id is distinct from old.id
    or new.organization_id is distinct from old.organization_id
    or new.choice_type is distinct from old.choice_type
    or new.project_type is distinct from old.project_type
    or new.created_at is distinct from old.created_at
    or new.created_by is distinct from old.created_by
  ) then
    raise exception 'Project choice scope cannot be changed' using errcode = '23514';
  end if;

  return new;
end
$$;


ALTER FUNCTION "public"."normalize_project_choice_option"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."prevent_last_project_choice_archive"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'pg_catalog', 'public'
    AS $$
begin
  if old.active_flag
    and not new.active_flag
    and new.choice_type in ('event_type', 'event_status')
    and not exists (
      select 1 from public.project_choice_options choice
      where choice.organization_id = new.organization_id
        and choice.choice_type = new.choice_type
        and choice.project_type = new.project_type
        and choice.active_flag
        and choice.id <> new.id
    ) then
    raise exception 'At least one active project choice is required for this project type'
      using errcode = '23514';
  end if;

  return new;
end
$$;


ALTER FUNCTION "public"."prevent_last_project_choice_archive"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."prevent_profile_privilege_change"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'pg_catalog', 'public'
    AS $$
begin
  if current_user in ('anon', 'authenticated') then
    if new.organization_id is distinct from old.organization_id then
      raise exception 'organization_id cannot be changed by the user';
    end if;
    if new.role is distinct from old.role then
      raise exception 'role cannot be changed by the user';
    end if;
  end if;
  return new;
end
$$;


ALTER FUNCTION "public"."prevent_profile_privilege_change"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."prevent_realization_history_delete"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'pg_catalog', 'public'
    AS $$
begin
  if tg_table_name = 'sourcing_events' and exists (
    select 1 from public.realization_periods where event_id = old.id
  ) then
    raise exception 'project deletion is blocked while savings realization history exists';
  end if;

  if tg_table_name = 'savings_calculations' and exists (
    select 1 from public.realization_periods where savings_calculation_id = old.id
  ) then
    raise exception 'savings calculation deletion is blocked while realization history exists';
  end if;

  return old;
end
$$;


ALTER FUNCTION "public"."prevent_realization_history_delete"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."protect_sourcing_completion_status"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'pg_catalog', 'public'
    AS $$
begin
  if current_user in ('postgres', 'service_role', 'supabase_admin') then
    return new;
  end if;

  if tg_op = 'INSERT' and new.requires_savings_disposition then
    raise exception 'savings completion status metadata is system-managed' using errcode = '42501';
  end if;

  if tg_op = 'UPDATE' and (
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

  return new;
end
$$;


ALTER FUNCTION "public"."protect_sourcing_completion_status"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."replace_savings_schedule"("p_savings_calculation_id" "uuid", "p_schedule_start_month" integer, "p_schedule_start_year" integer, "p_schedule_period_type" "text", "p_periods" "jsonb") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'public'
    AS $$
declare
  v_user uuid := auth.uid();
  v_org uuid;
  v_role text;
  v_event uuid;
  v_status text;
  v_count integer;
  v_months numeric;
  v_baseline numeric;
  v_opening numeric;
  v_final numeric;
  v_reduction numeric;
  v_avoidance numeric;
  v_total numeric;
  v_end_date date;
begin
  if v_user is null then
    raise exception 'authentication required';
  end if;

  select organization_id, role into v_org, v_role
  from public.profiles
  where id = v_user;

  if v_org is null then
    raise exception 'workspace membership required';
  end if;
  if v_role not in ('admin', 'procurement_user') then
    raise exception 'administrator or procurement role required';
  end if;
  if p_schedule_start_month not between 1 and 12 then
    raise exception 'schedule start month must be between 1 and 12';
  end if;
  if p_schedule_start_year not between 2000 and 2100 then
    raise exception 'schedule start year must be between 2000 and 2100';
  end if;
  if p_schedule_period_type not in ('monthly', 'annual', 'one_time') then
    raise exception 'unsupported schedule period type';
  end if;
  if jsonb_typeof(p_periods) is distinct from 'array' then
    raise exception 'periods must be a JSON array';
  end if;

  v_count := jsonb_array_length(p_periods);
  if v_count not between 1 and 600 then
    raise exception 'schedule must contain between 1 and 600 periods';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(p_periods) as period_item(value)
    cross join lateral jsonb_object_keys(period_item.value) as period_key(field_name)
    where period_key.field_name not in (
      'period_number', 'period_month', 'period_year', 'period_months',
      'baseline_amount', 'opening_amount', 'final_amount',
      'cost_reduction_amount', 'cost_avoidance_amount',
      'total_savings_amount', 'is_edited', 'notes'
    )
  ) then
    raise exception 'period payload contains unsupported fields';
  end if;

  select event_id, calculation_status into v_event, v_status
  from public.savings_calculations
  where id = p_savings_calculation_id
    and organization_id = v_org
  for update;

  if v_event is null then
    raise exception 'savings calculation not found';
  end if;
  if v_status <> 'estimated' then
    raise exception 'executed schedules are preserved and cannot be regenerated';
  end if;

  perform 1
  from public.sourcing_events
  where id = v_event and organization_id = v_org
  for update;

  perform 1
  from public.savings_periods
  where savings_calculation_id = p_savings_calculation_id
    and organization_id = v_org
  order by id
  for update;

  -- Intentionally replace before parsing/inserting the rows. Any malformed row
  -- or constraint failure aborts the RPC transaction and restores the prior
  -- schedule and published header automatically.
  delete from public.savings_periods
  where savings_calculation_id = p_savings_calculation_id
    and organization_id = v_org;

  insert into public.savings_periods (
    organization_id, event_id, savings_calculation_id,
    period_number, period_month, period_year, period_months,
    baseline_amount, opening_amount, final_amount,
    cost_reduction_amount, cost_avoidance_amount, total_savings_amount,
    is_edited, notes, created_by, updated_by
  )
  select
    v_org, v_event, p_savings_calculation_id,
    row.period_number, row.period_month, row.period_year, row.period_months,
    row.baseline_amount, row.opening_amount, row.final_amount,
    row.cost_reduction_amount, row.cost_avoidance_amount,
    row.total_savings_amount, coalesce(row.is_edited, false), row.notes,
    v_user, v_user
  from jsonb_to_recordset(p_periods) as row(
    period_number integer,
    period_month integer,
    period_year integer,
    period_months numeric,
    baseline_amount numeric,
    opening_amount numeric,
    final_amount numeric,
    cost_reduction_amount numeric,
    cost_avoidance_amount numeric,
    total_savings_amount numeric,
    is_edited boolean,
    notes text
  );

  if (
    select count(*) <> v_count
      or count(distinct period_number) <> v_count
      or min(period_number) <> 1
      or max(period_number) <> v_count
    from public.savings_periods
    where savings_calculation_id = p_savings_calculation_id
      and organization_id = v_org
  ) then
    raise exception 'period numbers must be unique and contiguous from 1';
  end if;

  select
    coalesce(sum(period_months), 0),
    coalesce(sum(baseline_amount), 0),
    coalesce(sum(opening_amount), 0),
    coalesce(sum(final_amount), 0),
    case when count(cost_reduction_amount) = 0 then null
         else sum(cost_reduction_amount) end,
    coalesce(sum(cost_avoidance_amount), 0),
    coalesce(sum(total_savings_amount), 0)
  into v_months, v_baseline, v_opening, v_final,
       v_reduction, v_avoidance, v_total
  from public.savings_periods
  where savings_calculation_id = p_savings_calculation_id
    and organization_id = v_org;

  v_end_date := (
    make_date(p_schedule_start_year, p_schedule_start_month, 1)
    + (greatest(1, round(v_months))::text || ' months')::interval
    - interval '1 day'
  )::date;

  update public.savings_calculations
  set schedule_start_month = p_schedule_start_month,
      schedule_start_year = p_schedule_start_year,
      schedule_period_type = p_schedule_period_type,
      schedule_period_count = v_count,
      baseline_total_amount = v_baseline,
      opening_proposal_amount = v_opening,
      award_total_amount = v_final,
      gross_savings_amount = v_total,
      net_savings_amount = v_total,
      cost_reduction_amount = v_reduction,
      cost_avoidance_amount = v_avoidance,
      savings_type = case when coalesce(v_reduction, 0) >= v_avoidance
                          then 'Cost Reduction' else 'Cost Avoidance' end,
      savings_percentage = case when v_baseline > 0
                                then round((v_total / v_baseline) * 100, 2)
                                else null end,
      savings_start_date = make_date(p_schedule_start_year, p_schedule_start_month, 1),
      savings_end_date = v_end_date,
      calculation_name = v_count || '-period savings schedule',
      recognition_notes = 'Published from the savings schedule: ' || v_count
        || ' periods covering ' || round(v_months) || ' of ' || round(v_months)
        || ' deal months.',
      updated_by = v_user,
      updated_at = now()
  where id = p_savings_calculation_id
    and organization_id = v_org;
end
$$;


ALTER FUNCTION "public"."replace_savings_schedule"("p_savings_calculation_id" "uuid", "p_schedule_start_month" integer, "p_schedule_start_year" integer, "p_schedule_period_type" "text", "p_periods" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."reverse_savings_execution"("p_calc_id" "uuid", "p_note" "text", "p_disposition_action" "text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'public'
    AS $$
declare
  v_user uuid := auth.uid();
  v_org uuid;
  v_role text;
  v_event uuid;
  v_status text;
  v_existing_note text;
  v_project_type text;
  v_event_status text;
  v_requires_disposition boolean;
begin
  if v_user is null then raise exception 'authentication required'; end if;
  if nullif(btrim(p_note), '') is null then raise exception 'a reversal note is required'; end if;

  select organization_id, role into v_org, v_role
  from public.profiles where id = v_user;
  if v_org is null then raise exception 'workspace membership required'; end if;
  if v_role <> 'admin' then raise exception 'administrator role required'; end if;

  select event_id, calculation_status, execution_note
  into v_event, v_status, v_existing_note
  from public.savings_calculations
  where id = p_calc_id and organization_id = v_org
  for update;
  if v_event is null then raise exception 'savings calculation not found'; end if;
  if v_status <> 'executed' then raise exception 'savings schedule is not executed'; end if;

  select project_type, event_status into v_project_type, v_event_status
  from public.sourcing_events
  where id = v_event and organization_id = v_org
  for update;

  select exists (
    select 1 from public.project_choice_options choice
    where choice.organization_id = v_org
      and choice.choice_type = 'event_status'
      and choice.project_type = v_project_type
      and choice.requires_savings_disposition
      and lower(btrim(choice.label)) = lower(btrim(v_event_status))
  ) into v_requires_disposition;

  perform 1 from public.savings_periods
  where savings_calculation_id = p_calc_id and organization_id = v_org
  order by id for update;

  perform 1 from public.realization_periods
  where savings_calculation_id = p_calc_id and organization_id = v_org
  order by id for update;

  if exists (
    select 1 from public.realization_periods
    where savings_calculation_id = p_calc_id
      and organization_id = v_org
      and (actual_amount is not null or realized_savings is not null or coalesce(finance_validated, false))
  ) then
    raise exception 'execution cannot be reversed after realization evidence exists; use a correction';
  end if;

  if v_project_type = 'Sourcing' and v_requires_disposition then
    if p_disposition_action <> 'no_executed_savings' then
      raise exception 'reopen the completed project or choose no_executed_savings';
    end if;
    if length(btrim(p_note)) < 10 then
      raise exception 'completed projects without executed savings require a reason of at least 10 characters';
    end if;

    update public.sourcing_events
    set savings_disposition = 'no_executed_savings',
        savings_disposition_reason = btrim(p_note),
        savings_disposition_at = now(),
        savings_disposition_by = v_user,
        updated_by = v_user,
        updated_at = now()
    where id = v_event and organization_id = v_org;
  else
    if p_disposition_action <> 'clear' then
      raise exception 'disposition action must be clear for an open project';
    end if;

    update public.sourcing_events
    set savings_disposition = null,
        savings_disposition_reason = null,
        savings_disposition_at = null,
        savings_disposition_by = null,
        updated_by = v_user,
        updated_at = now()
    where id = v_event and organization_id = v_org;
  end if;

  delete from public.realization_periods
  where savings_calculation_id = p_calc_id and organization_id = v_org;

  update public.savings_calculations
  set execution_note = concat_ws(
        E'\n', nullif(v_existing_note, ''),
        '[' || to_char(now(), 'YYYY-MM-DD HH24:MI:SSOF') || '] Reversal: ' || btrim(p_note)
      ),
      updated_by = v_user,
      updated_at = now()
  where id = p_calc_id and organization_id = v_org;

  update public.savings_periods
  set executed_baseline_amount = null,
      executed_opening_amount = null,
      executed_final_amount = null,
      executed_cost_reduction_amount = null,
      executed_cost_avoidance_amount = null,
      executed_total_savings_amount = null,
      updated_by = v_user,
      updated_at = now()
  where savings_calculation_id = p_calc_id and organization_id = v_org;

  update public.savings_calculations
  set calculation_status = 'estimated',
      executed_at = null,
      executed_by = null,
      execution_note = null,
      legacy_execution_actor_missing = false,
      updated_by = v_user,
      updated_at = now()
  where id = p_calc_id and organization_id = v_org;
end
$$;


ALTER FUNCTION "public"."reverse_savings_execution"("p_calc_id" "uuid", "p_note" "text", "p_disposition_action" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."select_baseline"("p_baseline_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'public'
    AS $$
declare
  v_user uuid := auth.uid();
  v_org uuid;
  v_role text;
  v_event uuid;
begin
  if v_user is null then
    raise exception 'authentication required';
  end if;

  select organization_id, role into v_org, v_role
  from public.profiles
  where id = v_user;

  if v_org is null then
    raise exception 'workspace membership required';
  end if;
  if v_role not in ('admin', 'procurement_user') then
    raise exception 'administrator or procurement role required';
  end if;

  select event_id into v_event
  from public.baselines
  where id = p_baseline_id
    and organization_id = v_org;

  if v_event is null then
    raise exception 'baseline not found';
  end if;

  -- The parent lock serializes two callers selecting different baselines for
  -- the same project. Lock every tuple before applying the invariant.
  perform 1
  from public.sourcing_events
  where id = v_event and organization_id = v_org
  for update;

  perform 1
  from public.baselines
  where event_id = v_event and organization_id = v_org
  order by id
  for update;

  if not exists (
    select 1 from public.baselines
    where id = p_baseline_id
      and event_id = v_event
      and organization_id = v_org
  ) then
    raise exception 'baseline not found';
  end if;

  update public.baselines
  set is_selected = false, updated_by = v_user, updated_at = now()
  where event_id = v_event
    and organization_id = v_org
    and id <> p_baseline_id
    and is_selected;

  update public.baselines
  set is_selected = true, updated_by = v_user, updated_at = now()
  where id = p_baseline_id
    and event_id = v_event
    and organization_id = v_org
    and not is_selected;
end
$$;


ALTER FUNCTION "public"."select_baseline"("p_baseline_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_finance_validation"("p_realization_period_id" "uuid", "p_validated" boolean) RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'public'
    AS $$
declare
  v_user uuid := auth.uid();
  v_org uuid;
  v_role text;
begin
  if v_user is null then raise exception 'authentication required'; end if;
  if p_validated is null then raise exception 'validated is required'; end if;

  select organization_id, role into v_org, v_role
  from public.profiles where id = v_user;
  if v_org is null then raise exception 'workspace membership required'; end if;
  if v_role <> 'admin' then raise exception 'administrator role required'; end if;

  perform 1 from public.realization_periods
  where id = p_realization_period_id and organization_id = v_org
  for update;
  if not found then raise exception 'realization period not found'; end if;

  update public.realization_periods
  set finance_validated = p_validated,
      finance_validated_by = case when p_validated then v_user end,
      finance_validation_date = case when p_validated then now() end,
      updated_by = v_user,
      updated_at = now()
  where id = p_realization_period_id and organization_id = v_org;
end
$$;


ALTER FUNCTION "public"."set_finance_validation"("p_realization_period_id" "uuid", "p_validated" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_hard_reduction_override"("p_baseline_id" "uuid", "p_enabled" boolean, "p_reason" "text" DEFAULT NULL::"text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'public'
    AS $$
declare
  v_user uuid := auth.uid();
  v_org uuid;
  v_role text;
  v_reason text := nullif(btrim(p_reason), '');
begin
  if v_user is null then raise exception 'authentication required'; end if;
  if p_enabled is null then raise exception 'enabled is required'; end if;

  select organization_id, role into v_org, v_role
  from public.profiles where id = v_user;
  if v_org is null then raise exception 'workspace membership required'; end if;
  if v_role not in ('admin', 'procurement_user') then
    raise exception 'administrator or procurement role required';
  end if;
  if p_enabled and coalesce(length(v_reason), 0) < 10 then
    raise exception 'override reason must contain at least 10 characters';
  end if;

  perform 1 from public.baselines
  where id = p_baseline_id and organization_id = v_org
  for update;
  if not found then raise exception 'baseline not found'; end if;

  update public.baselines
  set hard_reduction_override = p_enabled,
      hard_reduction_override_reason = case when p_enabled then v_reason end,
      hard_reduction_override_by = case when p_enabled then v_user end,
      hard_reduction_override_at = case when p_enabled then now() end,
      updated_by = v_user,
      updated_at = now()
  where id = p_baseline_id and organization_id = v_org;
end
$$;


ALTER FUNCTION "public"."set_hard_reduction_override"("p_baseline_id" "uuid", "p_enabled" boolean, "p_reason" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_offer_role"("p_offer_id" "uuid", "p_role" "text" DEFAULT NULL::"text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'public'
    AS $$
declare
  v_user uuid := auth.uid();
  v_org uuid;
  v_role text;
  v_event uuid;
  v_final_supplier uuid;
begin
  if v_user is null then
    raise exception 'authentication required';
  end if;
  if p_role is not null and p_role not in ('opening', 'final') then
    raise exception 'offer role must be opening, final, or null';
  end if;

  select organization_id, role into v_org, v_role
  from public.profiles
  where id = v_user;

  if v_org is null then
    raise exception 'workspace membership required';
  end if;
  if v_role not in ('admin', 'procurement_user') then
    raise exception 'administrator or procurement role required';
  end if;

  select event_id into v_event
  from public.supplier_offers
  where id = p_offer_id
    and organization_id = v_org;

  if v_event is null then
    raise exception 'offer not found';
  end if;

  -- The event row is the shared mutex for role changes and the award pointer.
  perform 1
  from public.sourcing_events
  where id = v_event and organization_id = v_org
  for update;

  perform 1
  from public.supplier_offers
  where event_id = v_event and organization_id = v_org
  order by id
  for update;

  if not exists (
    select 1 from public.supplier_offers
    where id = p_offer_id
      and event_id = v_event
      and organization_id = v_org
  ) then
    raise exception 'offer not found';
  end if;

  if p_role is not null then
    update public.supplier_offers
    set offer_role = null, updated_by = v_user, updated_at = now()
    where event_id = v_event
      and organization_id = v_org
      and id <> p_offer_id
      and offer_role = p_role;
  end if;

  update public.supplier_offers
  set offer_role = p_role, updated_by = v_user, updated_at = now()
  where id = p_offer_id
    and event_id = v_event
    and organization_id = v_org
    and offer_role is distinct from p_role;

  -- Resolve the winner from the locked database rows, never from browser state.
  select supplier_id into v_final_supplier
  from public.supplier_offers
  where event_id = v_event
    and organization_id = v_org
    and offer_role = 'final';

  if exists (
    select 1 from public.supplier_offers
    where event_id = v_event
      and organization_id = v_org
      and offer_role = 'final'
      and supplier_id is null
  ) then
    raise exception 'a final offer must name a supplier';
  end if;

  update public.sourcing_events
  set awarded_supplier_id = v_final_supplier,
      updated_by = v_user,
      updated_at = now()
  where id = v_event
    and organization_id = v_org
    and awarded_supplier_id is distinct from v_final_supplier;
end
$$;


ALTER FUNCTION "public"."set_offer_role"("p_offer_id" "uuid", "p_role" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_single_primary_supplier_contact"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'pg_catalog', 'public'
    AS $$
begin
  if new.is_primary then
    update public.supplier_contacts
    set
      is_primary = false,
      updated_at = now(),
      updated_by = auth.uid()
    where supplier_id = new.supplier_id
      and organization_id = new.organization_id
      and id is distinct from new.id
      and is_primary;
  end if;
  return new;
end
$$;


ALTER FUNCTION "public"."set_single_primary_supplier_contact"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_supplier_normalized_name"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'pg_catalog', 'public'
    AS $$
begin
  new.supplier_name := btrim(new.supplier_name);
  new.supplier_normalized_name := btrim(
    regexp_replace(lower(new.supplier_name), '[^a-z0-9]+', ' ', 'g')
  );

  if new.supplier_normalized_name = '' then
    raise exception 'Supplier name must contain at least one letter or number'
      using errcode = '23514';
  end if;

  return new;
end
$$;


ALTER FUNCTION "public"."set_supplier_normalized_name"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."stamp_money_record_actor"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'pg_catalog', 'public'
    AS $$
declare
  v_user uuid := auth.uid();
begin
  -- Preserve import/service behavior when no end-user JWT is present. Data API
  -- writes always carry auth.uid() and can never choose their own actor.
  if v_user is null then
    return new;
  end if;

  if tg_op = 'INSERT' then
    new.created_by := v_user;
  else
    new.created_by := old.created_by;
  end if;
  new.updated_by := v_user;
  return new;
end
$$;


ALTER FUNCTION "public"."stamp_money_record_actor"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."stamp_supplier_certification_actor"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'pg_catalog', 'public'
    AS $$
begin
  if auth.uid() is not null then
    if tg_op = 'INSERT' then new.created_by := auth.uid(); else new.created_by := old.created_by; end if;
    new.updated_by := auth.uid();
  end if;
  return new;
end
$$;


ALTER FUNCTION "public"."stamp_supplier_certification_actor"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."stamp_supplier_contact_actor"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'pg_catalog', 'public'
    AS $$
begin
  if auth.uid() is not null then
    if tg_op = 'INSERT' then
      new.created_by := auth.uid();
    else
      new.created_by := old.created_by;
    end if;
    new.updated_by := auth.uid();
  end if;
  return new;
end
$$;


ALTER FUNCTION "public"."stamp_supplier_contact_actor"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."stamp_supplier_note_actor"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'pg_catalog', 'public'
    AS $$
begin
  if auth.uid() is not null then
    new.created_by := auth.uid();
  end if;
  return new;
end
$$;


ALTER FUNCTION "public"."stamp_supplier_note_actor"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."stamp_supplier_performance_review_actor"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'pg_catalog', 'public'
    AS $$
begin
  if auth.uid() is not null then
    if tg_op = 'INSERT' then new.created_by := auth.uid(); else new.created_by := old.created_by; end if;
    new.updated_by := auth.uid();
  end if;
  return new;
end
$$;


ALTER FUNCTION "public"."stamp_supplier_performance_review_actor"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."stamp_supplier_risk_actor"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'pg_catalog', 'public'
    AS $$
begin
  if auth.uid() is not null then
    if tg_op = 'INSERT' then new.created_by := auth.uid(); else new.created_by := old.created_by; end if;
    new.updated_by := auth.uid();
  end if;
  return new;
end
$$;


ALTER FUNCTION "public"."stamp_supplier_risk_actor"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."sync_realization_periods"("p_event_id" "uuid") RETURNS integer
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'public'
    AS $$
declare
  v_user uuid := auth.uid();
  v_org uuid;
  v_role text;
  v_inserted integer := 0;
begin
  if v_user is null then raise exception 'authentication required'; end if;

  select organization_id, role into v_org, v_role
  from public.profiles where id = v_user;
  if v_org is null then raise exception 'workspace membership required'; end if;
  if v_role not in ('admin', 'procurement_user') then
    raise exception 'administrator or procurement role required';
  end if;

  perform 1
  from public.sourcing_events event
  where event.id = p_event_id
    and event.organization_id = v_org
    and event.project_type = 'Sourcing'
  for update;
  if not found then raise exception 'sourcing project not found'; end if;

  if not coalesce((
    select settings.savings_realization_enabled
    from public.organization_settings settings
    where settings.organization_id = v_org
  ), false) then
    raise exception 'Savings Realization is disabled for this workspace';
  end if;

  insert into public.realization_periods (
    organization_id, event_id, savings_calculation_id, savings_period_id,
    period_name, period_start_date, period_end_date,
    baseline_amount, actual_amount, projected_savings, realized_savings,
    leakage_amount, realization_status, created_by, updated_by
  )
  select
    period.organization_id,
    period.event_id,
    period.savings_calculation_id,
    period.id,
    to_char(make_date(period.period_year, period.period_month, 1), 'Mon YYYY'),
    make_date(period.period_year, period.period_month, 1),
    (
      make_date(period.period_year, period.period_month, 1)
      + make_interval(months => greatest(1, round(period.period_months)::integer))
      - interval '1 day'
    )::date,
    period.executed_baseline_amount,
    null,
    period.executed_total_savings_amount,
    null,
    null,
    'Pending',
    v_user,
    v_user
  from public.savings_periods period
  join public.savings_calculations calculation
    on calculation.id = period.savings_calculation_id
   and calculation.organization_id = period.organization_id
   and calculation.event_id = period.event_id
  where period.organization_id = v_org
    and period.event_id = p_event_id
    and calculation.calculation_status = 'executed'
    and period.executed_total_savings_amount is not null
    and period.executed_final_amount is not null
    and period.executed_cost_avoidance_amount is not null
    and not exists (
      select 1 from public.realization_periods existing
      where existing.savings_period_id = period.id
    )
  order by period.period_number
  on conflict do nothing;

  get diagnostics v_inserted = row_count;
  return v_inserted;
end
$$;


ALTER FUNCTION "public"."sync_realization_periods"("p_event_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_updated_at"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'pg_catalog', 'public'
    AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."update_updated_at"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_workspace_settings"("p_organization_name" "text", "p_full_name" "text", "p_currency_code" "text", "p_locale" "text", "p_timezone" "text", "p_fiscal_year_start_month" integer, "p_date_format" "text", "p_default_recognition_method" "text", "p_require_baseline" boolean, "p_hard_reduction_approval_threshold" numeric) RETURNS "void"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'pg_catalog', 'public'
    AS $$
begin
  perform public.update_workspace_settings(
    p_organization_name,
    p_full_name,
    p_currency_code,
    p_locale,
    p_timezone,
    p_fiscal_year_start_month,
    p_date_format,
    p_default_recognition_method,
    p_require_baseline,
    p_hard_reduction_approval_threshold,
    coalesce(
      (
        select settings.support_projects_enabled
        from public.organization_settings as settings
        where settings.organization_id = public.current_org_id()
      ),
      true
    )
  );
end
$$;


ALTER FUNCTION "public"."update_workspace_settings"("p_organization_name" "text", "p_full_name" "text", "p_currency_code" "text", "p_locale" "text", "p_timezone" "text", "p_fiscal_year_start_month" integer, "p_date_format" "text", "p_default_recognition_method" "text", "p_require_baseline" boolean, "p_hard_reduction_approval_threshold" numeric) OWNER TO "postgres";


COMMENT ON FUNCTION "public"."update_workspace_settings"("p_organization_name" "text", "p_full_name" "text", "p_currency_code" "text", "p_locale" "text", "p_timezone" "text", "p_fiscal_year_start_month" integer, "p_date_format" "text", "p_default_recognition_method" "text", "p_require_baseline" boolean, "p_hard_reduction_approval_threshold" numeric) IS 'Compatibility overload for deployed clients that predate the Support project setting.';



CREATE OR REPLACE FUNCTION "public"."update_workspace_settings"("p_organization_name" "text", "p_full_name" "text", "p_currency_code" "text", "p_locale" "text", "p_timezone" "text", "p_fiscal_year_start_month" integer, "p_date_format" "text", "p_default_recognition_method" "text", "p_require_baseline" boolean, "p_hard_reduction_approval_threshold" numeric, "p_support_projects_enabled" boolean) RETURNS "void"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'pg_catalog', 'public'
    AS $$
declare
  v_user uuid := auth.uid();
  v_org uuid := public.current_org_id();
  v_role text;
begin
  if v_user is null or v_org is null then
    raise exception 'authentication required';
  end if;

  select role into v_role
  from public.profiles
  where id = v_user and organization_id = v_org;

  if v_role is distinct from 'admin' then
    raise exception 'administrator role required';
  end if;

  update public.organizations
  set name = p_organization_name
  where id = v_org;

  update public.profiles
  set full_name = p_full_name
  where id = v_user and organization_id = v_org;

  insert into public.organization_settings (
    organization_id,
    currency_code,
    locale,
    timezone,
    fiscal_year_start_month,
    date_format,
    default_recognition_method,
    require_baseline_for_hard_reduction,
    hard_reduction_approval_threshold,
    support_projects_enabled,
    updated_by
  ) values (
    v_org,
    p_currency_code,
    p_locale,
    p_timezone,
    p_fiscal_year_start_month,
    p_date_format,
    p_default_recognition_method,
    p_require_baseline,
    p_hard_reduction_approval_threshold,
    p_support_projects_enabled,
    v_user
  )
  on conflict (organization_id) do update set
    currency_code = excluded.currency_code,
    locale = excluded.locale,
    timezone = excluded.timezone,
    fiscal_year_start_month = excluded.fiscal_year_start_month,
    date_format = excluded.date_format,
    default_recognition_method = excluded.default_recognition_method,
    require_baseline_for_hard_reduction = excluded.require_baseline_for_hard_reduction,
    hard_reduction_approval_threshold = excluded.hard_reduction_approval_threshold,
    support_projects_enabled = excluded.support_projects_enabled,
    updated_by = excluded.updated_by;
end
$$;


ALTER FUNCTION "public"."update_workspace_settings"("p_organization_name" "text", "p_full_name" "text", "p_currency_code" "text", "p_locale" "text", "p_timezone" "text", "p_fiscal_year_start_month" integer, "p_date_format" "text", "p_default_recognition_method" "text", "p_require_baseline" boolean, "p_hard_reduction_approval_threshold" numeric, "p_support_projects_enabled" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_workspace_settings_v2"("p_organization_name" "text", "p_full_name" "text", "p_currency_code" "text", "p_locale" "text", "p_timezone" "text", "p_fiscal_year_start_month" integer, "p_date_format" "text", "p_default_recognition_method" "text", "p_require_baseline" boolean, "p_hard_reduction_approval_threshold" numeric, "p_support_projects_enabled" boolean, "p_project_descriptions_enabled" boolean) RETURNS "void"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'pg_catalog', 'public'
    AS $$
declare
  v_user uuid := auth.uid();
  v_org uuid := public.current_org_id();
  v_role text;
begin
  if v_user is null or v_org is null then
    raise exception 'authentication required';
  end if;

  select role into v_role
  from public.profiles
  where id = v_user and organization_id = v_org;

  if v_role is distinct from 'admin' then
    raise exception 'administrator role required';
  end if;

  update public.organizations
  set name = p_organization_name
  where id = v_org;

  update public.profiles
  set full_name = p_full_name
  where id = v_user and organization_id = v_org;

  insert into public.organization_settings (
    organization_id,
    currency_code,
    locale,
    timezone,
    fiscal_year_start_month,
    date_format,
    default_recognition_method,
    require_baseline_for_hard_reduction,
    hard_reduction_approval_threshold,
    support_projects_enabled,
    project_descriptions_enabled,
    updated_by
  ) values (
    v_org,
    p_currency_code,
    p_locale,
    p_timezone,
    p_fiscal_year_start_month,
    p_date_format,
    p_default_recognition_method,
    p_require_baseline,
    p_hard_reduction_approval_threshold,
    p_support_projects_enabled,
    p_project_descriptions_enabled,
    v_user
  )
  on conflict (organization_id) do update set
    currency_code = excluded.currency_code,
    locale = excluded.locale,
    timezone = excluded.timezone,
    fiscal_year_start_month = excluded.fiscal_year_start_month,
    date_format = excluded.date_format,
    default_recognition_method = excluded.default_recognition_method,
    require_baseline_for_hard_reduction = excluded.require_baseline_for_hard_reduction,
    hard_reduction_approval_threshold = excluded.hard_reduction_approval_threshold,
    support_projects_enabled = excluded.support_projects_enabled,
    project_descriptions_enabled = excluded.project_descriptions_enabled,
    updated_by = excluded.updated_by;
end
$$;


ALTER FUNCTION "public"."update_workspace_settings_v2"("p_organization_name" "text", "p_full_name" "text", "p_currency_code" "text", "p_locale" "text", "p_timezone" "text", "p_fiscal_year_start_month" integer, "p_date_format" "text", "p_default_recognition_method" "text", "p_require_baseline" boolean, "p_hard_reduction_approval_threshold" numeric, "p_support_projects_enabled" boolean, "p_project_descriptions_enabled" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_workspace_settings_v3"("p_organization_name" "text", "p_full_name" "text", "p_currency_code" "text", "p_locale" "text", "p_timezone" "text", "p_fiscal_year_start_month" integer, "p_date_format" "text", "p_default_recognition_method" "text", "p_require_baseline" boolean, "p_hard_reduction_approval_threshold" numeric, "p_support_projects_enabled" boolean, "p_project_descriptions_enabled" boolean, "p_project_owners_enabled" boolean) RETURNS "void"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'pg_catalog', 'public'
    AS $$
declare
  v_user uuid := auth.uid();
  v_org uuid := public.current_org_id();
  v_role text;
begin
  if v_user is null or v_org is null then
    raise exception 'authentication required';
  end if;

  select role into v_role
  from public.profiles
  where id = v_user and organization_id = v_org;

  if v_role is distinct from 'admin' then
    raise exception 'administrator role required';
  end if;

  update public.organizations
  set name = p_organization_name
  where id = v_org;

  update public.profiles
  set full_name = p_full_name
  where id = v_user and organization_id = v_org;

  insert into public.organization_settings (
    organization_id,
    currency_code,
    locale,
    timezone,
    fiscal_year_start_month,
    date_format,
    default_recognition_method,
    require_baseline_for_hard_reduction,
    hard_reduction_approval_threshold,
    support_projects_enabled,
    project_descriptions_enabled,
    project_owners_enabled,
    updated_by
  ) values (
    v_org,
    p_currency_code,
    p_locale,
    p_timezone,
    p_fiscal_year_start_month,
    p_date_format,
    p_default_recognition_method,
    p_require_baseline,
    p_hard_reduction_approval_threshold,
    p_support_projects_enabled,
    p_project_descriptions_enabled,
    p_project_owners_enabled,
    v_user
  )
  on conflict (organization_id) do update set
    currency_code = excluded.currency_code,
    locale = excluded.locale,
    timezone = excluded.timezone,
    fiscal_year_start_month = excluded.fiscal_year_start_month,
    date_format = excluded.date_format,
    default_recognition_method = excluded.default_recognition_method,
    require_baseline_for_hard_reduction = excluded.require_baseline_for_hard_reduction,
    hard_reduction_approval_threshold = excluded.hard_reduction_approval_threshold,
    support_projects_enabled = excluded.support_projects_enabled,
    project_descriptions_enabled = excluded.project_descriptions_enabled,
    project_owners_enabled = excluded.project_owners_enabled,
    updated_by = excluded.updated_by;
end
$$;


ALTER FUNCTION "public"."update_workspace_settings_v3"("p_organization_name" "text", "p_full_name" "text", "p_currency_code" "text", "p_locale" "text", "p_timezone" "text", "p_fiscal_year_start_month" integer, "p_date_format" "text", "p_default_recognition_method" "text", "p_require_baseline" boolean, "p_hard_reduction_approval_threshold" numeric, "p_support_projects_enabled" boolean, "p_project_descriptions_enabled" boolean, "p_project_owners_enabled" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_workspace_settings_v4"("p_organization_name" "text", "p_full_name" "text", "p_currency_code" "text", "p_locale" "text", "p_timezone" "text", "p_fiscal_year_start_month" integer, "p_date_format" "text", "p_default_recognition_method" "text", "p_require_baseline" boolean, "p_hard_reduction_approval_threshold" numeric, "p_support_projects_enabled" boolean, "p_project_descriptions_enabled" boolean, "p_project_owners_enabled" boolean, "p_project_cost_centers_enabled" boolean) RETURNS "void"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'pg_catalog', 'public'
    AS $$
declare
  v_user uuid := auth.uid();
  v_org uuid := public.current_org_id();
  v_role text;
begin
  if v_user is null or v_org is null then
    raise exception 'authentication required';
  end if;

  select role into v_role
  from public.profiles
  where id = v_user and organization_id = v_org;

  if v_role is distinct from 'admin' then
    raise exception 'administrator role required';
  end if;

  update public.organizations
  set name = p_organization_name
  where id = v_org;

  update public.profiles
  set full_name = p_full_name
  where id = v_user and organization_id = v_org;

  insert into public.organization_settings (
    organization_id,
    currency_code,
    locale,
    timezone,
    fiscal_year_start_month,
    date_format,
    default_recognition_method,
    require_baseline_for_hard_reduction,
    hard_reduction_approval_threshold,
    support_projects_enabled,
    project_descriptions_enabled,
    project_owners_enabled,
    project_cost_centers_enabled,
    updated_by
  ) values (
    v_org,
    p_currency_code,
    p_locale,
    p_timezone,
    p_fiscal_year_start_month,
    p_date_format,
    p_default_recognition_method,
    p_require_baseline,
    p_hard_reduction_approval_threshold,
    p_support_projects_enabled,
    p_project_descriptions_enabled,
    p_project_owners_enabled,
    p_project_cost_centers_enabled,
    v_user
  )
  on conflict (organization_id) do update set
    currency_code = excluded.currency_code,
    locale = excluded.locale,
    timezone = excluded.timezone,
    fiscal_year_start_month = excluded.fiscal_year_start_month,
    date_format = excluded.date_format,
    default_recognition_method = excluded.default_recognition_method,
    require_baseline_for_hard_reduction = excluded.require_baseline_for_hard_reduction,
    hard_reduction_approval_threshold = excluded.hard_reduction_approval_threshold,
    support_projects_enabled = excluded.support_projects_enabled,
    project_descriptions_enabled = excluded.project_descriptions_enabled,
    project_owners_enabled = excluded.project_owners_enabled,
    project_cost_centers_enabled = excluded.project_cost_centers_enabled,
    updated_by = excluded.updated_by;
end
$$;


ALTER FUNCTION "public"."update_workspace_settings_v4"("p_organization_name" "text", "p_full_name" "text", "p_currency_code" "text", "p_locale" "text", "p_timezone" "text", "p_fiscal_year_start_month" integer, "p_date_format" "text", "p_default_recognition_method" "text", "p_require_baseline" boolean, "p_hard_reduction_approval_threshold" numeric, "p_support_projects_enabled" boolean, "p_project_descriptions_enabled" boolean, "p_project_owners_enabled" boolean, "p_project_cost_centers_enabled" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_workspace_settings_v5"("p_organization_name" "text", "p_full_name" "text", "p_currency_code" "text", "p_locale" "text", "p_timezone" "text", "p_fiscal_year_start_month" integer, "p_date_format" "text", "p_default_recognition_method" "text", "p_require_baseline" boolean, "p_hard_reduction_approval_threshold" numeric, "p_support_projects_enabled" boolean, "p_project_descriptions_enabled" boolean, "p_project_owners_enabled" boolean, "p_project_cost_centers_enabled" boolean, "p_project_categories_enabled" boolean) RETURNS "void"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'pg_catalog', 'public'
    AS $$
declare
  v_user uuid := auth.uid();
  v_org uuid := public.current_org_id();
  v_role text;
begin
  if v_user is null or v_org is null then
    raise exception 'authentication required';
  end if;

  select role into v_role
  from public.profiles
  where id = v_user and organization_id = v_org;

  if v_role is distinct from 'admin' then
    raise exception 'administrator role required';
  end if;

  update public.organizations
  set name = p_organization_name
  where id = v_org;

  update public.profiles
  set full_name = p_full_name
  where id = v_user and organization_id = v_org;

  insert into public.organization_settings (
    organization_id,
    currency_code,
    locale,
    timezone,
    fiscal_year_start_month,
    date_format,
    default_recognition_method,
    require_baseline_for_hard_reduction,
    hard_reduction_approval_threshold,
    support_projects_enabled,
    project_descriptions_enabled,
    project_owners_enabled,
    project_cost_centers_enabled,
    project_categories_enabled,
    updated_by
  ) values (
    v_org,
    p_currency_code,
    p_locale,
    p_timezone,
    p_fiscal_year_start_month,
    p_date_format,
    p_default_recognition_method,
    p_require_baseline,
    p_hard_reduction_approval_threshold,
    p_support_projects_enabled,
    p_project_descriptions_enabled,
    p_project_owners_enabled,
    p_project_cost_centers_enabled,
    p_project_categories_enabled,
    v_user
  )
  on conflict (organization_id) do update set
    currency_code = excluded.currency_code,
    locale = excluded.locale,
    timezone = excluded.timezone,
    fiscal_year_start_month = excluded.fiscal_year_start_month,
    date_format = excluded.date_format,
    default_recognition_method = excluded.default_recognition_method,
    require_baseline_for_hard_reduction = excluded.require_baseline_for_hard_reduction,
    hard_reduction_approval_threshold = excluded.hard_reduction_approval_threshold,
    support_projects_enabled = excluded.support_projects_enabled,
    project_descriptions_enabled = excluded.project_descriptions_enabled,
    project_owners_enabled = excluded.project_owners_enabled,
    project_cost_centers_enabled = excluded.project_cost_centers_enabled,
    project_categories_enabled = excluded.project_categories_enabled,
    updated_by = excluded.updated_by;
end
$$;


ALTER FUNCTION "public"."update_workspace_settings_v5"("p_organization_name" "text", "p_full_name" "text", "p_currency_code" "text", "p_locale" "text", "p_timezone" "text", "p_fiscal_year_start_month" integer, "p_date_format" "text", "p_default_recognition_method" "text", "p_require_baseline" boolean, "p_hard_reduction_approval_threshold" numeric, "p_support_projects_enabled" boolean, "p_project_descriptions_enabled" boolean, "p_project_owners_enabled" boolean, "p_project_cost_centers_enabled" boolean, "p_project_categories_enabled" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_workspace_settings_v6"("p_organization_name" "text", "p_full_name" "text", "p_currency_code" "text", "p_locale" "text", "p_timezone" "text", "p_fiscal_year_start_month" integer, "p_date_format" "text", "p_default_recognition_method" "text", "p_require_baseline" boolean, "p_hard_reduction_approval_threshold" numeric, "p_support_projects_enabled" boolean, "p_project_descriptions_enabled" boolean, "p_project_owners_enabled" boolean, "p_project_cost_centers_enabled" boolean, "p_project_categories_enabled" boolean, "p_project_business_units_enabled" boolean) RETURNS "void"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'pg_catalog', 'public'
    AS $$
declare
  v_user uuid := auth.uid();
  v_org uuid := public.current_org_id();
  v_role text;
begin
  if v_user is null or v_org is null then
    raise exception 'authentication required';
  end if;

  select role into v_role
  from public.profiles
  where id = v_user and organization_id = v_org;

  if v_role is distinct from 'admin' then
    raise exception 'administrator role required';
  end if;

  update public.organizations
  set name = p_organization_name
  where id = v_org;

  update public.profiles
  set full_name = p_full_name
  where id = v_user and organization_id = v_org;

  insert into public.organization_settings (
    organization_id,
    currency_code,
    locale,
    timezone,
    fiscal_year_start_month,
    date_format,
    default_recognition_method,
    require_baseline_for_hard_reduction,
    hard_reduction_approval_threshold,
    support_projects_enabled,
    project_descriptions_enabled,
    project_owners_enabled,
    project_cost_centers_enabled,
    project_categories_enabled,
    project_business_units_enabled,
    updated_by
  ) values (
    v_org,
    p_currency_code,
    p_locale,
    p_timezone,
    p_fiscal_year_start_month,
    p_date_format,
    p_default_recognition_method,
    p_require_baseline,
    p_hard_reduction_approval_threshold,
    p_support_projects_enabled,
    p_project_descriptions_enabled,
    p_project_owners_enabled,
    p_project_cost_centers_enabled,
    p_project_categories_enabled,
    p_project_business_units_enabled,
    v_user
  )
  on conflict (organization_id) do update set
    currency_code = excluded.currency_code,
    locale = excluded.locale,
    timezone = excluded.timezone,
    fiscal_year_start_month = excluded.fiscal_year_start_month,
    date_format = excluded.date_format,
    default_recognition_method = excluded.default_recognition_method,
    require_baseline_for_hard_reduction = excluded.require_baseline_for_hard_reduction,
    hard_reduction_approval_threshold = excluded.hard_reduction_approval_threshold,
    support_projects_enabled = excluded.support_projects_enabled,
    project_descriptions_enabled = excluded.project_descriptions_enabled,
    project_owners_enabled = excluded.project_owners_enabled,
    project_cost_centers_enabled = excluded.project_cost_centers_enabled,
    project_categories_enabled = excluded.project_categories_enabled,
    project_business_units_enabled = excluded.project_business_units_enabled,
    updated_by = excluded.updated_by;
end
$$;


ALTER FUNCTION "public"."update_workspace_settings_v6"("p_organization_name" "text", "p_full_name" "text", "p_currency_code" "text", "p_locale" "text", "p_timezone" "text", "p_fiscal_year_start_month" integer, "p_date_format" "text", "p_default_recognition_method" "text", "p_require_baseline" boolean, "p_hard_reduction_approval_threshold" numeric, "p_support_projects_enabled" boolean, "p_project_descriptions_enabled" boolean, "p_project_owners_enabled" boolean, "p_project_cost_centers_enabled" boolean, "p_project_categories_enabled" boolean, "p_project_business_units_enabled" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_workspace_settings_v7"("p_organization_name" "text", "p_full_name" "text", "p_currency_code" "text", "p_locale" "text", "p_timezone" "text", "p_fiscal_year_start_month" integer, "p_date_format" "text", "p_default_recognition_method" "text", "p_require_baseline" boolean, "p_hard_reduction_approval_threshold" numeric, "p_support_projects_enabled" boolean, "p_project_descriptions_enabled" boolean, "p_project_owners_enabled" boolean, "p_project_cost_centers_enabled" boolean, "p_project_categories_enabled" boolean, "p_project_business_units_enabled" boolean, "p_project_updates_enabled" boolean) RETURNS "void"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'pg_catalog', 'public'
    AS $$
declare
  v_user uuid := auth.uid();
  v_org uuid := public.current_org_id();
  v_role text;
begin
  if v_user is null or v_org is null then
    raise exception 'authentication required';
  end if;

  select role into v_role
  from public.profiles
  where id = v_user and organization_id = v_org;

  if v_role is distinct from 'admin' then
    raise exception 'administrator role required';
  end if;

  update public.organizations
  set name = p_organization_name
  where id = v_org;

  update public.profiles
  set full_name = p_full_name
  where id = v_user and organization_id = v_org;

  insert into public.organization_settings (
    organization_id,
    currency_code,
    locale,
    timezone,
    fiscal_year_start_month,
    date_format,
    default_recognition_method,
    require_baseline_for_hard_reduction,
    hard_reduction_approval_threshold,
    support_projects_enabled,
    project_descriptions_enabled,
    project_owners_enabled,
    project_cost_centers_enabled,
    project_categories_enabled,
    project_business_units_enabled,
    project_updates_enabled,
    updated_by
  ) values (
    v_org,
    p_currency_code,
    p_locale,
    p_timezone,
    p_fiscal_year_start_month,
    p_date_format,
    p_default_recognition_method,
    p_require_baseline,
    p_hard_reduction_approval_threshold,
    p_support_projects_enabled,
    p_project_descriptions_enabled,
    p_project_owners_enabled,
    p_project_cost_centers_enabled,
    p_project_categories_enabled,
    p_project_business_units_enabled,
    p_project_updates_enabled,
    v_user
  )
  on conflict (organization_id) do update set
    currency_code = excluded.currency_code,
    locale = excluded.locale,
    timezone = excluded.timezone,
    fiscal_year_start_month = excluded.fiscal_year_start_month,
    date_format = excluded.date_format,
    default_recognition_method = excluded.default_recognition_method,
    require_baseline_for_hard_reduction = excluded.require_baseline_for_hard_reduction,
    hard_reduction_approval_threshold = excluded.hard_reduction_approval_threshold,
    support_projects_enabled = excluded.support_projects_enabled,
    project_descriptions_enabled = excluded.project_descriptions_enabled,
    project_owners_enabled = excluded.project_owners_enabled,
    project_cost_centers_enabled = excluded.project_cost_centers_enabled,
    project_categories_enabled = excluded.project_categories_enabled,
    project_business_units_enabled = excluded.project_business_units_enabled,
    project_updates_enabled = excluded.project_updates_enabled,
    updated_by = excluded.updated_by;
end
$$;


ALTER FUNCTION "public"."update_workspace_settings_v7"("p_organization_name" "text", "p_full_name" "text", "p_currency_code" "text", "p_locale" "text", "p_timezone" "text", "p_fiscal_year_start_month" integer, "p_date_format" "text", "p_default_recognition_method" "text", "p_require_baseline" boolean, "p_hard_reduction_approval_threshold" numeric, "p_support_projects_enabled" boolean, "p_project_descriptions_enabled" boolean, "p_project_owners_enabled" boolean, "p_project_cost_centers_enabled" boolean, "p_project_categories_enabled" boolean, "p_project_business_units_enabled" boolean, "p_project_updates_enabled" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_workspace_settings_v8"("p_organization_name" "text", "p_full_name" "text", "p_currency_code" "text", "p_locale" "text", "p_timezone" "text", "p_fiscal_year_start_month" integer, "p_date_format" "text", "p_default_recognition_method" "text", "p_require_baseline" boolean, "p_hard_reduction_approval_threshold" numeric, "p_support_projects_enabled" boolean, "p_project_descriptions_enabled" boolean, "p_project_owners_enabled" boolean, "p_project_cost_centers_enabled" boolean, "p_project_categories_enabled" boolean, "p_project_business_units_enabled" boolean, "p_project_updates_enabled" boolean, "p_project_incumbent_suppliers_enabled" boolean) RETURNS "void"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'pg_catalog', 'public'
    AS $$
declare
  v_user uuid := auth.uid();
  v_org uuid := public.current_org_id();
  v_role text;
begin
  if v_user is null or v_org is null then
    raise exception 'authentication required';
  end if;

  select role into v_role
  from public.profiles
  where id = v_user and organization_id = v_org;

  if v_role is distinct from 'admin' then
    raise exception 'administrator role required';
  end if;

  update public.organizations
  set name = p_organization_name
  where id = v_org;

  update public.profiles
  set full_name = p_full_name
  where id = v_user and organization_id = v_org;

  insert into public.organization_settings (
    organization_id,
    currency_code,
    locale,
    timezone,
    fiscal_year_start_month,
    date_format,
    default_recognition_method,
    require_baseline_for_hard_reduction,
    hard_reduction_approval_threshold,
    support_projects_enabled,
    project_descriptions_enabled,
    project_owners_enabled,
    project_cost_centers_enabled,
    project_categories_enabled,
    project_business_units_enabled,
    project_updates_enabled,
    project_incumbent_suppliers_enabled,
    updated_by
  ) values (
    v_org,
    p_currency_code,
    p_locale,
    p_timezone,
    p_fiscal_year_start_month,
    p_date_format,
    p_default_recognition_method,
    p_require_baseline,
    p_hard_reduction_approval_threshold,
    p_support_projects_enabled,
    p_project_descriptions_enabled,
    p_project_owners_enabled,
    p_project_cost_centers_enabled,
    p_project_categories_enabled,
    p_project_business_units_enabled,
    p_project_updates_enabled,
    p_project_incumbent_suppliers_enabled,
    v_user
  )
  on conflict (organization_id) do update set
    currency_code = excluded.currency_code,
    locale = excluded.locale,
    timezone = excluded.timezone,
    fiscal_year_start_month = excluded.fiscal_year_start_month,
    date_format = excluded.date_format,
    default_recognition_method = excluded.default_recognition_method,
    require_baseline_for_hard_reduction = excluded.require_baseline_for_hard_reduction,
    hard_reduction_approval_threshold = excluded.hard_reduction_approval_threshold,
    support_projects_enabled = excluded.support_projects_enabled,
    project_descriptions_enabled = excluded.project_descriptions_enabled,
    project_owners_enabled = excluded.project_owners_enabled,
    project_cost_centers_enabled = excluded.project_cost_centers_enabled,
    project_categories_enabled = excluded.project_categories_enabled,
    project_business_units_enabled = excluded.project_business_units_enabled,
    project_updates_enabled = excluded.project_updates_enabled,
    project_incumbent_suppliers_enabled = excluded.project_incumbent_suppliers_enabled,
    updated_by = excluded.updated_by;
end
$$;


ALTER FUNCTION "public"."update_workspace_settings_v8"("p_organization_name" "text", "p_full_name" "text", "p_currency_code" "text", "p_locale" "text", "p_timezone" "text", "p_fiscal_year_start_month" integer, "p_date_format" "text", "p_default_recognition_method" "text", "p_require_baseline" boolean, "p_hard_reduction_approval_threshold" numeric, "p_support_projects_enabled" boolean, "p_project_descriptions_enabled" boolean, "p_project_owners_enabled" boolean, "p_project_cost_centers_enabled" boolean, "p_project_categories_enabled" boolean, "p_project_business_units_enabled" boolean, "p_project_updates_enabled" boolean, "p_project_incumbent_suppliers_enabled" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_workspace_settings_v9"("p_organization_name" "text", "p_full_name" "text", "p_currency_code" "text", "p_locale" "text", "p_timezone" "text", "p_fiscal_year_start_month" integer, "p_date_format" "text", "p_default_recognition_method" "text", "p_require_baseline" boolean, "p_hard_reduction_approval_threshold" numeric, "p_support_projects_enabled" boolean, "p_project_descriptions_enabled" boolean, "p_project_owners_enabled" boolean, "p_project_cost_centers_enabled" boolean, "p_project_categories_enabled" boolean, "p_project_business_units_enabled" boolean, "p_project_updates_enabled" boolean, "p_project_incumbent_suppliers_enabled" boolean, "p_savings_realization_enabled" boolean) RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'public'
    AS $$
declare
  v_user uuid := auth.uid();
  v_org uuid := public.current_org_id();
  v_role text;
begin
  if v_user is null or v_org is null then raise exception 'authentication required'; end if;
  select role into v_role from public.profiles where id = v_user and organization_id = v_org;
  if v_role is distinct from 'admin' then raise exception 'administrator role required'; end if;

  update public.organizations set name = p_organization_name where id = v_org;
  update public.profiles set full_name = p_full_name where id = v_user and organization_id = v_org;

  insert into public.organization_settings (
    organization_id, currency_code, locale, timezone, fiscal_year_start_month,
    date_format, default_recognition_method, require_baseline_for_hard_reduction,
    hard_reduction_approval_threshold, support_projects_enabled,
    project_descriptions_enabled, project_owners_enabled,
    project_cost_centers_enabled, project_categories_enabled,
    project_business_units_enabled, project_updates_enabled,
    project_incumbent_suppliers_enabled, savings_realization_enabled, updated_by
  ) values (
    v_org, p_currency_code, p_locale, p_timezone, p_fiscal_year_start_month,
    p_date_format, p_default_recognition_method, p_require_baseline,
    p_hard_reduction_approval_threshold, p_support_projects_enabled,
    p_project_descriptions_enabled, p_project_owners_enabled,
    p_project_cost_centers_enabled, p_project_categories_enabled,
    p_project_business_units_enabled, p_project_updates_enabled,
    p_project_incumbent_suppliers_enabled, p_savings_realization_enabled, v_user
  )
  on conflict (organization_id) do update set
    currency_code = excluded.currency_code,
    locale = excluded.locale,
    timezone = excluded.timezone,
    fiscal_year_start_month = excluded.fiscal_year_start_month,
    date_format = excluded.date_format,
    default_recognition_method = excluded.default_recognition_method,
    require_baseline_for_hard_reduction = excluded.require_baseline_for_hard_reduction,
    hard_reduction_approval_threshold = excluded.hard_reduction_approval_threshold,
    support_projects_enabled = excluded.support_projects_enabled,
    project_descriptions_enabled = excluded.project_descriptions_enabled,
    project_owners_enabled = excluded.project_owners_enabled,
    project_cost_centers_enabled = excluded.project_cost_centers_enabled,
    project_categories_enabled = excluded.project_categories_enabled,
    project_business_units_enabled = excluded.project_business_units_enabled,
    project_updates_enabled = excluded.project_updates_enabled,
    project_incumbent_suppliers_enabled = excluded.project_incumbent_suppliers_enabled,
    savings_realization_enabled = excluded.savings_realization_enabled,
    updated_by = excluded.updated_by;
end
$$;


ALTER FUNCTION "public"."update_workspace_settings_v9"("p_organization_name" "text", "p_full_name" "text", "p_currency_code" "text", "p_locale" "text", "p_timezone" "text", "p_fiscal_year_start_month" integer, "p_date_format" "text", "p_default_recognition_method" "text", "p_require_baseline" boolean, "p_hard_reduction_approval_threshold" numeric, "p_support_projects_enabled" boolean, "p_project_descriptions_enabled" boolean, "p_project_owners_enabled" boolean, "p_project_cost_centers_enabled" boolean, "p_project_categories_enabled" boolean, "p_project_business_units_enabled" boolean, "p_project_updates_enabled" boolean, "p_project_incumbent_suppliers_enabled" boolean, "p_savings_realization_enabled" boolean) OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "public"."audit_log" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid" NOT NULL,
    "actor_id" "uuid",
    "entity_type" "text" NOT NULL,
    "entity_id" "uuid" NOT NULL,
    "action" "text" NOT NULL,
    "before_data" "jsonb",
    "after_data" "jsonb",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "audit_log_action_check" CHECK (("action" = ANY (ARRAY['insert'::"text", 'update'::"text", 'delete'::"text"]))),
    CONSTRAINT "audit_log_entity_type_check" CHECK (("entity_type" = ANY (ARRAY['organization'::"text", 'organization_settings'::"text", 'supplier'::"text", 'supplier_contact'::"text", 'supplier_certification'::"text", 'supplier_performance_review'::"text", 'supplier_risk'::"text", 'project_choice_option'::"text", 'category'::"text", 'business_unit'::"text", 'cost_center'::"text", 'project_classification_reset'::"text", 'savings_calculation'::"text", 'savings_period'::"text", 'realization_period'::"text", 'sourcing_event'::"text"])))
);

ALTER TABLE ONLY "public"."audit_log" FORCE ROW LEVEL SECURITY;


ALTER TABLE "public"."audit_log" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."award_lines" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid",
    "award_id" "uuid",
    "event_id" "uuid",
    "scope_line_id" "uuid",
    "line_number" integer NOT NULL,
    "awarded_unit_price" numeric(15,4),
    "awarded_quantity" numeric(15,2),
    "awarded_extended_amount" numeric(15,2) DEFAULT 0,
    "awarded_recurring_amount" numeric(15,2) DEFAULT 0,
    "awarded_one_time_amount" numeric(15,2) DEFAULT 0,
    "awarded_term_months" numeric(10,2),
    "annualized_award_amount" numeric(15,2) DEFAULT 0,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "created_by" "uuid",
    "updated_by" "uuid"
);

ALTER TABLE ONLY "public"."award_lines" FORCE ROW LEVEL SECURITY;


ALTER TABLE "public"."award_lines" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."awards" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid",
    "event_id" "uuid",
    "supplier_id" "uuid",
    "offer_id" "uuid",
    "award_name" "text" NOT NULL,
    "award_date" "date",
    "award_total_amount" numeric(15,2) DEFAULT 0,
    "award_status" "text" DEFAULT 'Recommended'::"text",
    "award_approved_by" "uuid",
    "award_approval_date" timestamp with time zone,
    "award_notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "created_by" "uuid",
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "updated_by" "uuid",
    CONSTRAINT "awards_award_status_check" CHECK (("award_status" = ANY (ARRAY['Recommended'::"text", 'Approved'::"text", 'Rejected'::"text", 'On Hold'::"text"])))
);

ALTER TABLE ONLY "public"."awards" FORCE ROW LEVEL SECURITY;


ALTER TABLE "public"."awards" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."baseline_lines" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid",
    "baseline_id" "uuid",
    "event_id" "uuid",
    "scope_line_id" "uuid",
    "line_number" integer NOT NULL,
    "baseline_unit_price" numeric(15,4),
    "baseline_quantity" numeric(15,2),
    "baseline_extended_amount" numeric(15,2) DEFAULT 0,
    "baseline_recurring_amount" numeric(15,2) DEFAULT 0,
    "baseline_one_time_amount" numeric(15,2) DEFAULT 0,
    "baseline_term_months" numeric(10,2),
    "annualized_baseline_amount" numeric(15,2) DEFAULT 0,
    "normalized_quantity" numeric(15,2),
    "normalized_unit_price" numeric(15,4),
    "normalized_extended_amount" numeric(15,2) DEFAULT 0,
    "tax_amount_included" numeric(15,2) DEFAULT 0,
    "freight_amount_included" numeric(15,2) DEFAULT 0,
    "source_document_id" "text",
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "created_by" "uuid",
    "updated_by" "uuid"
);

ALTER TABLE ONLY "public"."baseline_lines" FORCE ROW LEVEL SECURITY;


ALTER TABLE "public"."baseline_lines" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."baselines" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid",
    "event_id" "uuid",
    "baseline_name" "text" NOT NULL,
    "baseline_type" "text" NOT NULL,
    "baseline_source" "text",
    "baseline_period_start" "date",
    "baseline_period_end" "date",
    "baseline_currency_code" "text" DEFAULT 'USD'::"text",
    "baseline_fx_rate_to_usd" numeric(10,4) DEFAULT 1.0000,
    "baseline_total_amount" numeric(15,2) DEFAULT 0,
    "baseline_normalized_amount" numeric(15,2) DEFAULT 0,
    "normalization_notes" "text",
    "baseline_lock_status" "text" DEFAULT 'Draft'::"text",
    "baseline_lock_date" timestamp with time zone,
    "baseline_approved_by" "uuid",
    "baseline_approval_date" timestamp with time zone,
    "official_for_hard_savings" boolean DEFAULT false,
    "official_for_cost_avoidance" boolean DEFAULT false,
    "official_for_demand_reduction" boolean DEFAULT false,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "created_by" "uuid",
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "updated_by" "uuid",
    "baseline_term_months" numeric,
    "is_selected" boolean DEFAULT false NOT NULL,
    "hard_reduction_override" boolean DEFAULT false NOT NULL,
    "hard_reduction_override_reason" "text",
    "hard_reduction_override_by" "uuid",
    "hard_reduction_override_at" timestamp with time zone,
    CONSTRAINT "baselines_baseline_lock_status_check" CHECK (("baseline_lock_status" = ANY (ARRAY['Draft'::"text", 'Locked'::"text", 'Submitted'::"text", 'Approved'::"text", 'Rejected'::"text"]))),
    CONSTRAINT "chk_baseline_lock_status" CHECK (("baseline_lock_status" = ANY (ARRAY['Draft'::"text", 'Locked'::"text", 'Submitted'::"text", 'Approved'::"text", 'Rejected'::"text"]))),
    CONSTRAINT "chk_hard_reduction_override_reason" CHECK ((("hard_reduction_override" = false) OR (("hard_reduction_override_reason" IS NOT NULL) AND ("length"("btrim"("hard_reduction_override_reason")) >= 10))))
);

ALTER TABLE ONLY "public"."baselines" FORCE ROW LEVEL SECURITY;


ALTER TABLE "public"."baselines" OWNER TO "postgres";


COMMENT ON COLUMN "public"."baselines"."baseline_term_months" IS 'Term the baseline_total_amount covers, in months. Used to derive a monthly rate (amount / months) so baselines and offers of different lengths can be compared like with like. NULL means the term was not captured.';



COMMENT ON COLUMN "public"."baselines"."is_selected" IS 'True for the one baseline this project measures against. At most one per event.';



COMMENT ON COLUMN "public"."baselines"."hard_reduction_override" IS 'True when a buyer has declared this baseline good enough to book a HARD cost reduction despite its type being classified as soft. Never changes the Total -- only moves money between the Reduction and Avoidance lines.';



COMMENT ON COLUMN "public"."baselines"."hard_reduction_override_reason" IS 'Why this baseline is defensible as own-spend despite its type. Required when the override is on, minimum 10 characters, enforced by CHECK.';



CREATE TABLE IF NOT EXISTS "public"."business_units" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid",
    "business_unit_name" "text" NOT NULL,
    "parent_business_unit_id" "uuid",
    "active_flag" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"()
);

ALTER TABLE ONLY "public"."business_units" FORCE ROW LEVEL SECURITY;


ALTER TABLE "public"."business_units" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."categories" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid",
    "category_name" "text" NOT NULL,
    "parent_category_id" "uuid",
    "default_baseline_type" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "active_flag" boolean DEFAULT true NOT NULL
);

ALTER TABLE ONLY "public"."categories" FORCE ROW LEVEL SECURITY;


ALTER TABLE "public"."categories" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."cost_centers" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid",
    "cost_center_name" "text" NOT NULL,
    "business_unit_id" "uuid",
    "gl_account_default" "text",
    "active_flag" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"()
);

ALTER TABLE ONLY "public"."cost_centers" FORCE ROW LEVEL SECURITY;


ALTER TABLE "public"."cost_centers" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."event_scope_lines" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid",
    "event_id" "uuid",
    "line_number" integer NOT NULL,
    "category_id" "uuid",
    "item_service_name" "text" NOT NULL,
    "item_description" "text",
    "uom" "text",
    "location_id" "text",
    "baseline_quantity" numeric(15,2),
    "forecast_quantity" numeric(15,2),
    "final_quantity" numeric(15,2),
    "scope_change_flag" boolean DEFAULT false,
    "scope_change_description" "text",
    "business_equivalency_confirmed" boolean DEFAULT false,
    "business_equivalency_confirmed_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "created_by" "uuid",
    "updated_by" "uuid"
);

ALTER TABLE ONLY "public"."event_scope_lines" FORCE ROW LEVEL SECURITY;


ALTER TABLE "public"."event_scope_lines" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."organization_settings" (
    "organization_id" "uuid" NOT NULL,
    "currency_code" "text" DEFAULT 'USD'::"text" NOT NULL,
    "locale" "text" DEFAULT 'en-US'::"text" NOT NULL,
    "timezone" "text" DEFAULT 'America/Chicago'::"text" NOT NULL,
    "fiscal_year_start_month" integer DEFAULT 1 NOT NULL,
    "date_format" "text" DEFAULT 'MMM D, YYYY'::"text" NOT NULL,
    "default_recognition_method" "text" DEFAULT 'monthly'::"text" NOT NULL,
    "require_baseline_for_hard_reduction" boolean DEFAULT true NOT NULL,
    "hard_reduction_approval_threshold" numeric(15,2),
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "uuid",
    "support_projects_enabled" boolean DEFAULT true NOT NULL,
    "project_descriptions_enabled" boolean DEFAULT true NOT NULL,
    "project_owners_enabled" boolean DEFAULT true NOT NULL,
    "project_cost_centers_enabled" boolean DEFAULT true NOT NULL,
    "project_categories_enabled" boolean DEFAULT true NOT NULL,
    "project_business_units_enabled" boolean DEFAULT true NOT NULL,
    "project_updates_enabled" boolean DEFAULT true NOT NULL,
    "project_incumbent_suppliers_enabled" boolean DEFAULT true NOT NULL,
    "savings_realization_enabled" boolean DEFAULT false NOT NULL,
    CONSTRAINT "organization_settings_currency_code_check" CHECK (("currency_code" ~ '^[A-Z]{3}$'::"text")),
    CONSTRAINT "organization_settings_date_format_check" CHECK (("date_format" = ANY (ARRAY['MMM D, YYYY'::"text", 'MM/DD/YYYY'::"text", 'DD/MM/YYYY'::"text", 'YYYY-MM-DD'::"text"]))),
    CONSTRAINT "organization_settings_default_recognition_method_check" CHECK (("default_recognition_method" = ANY (ARRAY['monthly'::"text", 'annual'::"text", 'one_time'::"text"]))),
    CONSTRAINT "organization_settings_fiscal_year_start_month_check" CHECK ((("fiscal_year_start_month" >= 1) AND ("fiscal_year_start_month" <= 12))),
    CONSTRAINT "organization_settings_hard_reduction_approval_threshold_check" CHECK ((("hard_reduction_approval_threshold" IS NULL) OR ("hard_reduction_approval_threshold" >= (0)::numeric)))
);

ALTER TABLE ONLY "public"."organization_settings" FORCE ROW LEVEL SECURITY;


ALTER TABLE "public"."organization_settings" OWNER TO "postgres";


COMMENT ON COLUMN "public"."organization_settings"."support_projects_enabled" IS 'Controls whether new Support / Non-Commercial projects may be created. Existing Support projects remain available.';



COMMENT ON COLUMN "public"."organization_settings"."project_descriptions_enabled" IS 'Controls whether project descriptions may be added or changed. Existing descriptions remain visible.';



COMMENT ON COLUMN "public"."organization_settings"."project_owners_enabled" IS 'Controls whether project Owner / Buyer values may be added or changed. Existing values remain visible.';



COMMENT ON COLUMN "public"."organization_settings"."project_cost_centers_enabled" IS 'Controls whether project Cost Center values may be added or changed. Existing values remain visible.';



COMMENT ON COLUMN "public"."organization_settings"."project_categories_enabled" IS 'Controls whether project Category values may be added or changed. Existing values remain visible.';



COMMENT ON COLUMN "public"."organization_settings"."project_business_units_enabled" IS 'Controls whether project Business Unit values may be added or changed. Existing values remain visible.';



COMMENT ON COLUMN "public"."organization_settings"."project_updates_enabled" IS 'Controls whether new project updates may be added. Existing update history remains visible.';



COMMENT ON COLUMN "public"."organization_settings"."project_incumbent_suppliers_enabled" IS 'Controls whether an incumbent supplier may be assigned to a project. Existing assignments remain visible.';



COMMENT ON COLUMN "public"."organization_settings"."savings_realization_enabled" IS 'Enables actual/realized savings entry, variance, and finance validation against executed schedule periods.';



CREATE TABLE IF NOT EXISTS "public"."organizations" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "is_demo_template" boolean DEFAULT false NOT NULL
);

ALTER TABLE ONLY "public"."organizations" FORCE ROW LEVEL SECURITY;


ALTER TABLE "public"."organizations" OWNER TO "postgres";


COMMENT ON COLUMN "public"."organizations"."is_demo_template" IS 'True for the single frozen organization that new signups are seeded from. Not a tenant anyone logs into.';



CREATE TABLE IF NOT EXISTS "public"."profiles" (
    "id" "uuid" NOT NULL,
    "organization_id" "uuid",
    "email" "text",
    "full_name" "text",
    "role" "text" DEFAULT 'viewer'::"text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "profiles_role_check" CHECK (("role" = ANY (ARRAY['admin'::"text", 'procurement_user'::"text", 'viewer'::"text"])))
);

ALTER TABLE ONLY "public"."profiles" FORCE ROW LEVEL SECURITY;


ALTER TABLE "public"."profiles" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."project_choice_options" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid" NOT NULL,
    "choice_type" "text" NOT NULL,
    "project_type" "text",
    "label" "text" NOT NULL,
    "active_flag" boolean DEFAULT true NOT NULL,
    "sort_order" integer DEFAULT 0 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "uuid",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "uuid",
    "is_terminal" boolean DEFAULT false NOT NULL,
    "requires_savings_disposition" boolean DEFAULT false NOT NULL,
    CONSTRAINT "project_choice_options_choice_type_check" CHECK (("choice_type" = ANY (ARRAY['event_type'::"text", 'event_status'::"text", 'owner'::"text"]))),
    CONSTRAINT "project_choice_options_label_check" CHECK ((("length"("btrim"("label")) >= 1) AND ("length"("btrim"("label")) <= 120))),
    CONSTRAINT "project_choice_options_project_type_check" CHECK (("project_type" = ANY (ARRAY['Sourcing'::"text", 'Support'::"text"]))),
    CONSTRAINT "project_choice_options_savings_disposition_status_only" CHECK (((NOT "requires_savings_disposition") OR (("choice_type" = 'event_status'::"text") AND ("project_type" = 'Sourcing'::"text") AND "is_terminal"))),
    CONSTRAINT "project_choice_options_scope_check" CHECK (((("choice_type" = ANY (ARRAY['event_type'::"text", 'event_status'::"text"])) AND ("project_type" IS NOT NULL)) OR (("choice_type" = 'owner'::"text") AND ("project_type" IS NULL)))),
    CONSTRAINT "project_choice_options_terminal_status_only" CHECK (((NOT "is_terminal") OR ("choice_type" = 'event_status'::"text")))
);

ALTER TABLE ONLY "public"."project_choice_options" FORCE ROW LEVEL SECURITY;


ALTER TABLE "public"."project_choice_options" OWNER TO "postgres";


COMMENT ON COLUMN "public"."project_choice_options"."is_terminal" IS 'True when this managed event status represents a finished project. New custom statuses default to non-terminal.';



COMMENT ON COLUMN "public"."project_choice_options"."requires_savings_disposition" IS 'True for the one Sourcing completion status that requires an executed/no-executed-savings decision. The flag survives status renames.';



CREATE TABLE IF NOT EXISTS "public"."project_updates" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid" NOT NULL,
    "event_id" "uuid" NOT NULL,
    "body" "text" NOT NULL,
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "project_updates_body_length" CHECK (("char_length"("body") <= 10000)),
    CONSTRAINT "project_updates_body_not_blank" CHECK (("length"("btrim"("body")) > 0))
);

ALTER TABLE ONLY "public"."project_updates" FORCE ROW LEVEL SECURITY;


ALTER TABLE "public"."project_updates" OWNER TO "postgres";


COMMENT ON TABLE "public"."project_updates" IS 'Append-only, dated project progress updates. Editing, deletion, mentions, and notifications are intentionally deferred.';



CREATE TABLE IF NOT EXISTS "public"."realization_periods" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid",
    "event_id" "uuid",
    "savings_calculation_id" "uuid",
    "period_name" "text" NOT NULL,
    "period_start_date" "date" NOT NULL,
    "period_end_date" "date" NOT NULL,
    "baseline_amount" numeric(15,2) DEFAULT 0,
    "actual_amount" numeric(15,2),
    "projected_savings" numeric(15,2) DEFAULT 0,
    "realized_savings" numeric(15,2),
    "leakage_amount" numeric(15,2),
    "leakage_reason" "text",
    "realization_status" "text" DEFAULT 'Pending'::"text",
    "evidence_document_id" "text",
    "finance_validated" boolean DEFAULT false,
    "finance_validated_by" "uuid",
    "finance_validation_date" timestamp with time zone,
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "created_by" "uuid",
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "updated_by" "uuid",
    "savings_period_id" "uuid",
    "comparison_rebased_at" timestamp with time zone,
    "comparison_rebased_by" "uuid",
    "projected_reduction_amount" numeric(15,2),
    "projected_avoidance_amount" numeric(15,2),
    "realized_reduction_amount" numeric(15,2),
    "realized_avoidance_amount" numeric(15,2),
    CONSTRAINT "chk_realization_status" CHECK (("realization_status" = ANY (ARRAY['Pending'::"text", 'In Progress'::"text", 'Realized'::"text", 'Partially Realized'::"text", 'Not Realized'::"text", 'Leaked'::"text"]))),
    CONSTRAINT "realization_periods_actual_nonnegative" CHECK ((("actual_amount" IS NULL) OR ("actual_amount" >= (0)::numeric))),
    CONSTRAINT "realization_periods_derived_status" CHECK (("realization_status" = "public"."derive_realization_status"("projected_reduction_amount", "projected_avoidance_amount", "realized_reduction_amount", "realized_avoidance_amount"))),
    CONSTRAINT "realization_periods_projected_total_per_leg" CHECK ((NOT ("projected_savings" IS DISTINCT FROM
CASE
    WHEN (("projected_reduction_amount" IS NULL) AND ("projected_avoidance_amount" IS NULL)) THEN NULL::numeric
    ELSE (COALESCE("projected_reduction_amount", (0)::numeric) + COALESCE("projected_avoidance_amount", (0)::numeric))
END))),
    CONSTRAINT "realization_periods_realization_status_check" CHECK (("realization_status" = ANY (ARRAY['Pending'::"text", 'In Progress'::"text", 'Realized'::"text", 'Partially Realized'::"text", 'Not Realized'::"text", 'Leaked'::"text"]))),
    CONSTRAINT "realization_periods_realized_total_per_leg" CHECK ((NOT ("realized_savings" IS DISTINCT FROM
CASE
    WHEN (("realized_reduction_amount" IS NULL) AND ("realized_avoidance_amount" IS NULL)) THEN NULL::numeric
    ELSE (COALESCE("realized_reduction_amount", (0)::numeric) + COALESCE("realized_avoidance_amount", (0)::numeric))
END))),
    CONSTRAINT "realization_periods_reduction_leakage" CHECK ((NOT ("leakage_amount" IS DISTINCT FROM
CASE
    WHEN (("projected_reduction_amount" IS NULL) OR ("realized_reduction_amount" IS NULL)) THEN NULL::numeric
    ELSE GREATEST(("projected_reduction_amount" - "realized_reduction_amount"), (0)::numeric)
END)))
);

ALTER TABLE ONLY "public"."realization_periods" FORCE ROW LEVEL SECURITY;


ALTER TABLE "public"."realization_periods" OWNER TO "postgres";


COMMENT ON COLUMN "public"."realization_periods"."leakage_amount" IS 'Reduction leakage only: positive executed reduction less realized reduction. Avoidance shortfall is never leakage.';



COMMENT ON COLUMN "public"."realization_periods"."comparison_rebased_at" IS 'Most recent time an executed-savings correction rebased this period comparator. NULL means never rebased.';



COMMENT ON COLUMN "public"."realization_periods"."projected_reduction_amount" IS 'Executed cost-reduction comparator for this period.';



COMMENT ON COLUMN "public"."realization_periods"."projected_avoidance_amount" IS 'Executed cost-avoidance comparator for this period.';



COMMENT ON COLUMN "public"."realization_periods"."realized_reduction_amount" IS 'Realized cost reduction, derived from actual spend when defensible or entered directly.';



COMMENT ON COLUMN "public"."realization_periods"."realized_avoidance_amount" IS 'Realized cost avoidance entered directly because it is counterfactual and not derivable from spend.';



CREATE TABLE IF NOT EXISTS "public"."savings_calculation_lines" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid",
    "savings_calculation_id" "uuid",
    "event_id" "uuid",
    "scope_line_id" "uuid",
    "line_number" integer NOT NULL,
    "baseline_unit_price" numeric(15,4),
    "baseline_quantity" numeric(15,2),
    "baseline_extended_amount" numeric(15,2) DEFAULT 0,
    "awarded_unit_price" numeric(15,4),
    "awarded_quantity" numeric(15,2),
    "awarded_extended_amount" numeric(15,2) DEFAULT 0,
    "savings_amount" numeric(15,2) DEFAULT 0,
    "savings_percentage" numeric(9,2) DEFAULT 0,
    "savings_type" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "created_by" "uuid",
    "updated_by" "uuid"
);

ALTER TABLE ONLY "public"."savings_calculation_lines" FORCE ROW LEVEL SECURITY;


ALTER TABLE "public"."savings_calculation_lines" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."savings_calculations" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid",
    "event_id" "uuid",
    "baseline_id" "uuid",
    "award_id" "uuid",
    "calculation_name" "text" NOT NULL,
    "savings_type" "text" NOT NULL,
    "baseline_total_amount" numeric(15,2) DEFAULT 0,
    "award_total_amount" numeric(15,2) DEFAULT 0,
    "gross_savings_amount" numeric(15,2) DEFAULT 0,
    "savings_percentage" numeric(9,2) DEFAULT 0,
    "net_savings_amount" numeric(15,2) DEFAULT 0,
    "calculation_status" "text" DEFAULT 'estimated'::"text",
    "recognition_notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "created_by" "uuid",
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "updated_by" "uuid",
    "savings_start_date" "date",
    "savings_end_date" "date",
    "cost_reduction_amount" numeric(15,2) DEFAULT 0,
    "cost_avoidance_amount" numeric(15,2) DEFAULT 0,
    "opening_proposal_amount" numeric(15,2),
    "schedule_start_month" integer,
    "schedule_start_year" integer,
    "schedule_period_type" "text",
    "schedule_period_count" integer,
    "executed_at" timestamp with time zone,
    "executed_by" "uuid",
    "execution_note" "text",
    "legacy_execution_actor_missing" boolean DEFAULT false NOT NULL,
    CONSTRAINT "chk_calculation_status" CHECK (("calculation_status" = ANY (ARRAY['estimated'::"text", 'executed'::"text"]))),
    CONSTRAINT "chk_savings_execution_metadata" CHECK (((("calculation_status" = 'estimated'::"text") AND ("executed_at" IS NULL) AND ("executed_by" IS NULL) AND ("execution_note" IS NULL) AND (NOT "legacy_execution_actor_missing")) OR (("calculation_status" = 'executed'::"text") AND ("executed_at" IS NOT NULL) AND ((("executed_by" IS NOT NULL) AND (NOT "legacy_execution_actor_missing")) OR (("executed_by" IS NULL) AND "legacy_execution_actor_missing"))))),
    CONSTRAINT "chk_schedule_period_count" CHECK ((("schedule_period_count" IS NULL) OR (("schedule_period_count" >= 1) AND ("schedule_period_count" <= 600)))),
    CONSTRAINT "chk_schedule_period_type" CHECK ((("schedule_period_type" IS NULL) OR ("schedule_period_type" = ANY (ARRAY['monthly'::"text", 'annual'::"text", 'one_time'::"text"])))),
    CONSTRAINT "chk_schedule_start_month" CHECK ((("schedule_start_month" IS NULL) OR (("schedule_start_month" >= 1) AND ("schedule_start_month" <= 12)))),
    CONSTRAINT "chk_schedule_start_year" CHECK ((("schedule_start_year" IS NULL) OR (("schedule_start_year" >= 2000) AND ("schedule_start_year" <= 2100)))),
    CONSTRAINT "savings_calculations_savings_type_check" CHECK (("savings_type" = ANY (ARRAY['Cost Reduction'::"text", 'Cost Avoidance'::"text", 'Demand Reduction'::"text", 'TCO Improvement'::"text", 'Working Capital'::"text"])))
);

ALTER TABLE ONLY "public"."savings_calculations" FORCE ROW LEVEL SECURITY;


ALTER TABLE "public"."savings_calculations" OWNER TO "postgres";


COMMENT ON COLUMN "public"."savings_calculations"."gross_savings_amount" IS 'THE CHAIN TOTAL (Opening - Final) - the reported headline. Equals cost_reduction_amount + cost_avoidance_amount exactly. When no opening was captured this collapses to Cost Reduction (Baseline - Final).';



COMMENT ON COLUMN "public"."savings_calculations"."savings_percentage" IS 'Total savings as a percentage of BASELINE spend (never of the opening ask or the awarded amount). NULL means not applicable -- no baseline anchor. Written only by reportableSavingsPct() in lib/savings.';



COMMENT ON COLUMN "public"."savings_calculations"."cost_reduction_amount" IS 'Baseline - Final. Hard, hits the P&L. MAY BE NEGATIVE (a genuine cost increase) - show in parentheses, never sign-flip, never relabel as savings. NULL means NOT APPLICABLE (no baseline anchor), distinct from 0.';



COMMENT ON COLUMN "public"."savings_calculations"."cost_avoidance_amount" IS 'Opening - Baseline. Soft. With no baseline anchor the whole span books here.';



COMMENT ON COLUMN "public"."savings_calculations"."opening_proposal_amount" IS 'The vendor''s opening proposal - the third anchor in the chain (Opening -> Baseline -> Final). NULL means no opening was captured, which is distinct from 0. Cost Avoidance = Opening - Baseline. Total procurement performance = Opening - Final = Reduction + Avoidance.';



COMMENT ON COLUMN "public"."savings_calculations"."schedule_start_month" IS 'Month (1-12) the savings start being booked. With schedule_start_year this replaces date arithmetic entirely -- see savings_periods.';



COMMENT ON COLUMN "public"."savings_calculations"."schedule_period_type" IS 'monthly | annual | one_time. Determines how many months one schedule row covers (1, 12, or the whole deal term). All three book the same total.';



COMMENT ON COLUMN "public"."savings_calculations"."schedule_period_count" IS 'How many rows the schedule has. Defaults to whatever covers the deal term exactly; a term that is not a whole number of periods ends in a short one.';



COMMENT ON COLUMN "public"."savings_calculations"."legacy_execution_actor_missing" IS 'True only for actorless executions preserved from before execution provenance controls existed.';



CREATE TABLE IF NOT EXISTS "public"."savings_periods" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid" NOT NULL,
    "event_id" "uuid" NOT NULL,
    "savings_calculation_id" "uuid" NOT NULL,
    "period_number" integer NOT NULL,
    "period_month" integer NOT NULL,
    "period_year" integer NOT NULL,
    "period_months" numeric DEFAULT 0 NOT NULL,
    "baseline_amount" numeric(15,2),
    "opening_amount" numeric(15,2),
    "final_amount" numeric(15,2) DEFAULT 0 NOT NULL,
    "cost_reduction_amount" numeric(15,2),
    "cost_avoidance_amount" numeric(15,2) DEFAULT 0 NOT NULL,
    "total_savings_amount" numeric(15,2) DEFAULT 0 NOT NULL,
    "is_edited" boolean DEFAULT false NOT NULL,
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "uuid",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "uuid",
    "executed_baseline_amount" numeric(15,2),
    "executed_opening_amount" numeric(15,2),
    "executed_final_amount" numeric(15,2),
    "executed_cost_reduction_amount" numeric(15,2),
    "executed_cost_avoidance_amount" numeric(15,2),
    "executed_total_savings_amount" numeric(15,2),
    CONSTRAINT "chk_savings_periods_estimated_chain" CHECK (((NOT ("cost_reduction_amount" IS DISTINCT FROM
CASE
    WHEN ("baseline_amount" IS NULL) THEN NULL::numeric
    ELSE ("baseline_amount" - "final_amount")
END)) AND ("cost_avoidance_amount" =
CASE
    WHEN (("baseline_amount" IS NOT NULL) AND ("opening_amount" > "baseline_amount")) THEN ("opening_amount" - "baseline_amount")
    WHEN (("baseline_amount" IS NULL) AND ("opening_amount" IS NOT NULL)) THEN ("opening_amount" - "final_amount")
    ELSE (0)::numeric
END) AND ("total_savings_amount" = (COALESCE("cost_reduction_amount", (0)::numeric) + "cost_avoidance_amount")))),
    CONSTRAINT "chk_savings_periods_executed_chain" CHECK ((("executed_total_savings_amount" IS NULL) OR ((NOT ("executed_cost_reduction_amount" IS DISTINCT FROM
CASE
    WHEN ("executed_baseline_amount" IS NULL) THEN NULL::numeric
    ELSE ("executed_baseline_amount" - "executed_final_amount")
END)) AND ("executed_cost_avoidance_amount" =
CASE
    WHEN (("executed_baseline_amount" IS NOT NULL) AND ("executed_opening_amount" > "executed_baseline_amount")) THEN ("executed_opening_amount" - "executed_baseline_amount")
    WHEN (("executed_baseline_amount" IS NULL) AND ("executed_opening_amount" IS NOT NULL)) THEN ("executed_opening_amount" - "executed_final_amount")
    ELSE (0)::numeric
END) AND ("executed_total_savings_amount" = (COALESCE("executed_cost_reduction_amount", (0)::numeric) + "executed_cost_avoidance_amount"))))),
    CONSTRAINT "chk_savings_periods_month" CHECK ((("period_month" >= 1) AND ("period_month" <= 12))),
    CONSTRAINT "chk_savings_periods_months" CHECK (("period_months" >= (0)::numeric)),
    CONSTRAINT "chk_savings_periods_number" CHECK (("period_number" >= 1)),
    CONSTRAINT "chk_savings_periods_year" CHECK ((("period_year" >= 2000) AND ("period_year" <= 2100)))
);

ALTER TABLE ONLY "public"."savings_periods" FORCE ROW LEVEL SECURITY;


ALTER TABLE "public"."savings_periods" OWNER TO "postgres";


COMMENT ON TABLE "public"."savings_periods" IS 'The savings schedule: one row per period, each carrying the three anchors and the derived chain. Generated from the anchors, then editable. Grouping these rows by calendar year is what produces fiscal-year and YoY reporting.';



COMMENT ON COLUMN "public"."savings_periods"."period_months" IS 'Months of the deal term this row books. Zero past the end of the term.';



COMMENT ON COLUMN "public"."savings_periods"."cost_reduction_amount" IS 'Baseline - Final for this period. NULL means NOT APPLICABLE (no baseline anchor), which is distinct from zero. May legitimately be negative.';



COMMENT ON COLUMN "public"."savings_periods"."total_savings_amount" IS 'Estimated savings for this period. Preserved when an executed snapshot is created.';



COMMENT ON COLUMN "public"."savings_periods"."is_edited" IS 'True when the amounts were overridden by hand rather than generated.';



COMMENT ON COLUMN "public"."savings_periods"."executed_total_savings_amount" IS 'Executed savings snapshot for this period. NULL means the schedule has not been executed.';



COMMENT ON CONSTRAINT "chk_savings_periods_estimated_chain" ON "public"."savings_periods" IS 'Cent-exact estimated row: anchors derive reduction/avoidance and both legs derive total.';



COMMENT ON CONSTRAINT "chk_savings_periods_executed_chain" ON "public"."savings_periods" IS 'Cent-exact executed snapshot: anchors derive reduction/avoidance and both legs derive total.';



CREATE TABLE IF NOT EXISTS "public"."sourcing_events" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid",
    "event_name" "text" NOT NULL,
    "event_description" "text",
    "event_type" "text" NOT NULL,
    "sourcing_method" "text",
    "category_id" "uuid",
    "business_unit_id" "uuid",
    "cost_center_id" "uuid",
    "incumbent_supplier_id" "uuid",
    "awarded_supplier_id" "uuid",
    "procurement_owner_id" "uuid",
    "business_owner_id" "uuid",
    "finance_owner_id" "uuid",
    "event_status" "text" DEFAULT 'Pipeline'::"text",
    "currency_code" "text" DEFAULT 'USD'::"text",
    "fx_rate_to_usd" numeric(10,4) DEFAULT 1.0000,
    "event_start_date" "date",
    "event_close_date" "date",
    "contract_start_date" "date",
    "contract_end_date" "date",
    "recognition_start_date" "date",
    "recognition_end_date" "date",
    "official_reporting_basis" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "created_by" "uuid",
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "updated_by" "uuid",
    "project_type" "text" DEFAULT 'Sourcing'::"text",
    "buyer_name" "text",
    "notes" "text",
    "project_due_date" "date",
    "savings_disposition" "text",
    "savings_disposition_reason" "text",
    "savings_disposition_at" timestamp with time zone,
    "savings_disposition_by" "uuid",
    CONSTRAINT "sourcing_events_no_execution_reason_check" CHECK ((("savings_disposition" <> 'no_executed_savings'::"text") OR ("length"("btrim"("savings_disposition_reason")) >= 10))),
    CONSTRAINT "sourcing_events_project_type_check" CHECK (("project_type" = ANY (ARRAY['Sourcing'::"text", 'Support'::"text"]))),
    CONSTRAINT "sourcing_events_savings_disposition_check" CHECK ((("savings_disposition" IS NULL) OR ("savings_disposition" = ANY (ARRAY['executed'::"text", 'no_executed_savings'::"text"]))))
);

ALTER TABLE ONLY "public"."sourcing_events" FORCE ROW LEVEL SECURITY;


ALTER TABLE "public"."sourcing_events" OWNER TO "postgres";


COMMENT ON COLUMN "public"."sourcing_events"."notes" IS 'Legacy project note retained for compatibility. New content belongs in project_updates.';



COMMENT ON COLUMN "public"."sourcing_events"."project_due_date" IS 'Planned date by which the project should be completed. Distinct from event_close_date, the actual completion/close date.';



CREATE TABLE IF NOT EXISTS "public"."supplier_certifications" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid" NOT NULL,
    "supplier_id" "uuid" NOT NULL,
    "certification_name" "text" NOT NULL,
    "issuer" "text",
    "certificate_number" "text",
    "issued_on" "date",
    "expires_on" "date",
    "evidence_url" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "uuid",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "uuid",
    CONSTRAINT "supplier_certifications_date_order_check" CHECK ((("issued_on" IS NULL) OR ("expires_on" IS NULL) OR ("expires_on" >= "issued_on"))),
    CONSTRAINT "supplier_certifications_issuer_check" CHECK ((("issuer" IS NULL) OR (("char_length"("issuer") >= 1) AND ("char_length"("issuer") <= 200)))),
    CONSTRAINT "supplier_certifications_name_check" CHECK ((("char_length"("btrim"("certification_name")) >= 2) AND ("char_length"("btrim"("certification_name")) <= 200))),
    CONSTRAINT "supplier_certifications_number_check" CHECK ((("certificate_number" IS NULL) OR (("char_length"("certificate_number") >= 1) AND ("char_length"("certificate_number") <= 200)))),
    CONSTRAINT "supplier_certifications_url_check" CHECK ((("evidence_url" IS NULL) OR (("char_length"("evidence_url") <= 2000) AND ("evidence_url" ~ '^https?://'::"text"))))
);

ALTER TABLE ONLY "public"."supplier_certifications" FORCE ROW LEVEL SECURITY;


ALTER TABLE "public"."supplier_certifications" OWNER TO "postgres";


COMMENT ON TABLE "public"."supplier_certifications" IS 'Supplier certifications with issuer, validity dates, and optional public evidence.';



CREATE TABLE IF NOT EXISTS "public"."supplier_contacts" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid" NOT NULL,
    "supplier_id" "uuid" NOT NULL,
    "contact_name" "text" NOT NULL,
    "job_title" "text",
    "email" "text",
    "phone" "text",
    "is_primary" boolean DEFAULT false NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "uuid",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "uuid",
    CONSTRAINT "supplier_contacts_email_check" CHECK ((("email" IS NULL) OR (("char_length"("email") <= 320) AND (POSITION(('@'::"text") IN ("email")) > 1)))),
    CONSTRAINT "supplier_contacts_job_title_check" CHECK ((("job_title" IS NULL) OR (("char_length"("job_title") >= 1) AND ("char_length"("job_title") <= 160)))),
    CONSTRAINT "supplier_contacts_name_check" CHECK ((("char_length"("btrim"("contact_name")) >= 2) AND ("char_length"("btrim"("contact_name")) <= 160))),
    CONSTRAINT "supplier_contacts_phone_check" CHECK ((("phone" IS NULL) OR (("char_length"("phone") >= 3) AND ("char_length"("phone") <= 50))))
);

ALTER TABLE ONLY "public"."supplier_contacts" FORCE ROW LEVEL SECURITY;


ALTER TABLE "public"."supplier_contacts" OWNER TO "postgres";


COMMENT ON TABLE "public"."supplier_contacts" IS 'Named commercial and operational contacts attached to one supplier relationship.';



CREATE TABLE IF NOT EXISTS "public"."supplier_notes" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid" NOT NULL,
    "supplier_id" "uuid" NOT NULL,
    "occurred_on" "date" DEFAULT CURRENT_DATE NOT NULL,
    "body" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "uuid",
    CONSTRAINT "supplier_notes_body_length" CHECK (("char_length"("body") <= 10000)),
    CONSTRAINT "supplier_notes_body_not_blank" CHECK (("length"("btrim"("body")) > 0))
);

ALTER TABLE ONLY "public"."supplier_notes" FORCE ROW LEVEL SECURITY;


ALTER TABLE "public"."supplier_notes" OWNER TO "postgres";


COMMENT ON TABLE "public"."supplier_notes" IS 'Append-only dated relationship context and risk evidence for one supplier.';



CREATE TABLE IF NOT EXISTS "public"."supplier_offer_lines" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid",
    "offer_id" "uuid",
    "event_id" "uuid",
    "scope_line_id" "uuid",
    "line_number" integer NOT NULL,
    "offer_unit_price" numeric(15,4),
    "offer_quantity" numeric(15,2),
    "offer_extended_amount" numeric(15,2) DEFAULT 0,
    "offer_recurring_amount" numeric(15,2) DEFAULT 0,
    "offer_one_time_amount" numeric(15,2) DEFAULT 0,
    "offer_term_months" numeric(10,2),
    "annualized_offer_amount" numeric(15,2) DEFAULT 0,
    "compliance_status" "text" DEFAULT 'Compliant'::"text",
    "exclusion_notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "created_by" "uuid",
    "updated_by" "uuid",
    CONSTRAINT "chk_compliance_status" CHECK (("compliance_status" = ANY (ARRAY['Compliant'::"text", 'Non-Compliant'::"text", 'Conditional'::"text", 'Pending Review'::"text"]))),
    CONSTRAINT "supplier_offer_lines_compliance_status_check" CHECK (("compliance_status" = ANY (ARRAY['Compliant'::"text", 'Non-Compliant'::"text", 'Conditional'::"text", 'Pending Review'::"text"])))
);

ALTER TABLE ONLY "public"."supplier_offer_lines" FORCE ROW LEVEL SECURITY;


ALTER TABLE "public"."supplier_offer_lines" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."supplier_offers" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid",
    "event_id" "uuid",
    "supplier_id" "uuid",
    "offer_type" "text" DEFAULT 'Initial'::"text",
    "offer_round" integer DEFAULT 1,
    "offer_date" "date",
    "offer_currency_code" "text" DEFAULT 'USD'::"text",
    "fx_rate_to_usd" numeric(10,4) DEFAULT 1.0000,
    "offer_total_amount" numeric(15,2) DEFAULT 0,
    "offer_valid_until" "date",
    "compliant_bid_flag" boolean DEFAULT true,
    "selected_for_award_flag" boolean DEFAULT false,
    "source_document_id" "text",
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "created_by" "uuid",
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "updated_by" "uuid",
    "offer_term_months" numeric,
    "offer_role" "text",
    CONSTRAINT "chk_offer_role" CHECK ((("offer_role" IS NULL) OR ("offer_role" = ANY (ARRAY['opening'::"text", 'final'::"text"])))),
    CONSTRAINT "chk_offer_type" CHECK (("offer_type" = ANY (ARRAY['Initial'::"text", 'Revised'::"text", 'Best and Final (BAFO)'::"text", 'Counter'::"text", 'Final'::"text"])))
);

ALTER TABLE ONLY "public"."supplier_offers" FORCE ROW LEVEL SECURITY;


ALTER TABLE "public"."supplier_offers" OWNER TO "postgres";


COMMENT ON COLUMN "public"."supplier_offers"."offer_term_months" IS 'Term the offer_total_amount covers, in months. Used to derive a monthly rate. Any annual escalator should be priced into offer_total_amount. NULL means the term was not captured.';



COMMENT ON COLUMN "public"."supplier_offers"."offer_role" IS 'Role in the savings chain: opening (the vendor first ask, drives Cost Avoidance), final (what was signed, drives Cost Reduction), or NULL for other rounds. Marking an offer as final IS the award decision.';



CREATE TABLE IF NOT EXISTS "public"."supplier_performance_reviews" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid" NOT NULL,
    "supplier_id" "uuid" NOT NULL,
    "review_title" "text" NOT NULL,
    "review_date" "date" NOT NULL,
    "overall_score" smallint NOT NULL,
    "delivery_score" smallint,
    "quality_score" smallint,
    "commercial_score" smallint,
    "compliance_score" smallint,
    "summary" "text" NOT NULL,
    "next_review_date" "date",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "uuid",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "uuid",
    CONSTRAINT "supplier_performance_reviews_commercial_score_check" CHECK ((("commercial_score" IS NULL) OR (("commercial_score" >= 1) AND ("commercial_score" <= 5)))),
    CONSTRAINT "supplier_performance_reviews_compliance_score_check" CHECK ((("compliance_score" IS NULL) OR (("compliance_score" >= 1) AND ("compliance_score" <= 5)))),
    CONSTRAINT "supplier_performance_reviews_delivery_score_check" CHECK ((("delivery_score" IS NULL) OR (("delivery_score" >= 1) AND ("delivery_score" <= 5)))),
    CONSTRAINT "supplier_performance_reviews_next_date_check" CHECK ((("next_review_date" IS NULL) OR ("next_review_date" >= "review_date"))),
    CONSTRAINT "supplier_performance_reviews_overall_score_check" CHECK ((("overall_score" >= 1) AND ("overall_score" <= 5))),
    CONSTRAINT "supplier_performance_reviews_quality_score_check" CHECK ((("quality_score" IS NULL) OR (("quality_score" >= 1) AND ("quality_score" <= 5)))),
    CONSTRAINT "supplier_performance_reviews_summary_check" CHECK ((("char_length"("btrim"("summary")) >= 1) AND ("char_length"("btrim"("summary")) <= 10000))),
    CONSTRAINT "supplier_performance_reviews_title_check" CHECK ((("char_length"("btrim"("review_title")) >= 2) AND ("char_length"("btrim"("review_title")) <= 200)))
);

ALTER TABLE ONLY "public"."supplier_performance_reviews" FORCE ROW LEVEL SECURITY;


ALTER TABLE "public"."supplier_performance_reviews" OWNER TO "postgres";


COMMENT ON TABLE "public"."supplier_performance_reviews" IS 'Dated supplier performance reviews with a required overall score and optional unweighted category scores.';



CREATE TABLE IF NOT EXISTS "public"."supplier_risks" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid" NOT NULL,
    "supplier_id" "uuid" NOT NULL,
    "risk_title" "text" NOT NULL,
    "identified_on" "date" NOT NULL,
    "severity" "text" NOT NULL,
    "risk_status" "text" DEFAULT 'Open'::"text" NOT NULL,
    "description" "text" NOT NULL,
    "target_resolution_date" "date",
    "evidence_url" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "uuid",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "uuid",
    CONSTRAINT "supplier_risks_description_check" CHECK ((("char_length"("btrim"("description")) >= 1) AND ("char_length"("btrim"("description")) <= 10000))),
    CONSTRAINT "supplier_risks_severity_check" CHECK (("severity" = ANY (ARRAY['Low'::"text", 'Medium'::"text", 'High'::"text", 'Critical'::"text"]))),
    CONSTRAINT "supplier_risks_status_check" CHECK (("risk_status" = ANY (ARRAY['Open'::"text", 'Monitoring'::"text", 'Resolved'::"text"]))),
    CONSTRAINT "supplier_risks_target_date_check" CHECK ((("target_resolution_date" IS NULL) OR ("target_resolution_date" >= "identified_on"))),
    CONSTRAINT "supplier_risks_title_check" CHECK ((("char_length"("btrim"("risk_title")) >= 2) AND ("char_length"("btrim"("risk_title")) <= 200))),
    CONSTRAINT "supplier_risks_url_check" CHECK ((("evidence_url" IS NULL) OR (("char_length"("evidence_url") <= 2000) AND ("evidence_url" ~ '^https?://'::"text"))))
);

ALTER TABLE ONLY "public"."supplier_risks" FORCE ROW LEVEL SECURITY;


ALTER TABLE "public"."supplier_risks" OWNER TO "postgres";


COMMENT ON TABLE "public"."supplier_risks" IS 'Structured supplier risk evidence without automatic changes to the relationship-level risk rating.';



CREATE TABLE IF NOT EXISTS "public"."suppliers" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid",
    "supplier_name" "text" NOT NULL,
    "supplier_normalized_name" "text" DEFAULT ''::"text" NOT NULL,
    "supplier_status" "text" DEFAULT 'Active'::"text",
    "preferred_flag" boolean DEFAULT false,
    "diversity_flag" boolean DEFAULT false,
    "risk_rating" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "website" "text",
    "country_code" "text",
    "relationship_owner_id" "uuid",
    "next_review_date" "date",
    "notes" "text",
    CONSTRAINT "suppliers_country_code_check" CHECK ((("country_code" IS NULL) OR ("country_code" ~ '^[A-Z]{2}$'::"text"))),
    CONSTRAINT "suppliers_risk_rating_check" CHECK ((("risk_rating" = ANY (ARRAY['Low'::"text", 'Medium'::"text", 'High'::"text"])) OR ("risk_rating" IS NULL))),
    CONSTRAINT "suppliers_supplier_status_check" CHECK (("supplier_status" = ANY (ARRAY['Active'::"text", 'Inactive'::"text", 'Prospective'::"text", 'Blocked'::"text", 'Under Review'::"text"]))),
    CONSTRAINT "suppliers_website_url_check" CHECK ((("website" IS NULL) OR (("char_length"("website") <= 2000) AND ("website" ~* '^https?://'::"text"))))
);

ALTER TABLE ONLY "public"."suppliers" FORCE ROW LEVEL SECURITY;


ALTER TABLE "public"."suppliers" OWNER TO "postgres";


ALTER TABLE ONLY "public"."audit_log"
    ADD CONSTRAINT "audit_log_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."award_lines"
    ADD CONSTRAINT "award_lines_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."awards"
    ADD CONSTRAINT "awards_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."baseline_lines"
    ADD CONSTRAINT "baseline_lines_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."baselines"
    ADD CONSTRAINT "baselines_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."business_units"
    ADD CONSTRAINT "business_units_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."categories"
    ADD CONSTRAINT "categories_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."cost_centers"
    ADD CONSTRAINT "cost_centers_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."event_scope_lines"
    ADD CONSTRAINT "event_scope_lines_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."organization_settings"
    ADD CONSTRAINT "organization_settings_pkey" PRIMARY KEY ("organization_id");



ALTER TABLE ONLY "public"."organizations"
    ADD CONSTRAINT "organizations_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."project_choice_options"
    ADD CONSTRAINT "project_choice_options_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."project_updates"
    ADD CONSTRAINT "project_updates_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."realization_periods"
    ADD CONSTRAINT "realization_periods_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."savings_calculation_lines"
    ADD CONSTRAINT "savings_calculation_lines_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."savings_calculations"
    ADD CONSTRAINT "savings_calculations_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."savings_periods"
    ADD CONSTRAINT "savings_periods_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."sourcing_events"
    ADD CONSTRAINT "sourcing_events_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."supplier_certifications"
    ADD CONSTRAINT "supplier_certifications_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."supplier_contacts"
    ADD CONSTRAINT "supplier_contacts_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."supplier_notes"
    ADD CONSTRAINT "supplier_notes_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."supplier_offer_lines"
    ADD CONSTRAINT "supplier_offer_lines_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."supplier_offers"
    ADD CONSTRAINT "supplier_offers_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."supplier_performance_reviews"
    ADD CONSTRAINT "supplier_performance_reviews_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."supplier_risks"
    ADD CONSTRAINT "supplier_risks_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."suppliers"
    ADD CONSTRAINT "suppliers_id_organization_unique" UNIQUE ("id", "organization_id");



ALTER TABLE ONLY "public"."suppliers"
    ADD CONSTRAINT "suppliers_pkey" PRIMARY KEY ("id");



CREATE INDEX "idx_audit_log_actor" ON "public"."audit_log" USING "btree" ("actor_id");



CREATE INDEX "idx_audit_log_entity" ON "public"."audit_log" USING "btree" ("entity_type", "entity_id", "created_at" DESC);



CREATE INDEX "idx_audit_log_org_created" ON "public"."audit_log" USING "btree" ("organization_id", "created_at" DESC);



CREATE INDEX "idx_award_lines_award" ON "public"."award_lines" USING "btree" ("award_id");



CREATE INDEX "idx_award_lines_created_by" ON "public"."award_lines" USING "btree" ("created_by") WHERE ("created_by" IS NOT NULL);



CREATE INDEX "idx_award_lines_event" ON "public"."award_lines" USING "btree" ("event_id");



CREATE INDEX "idx_award_lines_org" ON "public"."award_lines" USING "btree" ("organization_id");



CREATE INDEX "idx_award_lines_updated_by" ON "public"."award_lines" USING "btree" ("updated_by") WHERE ("updated_by" IS NOT NULL);



CREATE INDEX "idx_awards_event" ON "public"."awards" USING "btree" ("event_id");



CREATE INDEX "idx_awards_offer" ON "public"."awards" USING "btree" ("offer_id");



CREATE INDEX "idx_awards_org" ON "public"."awards" USING "btree" ("organization_id");



CREATE INDEX "idx_baseline_lines_baseline" ON "public"."baseline_lines" USING "btree" ("baseline_id");



CREATE INDEX "idx_baseline_lines_created_by" ON "public"."baseline_lines" USING "btree" ("created_by") WHERE ("created_by" IS NOT NULL);



CREATE INDEX "idx_baseline_lines_event" ON "public"."baseline_lines" USING "btree" ("event_id");



CREATE INDEX "idx_baseline_lines_org" ON "public"."baseline_lines" USING "btree" ("organization_id");



CREATE INDEX "idx_baseline_lines_updated_by" ON "public"."baseline_lines" USING "btree" ("updated_by") WHERE ("updated_by" IS NOT NULL);



CREATE INDEX "idx_baselines_event" ON "public"."baselines" USING "btree" ("event_id");



CREATE INDEX "idx_baselines_org" ON "public"."baselines" USING "btree" ("organization_id");



CREATE INDEX "idx_business_units_org" ON "public"."business_units" USING "btree" ("organization_id");



CREATE INDEX "idx_categories_org" ON "public"."categories" USING "btree" ("organization_id");



CREATE INDEX "idx_cost_centers_org" ON "public"."cost_centers" USING "btree" ("organization_id");



CREATE INDEX "idx_event_scope_lines_created_by" ON "public"."event_scope_lines" USING "btree" ("created_by") WHERE ("created_by" IS NOT NULL);



CREATE INDEX "idx_event_scope_lines_event" ON "public"."event_scope_lines" USING "btree" ("event_id");



CREATE INDEX "idx_event_scope_lines_org" ON "public"."event_scope_lines" USING "btree" ("organization_id");



CREATE INDEX "idx_event_scope_lines_updated_by" ON "public"."event_scope_lines" USING "btree" ("updated_by") WHERE ("updated_by" IS NOT NULL);



CREATE INDEX "idx_organization_settings_updated_by" ON "public"."organization_settings" USING "btree" ("updated_by");



CREATE INDEX "idx_project_choice_options_org_active" ON "public"."project_choice_options" USING "btree" ("organization_id", "choice_type", "project_type", "active_flag", "sort_order", "label");



CREATE INDEX "idx_project_updates_created_by" ON "public"."project_updates" USING "btree" ("created_by");



CREATE INDEX "idx_project_updates_event_created" ON "public"."project_updates" USING "btree" ("event_id", "created_at" DESC);



CREATE INDEX "idx_project_updates_org_created" ON "public"."project_updates" USING "btree" ("organization_id", "created_at" DESC);



CREATE INDEX "idx_realization_periods_calc" ON "public"."realization_periods" USING "btree" ("savings_calculation_id");



CREATE INDEX "idx_realization_periods_event" ON "public"."realization_periods" USING "btree" ("event_id");



CREATE INDEX "idx_realization_periods_org" ON "public"."realization_periods" USING "btree" ("organization_id");



CREATE INDEX "idx_savings_calculation_lines_calc" ON "public"."savings_calculation_lines" USING "btree" ("savings_calculation_id");



CREATE INDEX "idx_savings_calculation_lines_created_by" ON "public"."savings_calculation_lines" USING "btree" ("created_by") WHERE ("created_by" IS NOT NULL);



CREATE INDEX "idx_savings_calculation_lines_updated_by" ON "public"."savings_calculation_lines" USING "btree" ("updated_by") WHERE ("updated_by" IS NOT NULL);



CREATE INDEX "idx_savings_calculations_award" ON "public"."savings_calculations" USING "btree" ("award_id");



CREATE INDEX "idx_savings_calculations_baseline" ON "public"."savings_calculations" USING "btree" ("baseline_id");



CREATE INDEX "idx_savings_calculations_event" ON "public"."savings_calculations" USING "btree" ("event_id");



CREATE INDEX "idx_savings_calculations_executed_by" ON "public"."savings_calculations" USING "btree" ("executed_by") WHERE ("executed_by" IS NOT NULL);



CREATE INDEX "idx_savings_calculations_org" ON "public"."savings_calculations" USING "btree" ("organization_id");



CREATE INDEX "idx_savings_periods_calc" ON "public"."savings_periods" USING "btree" ("savings_calculation_id");



CREATE INDEX "idx_savings_periods_event" ON "public"."savings_periods" USING "btree" ("event_id");



CREATE INDEX "idx_savings_periods_org" ON "public"."savings_periods" USING "btree" ("organization_id");



CREATE INDEX "idx_savings_periods_year" ON "public"."savings_periods" USING "btree" ("organization_id", "period_year");



CREATE INDEX "idx_sourcing_events_awarded" ON "public"."sourcing_events" USING "btree" ("awarded_supplier_id");



CREATE INDEX "idx_sourcing_events_bu" ON "public"."sourcing_events" USING "btree" ("business_unit_id");



CREATE INDEX "idx_sourcing_events_category" ON "public"."sourcing_events" USING "btree" ("category_id");



CREATE INDEX "idx_sourcing_events_incumbent" ON "public"."sourcing_events" USING "btree" ("incumbent_supplier_id");



CREATE INDEX "idx_sourcing_events_org" ON "public"."sourcing_events" USING "btree" ("organization_id");



CREATE INDEX "idx_sourcing_events_savings_disposition_by" ON "public"."sourcing_events" USING "btree" ("savings_disposition_by") WHERE ("savings_disposition_by" IS NOT NULL);



CREATE INDEX "idx_supplier_certifications_created_by" ON "public"."supplier_certifications" USING "btree" ("created_by");



CREATE INDEX "idx_supplier_certifications_updated_by" ON "public"."supplier_certifications" USING "btree" ("updated_by");



CREATE INDEX "idx_supplier_certifications_workspace_supplier_expiry" ON "public"."supplier_certifications" USING "btree" ("organization_id", "supplier_id", "expires_on", "certification_name");



CREATE INDEX "idx_supplier_contacts_created_by" ON "public"."supplier_contacts" USING "btree" ("created_by");



CREATE INDEX "idx_supplier_contacts_updated_by" ON "public"."supplier_contacts" USING "btree" ("updated_by");



CREATE INDEX "idx_supplier_contacts_workspace_supplier" ON "public"."supplier_contacts" USING "btree" ("organization_id", "supplier_id", "is_primary" DESC, "contact_name");



CREATE INDEX "idx_supplier_notes_created_by" ON "public"."supplier_notes" USING "btree" ("created_by");



CREATE INDEX "idx_supplier_notes_workspace_supplier_date" ON "public"."supplier_notes" USING "btree" ("organization_id", "supplier_id", "occurred_on" DESC, "created_at" DESC);



CREATE INDEX "idx_supplier_offer_lines_created_by" ON "public"."supplier_offer_lines" USING "btree" ("created_by") WHERE ("created_by" IS NOT NULL);



CREATE INDEX "idx_supplier_offer_lines_event" ON "public"."supplier_offer_lines" USING "btree" ("event_id");



CREATE INDEX "idx_supplier_offer_lines_offer" ON "public"."supplier_offer_lines" USING "btree" ("offer_id");



CREATE INDEX "idx_supplier_offer_lines_org" ON "public"."supplier_offer_lines" USING "btree" ("organization_id");



CREATE INDEX "idx_supplier_offer_lines_updated_by" ON "public"."supplier_offer_lines" USING "btree" ("updated_by") WHERE ("updated_by" IS NOT NULL);



CREATE INDEX "idx_supplier_offers_event" ON "public"."supplier_offers" USING "btree" ("event_id");



CREATE INDEX "idx_supplier_offers_org" ON "public"."supplier_offers" USING "btree" ("organization_id");



CREATE INDEX "idx_supplier_performance_reviews_created_by" ON "public"."supplier_performance_reviews" USING "btree" ("created_by");



CREATE INDEX "idx_supplier_performance_reviews_supplier_workspace" ON "public"."supplier_performance_reviews" USING "btree" ("supplier_id", "organization_id");



CREATE INDEX "idx_supplier_performance_reviews_updated_by" ON "public"."supplier_performance_reviews" USING "btree" ("updated_by");



CREATE INDEX "idx_supplier_performance_reviews_workspace_supplier_date" ON "public"."supplier_performance_reviews" USING "btree" ("organization_id", "supplier_id", "review_date" DESC, "created_at" DESC);



CREATE INDEX "idx_supplier_risks_created_by" ON "public"."supplier_risks" USING "btree" ("created_by");



CREATE INDEX "idx_supplier_risks_supplier_workspace" ON "public"."supplier_risks" USING "btree" ("supplier_id", "organization_id");



CREATE INDEX "idx_supplier_risks_updated_by" ON "public"."supplier_risks" USING "btree" ("updated_by");



CREATE INDEX "idx_supplier_risks_workspace_supplier_status" ON "public"."supplier_risks" USING "btree" ("organization_id", "supplier_id", "risk_status", "severity", "identified_on" DESC);



CREATE INDEX "idx_suppliers_org" ON "public"."suppliers" USING "btree" ("organization_id");



CREATE INDEX "idx_suppliers_relationship_owner" ON "public"."suppliers" USING "btree" ("relationship_owner_id");



CREATE UNIQUE INDEX "project_choice_options_one_savings_completion_status" ON "public"."project_choice_options" USING "btree" ("organization_id", "project_type") WHERE "requires_savings_disposition";



CREATE UNIQUE INDEX "uq_baselines_official_cost_avoidance" ON "public"."baselines" USING "btree" ("event_id") WHERE "official_for_cost_avoidance";



CREATE UNIQUE INDEX "uq_baselines_official_demand_reduction" ON "public"."baselines" USING "btree" ("event_id") WHERE "official_for_demand_reduction";



CREATE UNIQUE INDEX "uq_baselines_official_hard_savings" ON "public"."baselines" USING "btree" ("event_id") WHERE "official_for_hard_savings";



CREATE UNIQUE INDEX "uq_baselines_selected" ON "public"."baselines" USING "btree" ("event_id") WHERE "is_selected";



CREATE UNIQUE INDEX "uq_business_units_org_normalized_name" ON "public"."business_units" USING "btree" ("organization_id", "lower"("btrim"("business_unit_name"))) WHERE ("organization_id" IS NOT NULL);



CREATE UNIQUE INDEX "uq_categories_org_normalized_name" ON "public"."categories" USING "btree" ("organization_id", "lower"("btrim"("category_name"))) WHERE ("organization_id" IS NOT NULL);



CREATE UNIQUE INDEX "uq_cost_centers_org_normalized_name" ON "public"."cost_centers" USING "btree" ("organization_id", "lower"("btrim"("cost_center_name"))) WHERE ("organization_id" IS NOT NULL);



CREATE UNIQUE INDEX "uq_offers_final" ON "public"."supplier_offers" USING "btree" ("event_id") WHERE ("offer_role" = 'final'::"text");



CREATE UNIQUE INDEX "uq_offers_opening" ON "public"."supplier_offers" USING "btree" ("event_id") WHERE ("offer_role" = 'opening'::"text");



CREATE UNIQUE INDEX "uq_organizations_demo_template" ON "public"."organizations" USING "btree" ("is_demo_template") WHERE "is_demo_template";



CREATE UNIQUE INDEX "uq_project_choice_options_org_type_label" ON "public"."project_choice_options" USING "btree" ("organization_id", "choice_type", COALESCE("project_type", ''::"text"), "lower"("btrim"("label")));



CREATE UNIQUE INDEX "uq_realization_periods_savings_period" ON "public"."realization_periods" USING "btree" ("savings_period_id") WHERE ("savings_period_id" IS NOT NULL);



CREATE UNIQUE INDEX "uq_savings_calculations_event" ON "public"."savings_calculations" USING "btree" ("event_id") WHERE ("event_id" IS NOT NULL);



CREATE UNIQUE INDEX "uq_savings_periods_calc_number" ON "public"."savings_periods" USING "btree" ("savings_calculation_id", "period_number");



CREATE UNIQUE INDEX "uq_supplier_contacts_primary" ON "public"."supplier_contacts" USING "btree" ("supplier_id") WHERE "is_primary";



CREATE UNIQUE INDEX "uq_supplier_offers_selected_award" ON "public"."supplier_offers" USING "btree" ("event_id") WHERE "selected_for_award_flag";



CREATE UNIQUE INDEX "uq_suppliers_org_normalized_name" ON "public"."suppliers" USING "btree" ("organization_id", "supplier_normalized_name");



CREATE OR REPLACE TRIGGER "award_lines_actor" BEFORE INSERT OR UPDATE ON "public"."award_lines" FOR EACH ROW EXECUTE FUNCTION "public"."stamp_money_record_actor"();



CREATE OR REPLACE TRIGGER "award_lines_updated_at" BEFORE UPDATE ON "public"."award_lines" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at"();



CREATE OR REPLACE TRIGGER "awards_actor" BEFORE INSERT OR UPDATE ON "public"."awards" FOR EACH ROW EXECUTE FUNCTION "public"."stamp_money_record_actor"();



CREATE OR REPLACE TRIGGER "awards_updated_at" BEFORE UPDATE ON "public"."awards" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at"();



CREATE OR REPLACE TRIGGER "baseline_lines_actor" BEFORE INSERT OR UPDATE ON "public"."baseline_lines" FOR EACH ROW EXECUTE FUNCTION "public"."stamp_money_record_actor"();



CREATE OR REPLACE TRIGGER "baseline_lines_updated_at" BEFORE UPDATE ON "public"."baseline_lines" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at"();



CREATE OR REPLACE TRIGGER "baselines_actor" BEFORE INSERT OR UPDATE ON "public"."baselines" FOR EACH ROW EXECUTE FUNCTION "public"."stamp_money_record_actor"();



CREATE OR REPLACE TRIGGER "baselines_updated_at" BEFORE UPDATE ON "public"."baselines" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at"();



CREATE OR REPLACE TRIGGER "business_units_audit" AFTER INSERT OR DELETE OR UPDATE ON "public"."business_units" FOR EACH ROW EXECUTE FUNCTION "public"."capture_workspace_audit"();



CREATE OR REPLACE TRIGGER "categories_audit" AFTER INSERT OR DELETE OR UPDATE ON "public"."categories" FOR EACH ROW EXECUTE FUNCTION "public"."capture_workspace_audit"();



CREATE OR REPLACE TRIGGER "cost_centers_audit" AFTER INSERT OR DELETE OR UPDATE ON "public"."cost_centers" FOR EACH ROW EXECUTE FUNCTION "public"."capture_workspace_audit"();



CREATE OR REPLACE TRIGGER "event_scope_lines_actor" BEFORE INSERT OR UPDATE ON "public"."event_scope_lines" FOR EACH ROW EXECUTE FUNCTION "public"."stamp_money_record_actor"();



CREATE OR REPLACE TRIGGER "organization_settings_audit" AFTER INSERT OR DELETE OR UPDATE ON "public"."organization_settings" FOR EACH ROW EXECUTE FUNCTION "public"."capture_workspace_audit"();



CREATE OR REPLACE TRIGGER "organization_settings_updated_at" BEFORE UPDATE ON "public"."organization_settings" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at"();



CREATE OR REPLACE TRIGGER "organizations_audit" AFTER UPDATE ON "public"."organizations" FOR EACH ROW EXECUTE FUNCTION "public"."capture_workspace_audit"();



CREATE OR REPLACE TRIGGER "project_choice_options_audit" AFTER INSERT OR DELETE OR UPDATE ON "public"."project_choice_options" FOR EACH ROW EXECUTE FUNCTION "public"."capture_workspace_audit"();



CREATE OR REPLACE TRIGGER "project_choice_options_cascade_rename" AFTER UPDATE OF "label" ON "public"."project_choice_options" FOR EACH ROW EXECUTE FUNCTION "public"."cascade_project_choice_rename"();



CREATE OR REPLACE TRIGGER "project_choice_options_normalize" BEFORE INSERT OR UPDATE ON "public"."project_choice_options" FOR EACH ROW EXECUTE FUNCTION "public"."normalize_project_choice_option"();



CREATE OR REPLACE TRIGGER "project_choice_options_prevent_last_archive" BEFORE UPDATE OF "active_flag" ON "public"."project_choice_options" FOR EACH ROW EXECUTE FUNCTION "public"."prevent_last_project_choice_archive"();



CREATE OR REPLACE TRIGGER "project_choice_options_protect_sourcing_completion" BEFORE INSERT OR UPDATE ON "public"."project_choice_options" FOR EACH ROW EXECUTE FUNCTION "public"."protect_sourcing_completion_status"();



CREATE OR REPLACE TRIGGER "project_choice_options_updated_at" BEFORE UPDATE ON "public"."project_choice_options" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at"();



CREATE OR REPLACE TRIGGER "project_updates_enforce_workspace_setting" BEFORE INSERT ON "public"."project_updates" FOR EACH ROW EXECUTE FUNCTION "public"."enforce_project_updates_setting"();



CREATE OR REPLACE TRIGGER "realization_periods_actor" BEFORE INSERT OR UPDATE ON "public"."realization_periods" FOR EACH ROW EXECUTE FUNCTION "public"."stamp_money_record_actor"();



CREATE OR REPLACE TRIGGER "realization_periods_audit" AFTER INSERT OR DELETE OR UPDATE ON "public"."realization_periods" FOR EACH ROW EXECUTE FUNCTION "public"."capture_workspace_audit"();



CREATE OR REPLACE TRIGGER "realization_periods_derive_per_leg_fields" BEFORE INSERT OR UPDATE ON "public"."realization_periods" FOR EACH ROW EXECUTE FUNCTION "public"."derive_realization_period_fields"();



CREATE OR REPLACE TRIGGER "realization_periods_setting_guard" BEFORE INSERT OR DELETE OR UPDATE ON "public"."realization_periods" FOR EACH ROW EXECUTE FUNCTION "public"."enforce_savings_realization_setting"();



CREATE OR REPLACE TRIGGER "realization_periods_sourcing_only_guard" BEFORE INSERT OR UPDATE OF "organization_id", "event_id", "savings_calculation_id" ON "public"."realization_periods" FOR EACH ROW EXECUTE FUNCTION "public"."enforce_sourcing_project_savings"();



CREATE OR REPLACE TRIGGER "realization_periods_updated_at" BEFORE UPDATE ON "public"."realization_periods" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at"();



CREATE OR REPLACE TRIGGER "savings_calculation_lines_actor" BEFORE INSERT OR UPDATE ON "public"."savings_calculation_lines" FOR EACH ROW EXECUTE FUNCTION "public"."stamp_money_record_actor"();



CREATE OR REPLACE TRIGGER "savings_calculation_lines_sourcing_only_guard" BEFORE INSERT OR UPDATE OF "organization_id", "event_id", "savings_calculation_id" ON "public"."savings_calculation_lines" FOR EACH ROW EXECUTE FUNCTION "public"."enforce_sourcing_project_savings"();



CREATE OR REPLACE TRIGGER "savings_calculation_lines_updated_at" BEFORE UPDATE ON "public"."savings_calculation_lines" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at"();



CREATE OR REPLACE TRIGGER "savings_calculations_actor" BEFORE INSERT OR UPDATE ON "public"."savings_calculations" FOR EACH ROW EXECUTE FUNCTION "public"."stamp_money_record_actor"();



CREATE OR REPLACE TRIGGER "savings_calculations_audit" AFTER INSERT OR DELETE OR UPDATE ON "public"."savings_calculations" FOR EACH ROW EXECUTE FUNCTION "public"."capture_workspace_audit"();



CREATE CONSTRAINT TRIGGER "savings_calculations_completion_invariant" AFTER INSERT OR DELETE OR UPDATE ON "public"."savings_calculations" DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION "public"."enforce_savings_completion_invariant"();



CREATE CONSTRAINT TRIGGER "savings_calculations_execution_invariant" AFTER INSERT OR DELETE OR UPDATE ON "public"."savings_calculations" DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION "public"."enforce_savings_execution_invariant"();



CREATE OR REPLACE TRIGGER "savings_calculations_realization_retention_guard" BEFORE DELETE ON "public"."savings_calculations" FOR EACH ROW EXECUTE FUNCTION "public"."prevent_realization_history_delete"();



CREATE OR REPLACE TRIGGER "savings_calculations_sourcing_only_guard" BEFORE INSERT OR UPDATE OF "organization_id", "event_id" ON "public"."savings_calculations" FOR EACH ROW EXECUTE FUNCTION "public"."enforce_sourcing_project_savings"();



CREATE OR REPLACE TRIGGER "savings_calculations_updated_at" BEFORE UPDATE ON "public"."savings_calculations" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at"();



CREATE OR REPLACE TRIGGER "savings_periods_actor" BEFORE INSERT OR UPDATE ON "public"."savings_periods" FOR EACH ROW EXECUTE FUNCTION "public"."stamp_money_record_actor"();



CREATE OR REPLACE TRIGGER "savings_periods_audit" AFTER INSERT OR DELETE OR UPDATE ON "public"."savings_periods" FOR EACH ROW EXECUTE FUNCTION "public"."capture_workspace_audit"();



CREATE CONSTRAINT TRIGGER "savings_periods_execution_invariant" AFTER INSERT OR DELETE OR UPDATE ON "public"."savings_periods" DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION "public"."enforce_savings_execution_invariant"();



CREATE OR REPLACE TRIGGER "savings_periods_sourcing_only_guard" BEFORE INSERT OR UPDATE OF "organization_id", "event_id", "savings_calculation_id" ON "public"."savings_periods" FOR EACH ROW EXECUTE FUNCTION "public"."enforce_sourcing_project_savings"();



CREATE OR REPLACE TRIGGER "sourcing_events_actor" BEFORE INSERT OR UPDATE ON "public"."sourcing_events" FOR EACH ROW EXECUTE FUNCTION "public"."stamp_money_record_actor"();



CREATE OR REPLACE TRIGGER "sourcing_events_completion_savings_guard" BEFORE INSERT OR UPDATE OF "event_status", "project_type", "savings_disposition", "savings_disposition_reason" ON "public"."sourcing_events" FOR EACH ROW EXECUTE FUNCTION "public"."enforce_completed_project_savings_disposition"();



CREATE OR REPLACE TRIGGER "sourcing_events_enforce_incumbent_supplier_setting" BEFORE INSERT OR UPDATE OF "incumbent_supplier_id" ON "public"."sourcing_events" FOR EACH ROW EXECUTE FUNCTION "public"."enforce_project_incumbent_supplier_setting"();



CREATE OR REPLACE TRIGGER "sourcing_events_enforce_project_business_unit_setting" BEFORE INSERT OR UPDATE ON "public"."sourcing_events" FOR EACH ROW EXECUTE FUNCTION "public"."enforce_project_business_unit_setting"();



CREATE OR REPLACE TRIGGER "sourcing_events_enforce_project_category_setting" BEFORE INSERT OR UPDATE ON "public"."sourcing_events" FOR EACH ROW EXECUTE FUNCTION "public"."enforce_project_category_setting"();



CREATE OR REPLACE TRIGGER "sourcing_events_enforce_project_cost_center_setting" BEFORE INSERT OR UPDATE ON "public"."sourcing_events" FOR EACH ROW EXECUTE FUNCTION "public"."enforce_project_cost_center_setting"();



CREATE OR REPLACE TRIGGER "sourcing_events_enforce_project_description_setting" BEFORE INSERT OR UPDATE ON "public"."sourcing_events" FOR EACH ROW EXECUTE FUNCTION "public"."enforce_project_description_setting"();



CREATE OR REPLACE TRIGGER "sourcing_events_enforce_project_owner_setting" BEFORE INSERT OR UPDATE ON "public"."sourcing_events" FOR EACH ROW EXECUTE FUNCTION "public"."enforce_project_owner_setting"();



CREATE OR REPLACE TRIGGER "sourcing_events_enforce_support_project_setting" BEFORE INSERT OR UPDATE ON "public"."sourcing_events" FOR EACH ROW EXECUTE FUNCTION "public"."enforce_support_project_setting"();



CREATE OR REPLACE TRIGGER "sourcing_events_realization_retention_guard" BEFORE DELETE ON "public"."sourcing_events" FOR EACH ROW EXECUTE FUNCTION "public"."prevent_realization_history_delete"();



CREATE CONSTRAINT TRIGGER "sourcing_events_savings_completion_invariant" AFTER INSERT OR DELETE OR UPDATE ON "public"."sourcing_events" DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION "public"."enforce_savings_completion_invariant"();



CREATE OR REPLACE TRIGGER "sourcing_events_savings_disposition_audit" AFTER DELETE OR UPDATE OF "savings_disposition", "savings_disposition_reason", "savings_disposition_at", "savings_disposition_by" ON "public"."sourcing_events" FOR EACH ROW EXECUTE FUNCTION "public"."capture_workspace_audit"();



CREATE OR REPLACE TRIGGER "sourcing_events_savings_population_guard" BEFORE UPDATE OF "project_type" ON "public"."sourcing_events" FOR EACH ROW EXECUTE FUNCTION "public"."enforce_sourcing_project_savings"();



CREATE OR REPLACE TRIGGER "supplier_certifications_audit" AFTER INSERT OR DELETE OR UPDATE ON "public"."supplier_certifications" FOR EACH ROW EXECUTE FUNCTION "public"."capture_workspace_audit"();



CREATE OR REPLACE TRIGGER "supplier_certifications_stamp_actor" BEFORE INSERT OR UPDATE ON "public"."supplier_certifications" FOR EACH ROW EXECUTE FUNCTION "public"."stamp_supplier_certification_actor"();



CREATE OR REPLACE TRIGGER "supplier_certifications_updated_at" BEFORE UPDATE ON "public"."supplier_certifications" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at"();



CREATE OR REPLACE TRIGGER "supplier_contacts_audit" AFTER INSERT OR DELETE OR UPDATE ON "public"."supplier_contacts" FOR EACH ROW EXECUTE FUNCTION "public"."capture_workspace_audit"();



CREATE OR REPLACE TRIGGER "supplier_contacts_single_primary" BEFORE INSERT OR UPDATE OF "is_primary" ON "public"."supplier_contacts" FOR EACH ROW EXECUTE FUNCTION "public"."set_single_primary_supplier_contact"();



CREATE OR REPLACE TRIGGER "supplier_contacts_stamp_actor" BEFORE INSERT OR UPDATE ON "public"."supplier_contacts" FOR EACH ROW EXECUTE FUNCTION "public"."stamp_supplier_contact_actor"();



CREATE OR REPLACE TRIGGER "supplier_contacts_updated_at" BEFORE UPDATE ON "public"."supplier_contacts" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at"();



CREATE OR REPLACE TRIGGER "supplier_notes_stamp_actor" BEFORE INSERT ON "public"."supplier_notes" FOR EACH ROW EXECUTE FUNCTION "public"."stamp_supplier_note_actor"();



CREATE OR REPLACE TRIGGER "supplier_offer_lines_actor" BEFORE INSERT OR UPDATE ON "public"."supplier_offer_lines" FOR EACH ROW EXECUTE FUNCTION "public"."stamp_money_record_actor"();



CREATE OR REPLACE TRIGGER "supplier_offer_lines_updated_at" BEFORE UPDATE ON "public"."supplier_offer_lines" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at"();



CREATE OR REPLACE TRIGGER "supplier_offers_actor" BEFORE INSERT OR UPDATE ON "public"."supplier_offers" FOR EACH ROW EXECUTE FUNCTION "public"."stamp_money_record_actor"();



CREATE OR REPLACE TRIGGER "supplier_offers_updated_at" BEFORE UPDATE ON "public"."supplier_offers" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at"();



CREATE OR REPLACE TRIGGER "supplier_performance_reviews_audit" AFTER INSERT OR DELETE OR UPDATE ON "public"."supplier_performance_reviews" FOR EACH ROW EXECUTE FUNCTION "public"."capture_workspace_audit"();



CREATE OR REPLACE TRIGGER "supplier_performance_reviews_stamp_actor" BEFORE INSERT OR UPDATE ON "public"."supplier_performance_reviews" FOR EACH ROW EXECUTE FUNCTION "public"."stamp_supplier_performance_review_actor"();



CREATE OR REPLACE TRIGGER "supplier_performance_reviews_updated_at" BEFORE UPDATE ON "public"."supplier_performance_reviews" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at"();



CREATE OR REPLACE TRIGGER "supplier_risks_audit" AFTER INSERT OR DELETE OR UPDATE ON "public"."supplier_risks" FOR EACH ROW EXECUTE FUNCTION "public"."capture_workspace_audit"();



CREATE OR REPLACE TRIGGER "supplier_risks_stamp_actor" BEFORE INSERT OR UPDATE ON "public"."supplier_risks" FOR EACH ROW EXECUTE FUNCTION "public"."stamp_supplier_risk_actor"();



CREATE OR REPLACE TRIGGER "supplier_risks_updated_at" BEFORE UPDATE ON "public"."supplier_risks" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at"();



CREATE OR REPLACE TRIGGER "suppliers_audit" AFTER INSERT OR DELETE OR UPDATE ON "public"."suppliers" FOR EACH ROW EXECUTE FUNCTION "public"."capture_workspace_audit"();



CREATE OR REPLACE TRIGGER "suppliers_normalize_name" BEFORE INSERT OR UPDATE ON "public"."suppliers" FOR EACH ROW EXECUTE FUNCTION "public"."set_supplier_normalized_name"();



CREATE OR REPLACE TRIGGER "suppliers_updated_at" BEFORE UPDATE ON "public"."suppliers" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at"();



CREATE OR REPLACE TRIGGER "trg_prevent_profile_privilege_change" BEFORE UPDATE ON "public"."profiles" FOR EACH ROW EXECUTE FUNCTION "public"."prevent_profile_privilege_change"();



CREATE OR REPLACE TRIGGER "zz_sourcing_events_enforce_project_choice_options" BEFORE INSERT OR UPDATE ON "public"."sourcing_events" FOR EACH ROW EXECUTE FUNCTION "public"."enforce_project_choice_options"();



ALTER TABLE ONLY "public"."audit_log"
    ADD CONSTRAINT "audit_log_actor_id_fkey" FOREIGN KEY ("actor_id") REFERENCES "public"."profiles"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."audit_log"
    ADD CONSTRAINT "audit_log_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."award_lines"
    ADD CONSTRAINT "award_lines_award_id_fkey" FOREIGN KEY ("award_id") REFERENCES "public"."awards"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."award_lines"
    ADD CONSTRAINT "award_lines_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "public"."profiles"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."award_lines"
    ADD CONSTRAINT "award_lines_event_id_fkey" FOREIGN KEY ("event_id") REFERENCES "public"."sourcing_events"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."award_lines"
    ADD CONSTRAINT "award_lines_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id");



ALTER TABLE ONLY "public"."award_lines"
    ADD CONSTRAINT "award_lines_scope_line_id_fkey" FOREIGN KEY ("scope_line_id") REFERENCES "public"."event_scope_lines"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."award_lines"
    ADD CONSTRAINT "award_lines_updated_by_fkey" FOREIGN KEY ("updated_by") REFERENCES "public"."profiles"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."awards"
    ADD CONSTRAINT "awards_award_approved_by_fkey" FOREIGN KEY ("award_approved_by") REFERENCES "public"."profiles"("id");



ALTER TABLE ONLY "public"."awards"
    ADD CONSTRAINT "awards_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "public"."profiles"("id");



ALTER TABLE ONLY "public"."awards"
    ADD CONSTRAINT "awards_event_id_fkey" FOREIGN KEY ("event_id") REFERENCES "public"."sourcing_events"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."awards"
    ADD CONSTRAINT "awards_offer_id_fkey" FOREIGN KEY ("offer_id") REFERENCES "public"."supplier_offers"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."awards"
    ADD CONSTRAINT "awards_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id");



ALTER TABLE ONLY "public"."awards"
    ADD CONSTRAINT "awards_supplier_id_fkey" FOREIGN KEY ("supplier_id") REFERENCES "public"."suppliers"("id");



ALTER TABLE ONLY "public"."awards"
    ADD CONSTRAINT "awards_updated_by_fkey" FOREIGN KEY ("updated_by") REFERENCES "public"."profiles"("id");



ALTER TABLE ONLY "public"."baseline_lines"
    ADD CONSTRAINT "baseline_lines_baseline_id_fkey" FOREIGN KEY ("baseline_id") REFERENCES "public"."baselines"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."baseline_lines"
    ADD CONSTRAINT "baseline_lines_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "public"."profiles"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."baseline_lines"
    ADD CONSTRAINT "baseline_lines_event_id_fkey" FOREIGN KEY ("event_id") REFERENCES "public"."sourcing_events"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."baseline_lines"
    ADD CONSTRAINT "baseline_lines_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id");



ALTER TABLE ONLY "public"."baseline_lines"
    ADD CONSTRAINT "baseline_lines_scope_line_id_fkey" FOREIGN KEY ("scope_line_id") REFERENCES "public"."event_scope_lines"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."baseline_lines"
    ADD CONSTRAINT "baseline_lines_updated_by_fkey" FOREIGN KEY ("updated_by") REFERENCES "public"."profiles"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."baselines"
    ADD CONSTRAINT "baselines_baseline_approved_by_fkey" FOREIGN KEY ("baseline_approved_by") REFERENCES "public"."profiles"("id");



ALTER TABLE ONLY "public"."baselines"
    ADD CONSTRAINT "baselines_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "public"."profiles"("id");



ALTER TABLE ONLY "public"."baselines"
    ADD CONSTRAINT "baselines_event_id_fkey" FOREIGN KEY ("event_id") REFERENCES "public"."sourcing_events"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."baselines"
    ADD CONSTRAINT "baselines_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id");



ALTER TABLE ONLY "public"."baselines"
    ADD CONSTRAINT "baselines_updated_by_fkey" FOREIGN KEY ("updated_by") REFERENCES "public"."profiles"("id");



ALTER TABLE ONLY "public"."business_units"
    ADD CONSTRAINT "business_units_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id");



ALTER TABLE ONLY "public"."business_units"
    ADD CONSTRAINT "business_units_parent_business_unit_id_fkey" FOREIGN KEY ("parent_business_unit_id") REFERENCES "public"."business_units"("id");



ALTER TABLE ONLY "public"."categories"
    ADD CONSTRAINT "categories_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id");



ALTER TABLE ONLY "public"."categories"
    ADD CONSTRAINT "categories_parent_category_id_fkey" FOREIGN KEY ("parent_category_id") REFERENCES "public"."categories"("id");



ALTER TABLE ONLY "public"."cost_centers"
    ADD CONSTRAINT "cost_centers_business_unit_id_fkey" FOREIGN KEY ("business_unit_id") REFERENCES "public"."business_units"("id");



ALTER TABLE ONLY "public"."cost_centers"
    ADD CONSTRAINT "cost_centers_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id");



ALTER TABLE ONLY "public"."event_scope_lines"
    ADD CONSTRAINT "event_scope_lines_business_equivalency_confirmed_by_fkey" FOREIGN KEY ("business_equivalency_confirmed_by") REFERENCES "public"."profiles"("id");



ALTER TABLE ONLY "public"."event_scope_lines"
    ADD CONSTRAINT "event_scope_lines_category_id_fkey" FOREIGN KEY ("category_id") REFERENCES "public"."categories"("id");



ALTER TABLE ONLY "public"."event_scope_lines"
    ADD CONSTRAINT "event_scope_lines_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "public"."profiles"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."event_scope_lines"
    ADD CONSTRAINT "event_scope_lines_event_id_fkey" FOREIGN KEY ("event_id") REFERENCES "public"."sourcing_events"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."event_scope_lines"
    ADD CONSTRAINT "event_scope_lines_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id");



ALTER TABLE ONLY "public"."event_scope_lines"
    ADD CONSTRAINT "event_scope_lines_updated_by_fkey" FOREIGN KEY ("updated_by") REFERENCES "public"."profiles"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."organization_settings"
    ADD CONSTRAINT "organization_settings_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."organization_settings"
    ADD CONSTRAINT "organization_settings_updated_by_fkey" FOREIGN KEY ("updated_by") REFERENCES "public"."profiles"("id");



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_id_fkey" FOREIGN KEY ("id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id");



ALTER TABLE ONLY "public"."project_choice_options"
    ADD CONSTRAINT "project_choice_options_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "public"."profiles"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."project_choice_options"
    ADD CONSTRAINT "project_choice_options_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."project_choice_options"
    ADD CONSTRAINT "project_choice_options_updated_by_fkey" FOREIGN KEY ("updated_by") REFERENCES "public"."profiles"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."project_updates"
    ADD CONSTRAINT "project_updates_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "public"."profiles"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."project_updates"
    ADD CONSTRAINT "project_updates_event_id_fkey" FOREIGN KEY ("event_id") REFERENCES "public"."sourcing_events"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."project_updates"
    ADD CONSTRAINT "project_updates_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."realization_periods"
    ADD CONSTRAINT "realization_periods_comparison_rebased_by_fkey" FOREIGN KEY ("comparison_rebased_by") REFERENCES "public"."profiles"("id");



ALTER TABLE ONLY "public"."realization_periods"
    ADD CONSTRAINT "realization_periods_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "public"."profiles"("id");



ALTER TABLE ONLY "public"."realization_periods"
    ADD CONSTRAINT "realization_periods_event_id_fkey" FOREIGN KEY ("event_id") REFERENCES "public"."sourcing_events"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."realization_periods"
    ADD CONSTRAINT "realization_periods_finance_validated_by_fkey" FOREIGN KEY ("finance_validated_by") REFERENCES "public"."profiles"("id");



ALTER TABLE ONLY "public"."realization_periods"
    ADD CONSTRAINT "realization_periods_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id");



ALTER TABLE ONLY "public"."realization_periods"
    ADD CONSTRAINT "realization_periods_savings_calculation_id_fkey" FOREIGN KEY ("savings_calculation_id") REFERENCES "public"."savings_calculations"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."realization_periods"
    ADD CONSTRAINT "realization_periods_savings_period_id_fkey" FOREIGN KEY ("savings_period_id") REFERENCES "public"."savings_periods"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."realization_periods"
    ADD CONSTRAINT "realization_periods_updated_by_fkey" FOREIGN KEY ("updated_by") REFERENCES "public"."profiles"("id");



ALTER TABLE ONLY "public"."savings_calculation_lines"
    ADD CONSTRAINT "savings_calculation_lines_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "public"."profiles"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."savings_calculation_lines"
    ADD CONSTRAINT "savings_calculation_lines_event_id_fkey" FOREIGN KEY ("event_id") REFERENCES "public"."sourcing_events"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."savings_calculation_lines"
    ADD CONSTRAINT "savings_calculation_lines_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id");



ALTER TABLE ONLY "public"."savings_calculation_lines"
    ADD CONSTRAINT "savings_calculation_lines_savings_calculation_id_fkey" FOREIGN KEY ("savings_calculation_id") REFERENCES "public"."savings_calculations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."savings_calculation_lines"
    ADD CONSTRAINT "savings_calculation_lines_scope_line_id_fkey" FOREIGN KEY ("scope_line_id") REFERENCES "public"."event_scope_lines"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."savings_calculation_lines"
    ADD CONSTRAINT "savings_calculation_lines_updated_by_fkey" FOREIGN KEY ("updated_by") REFERENCES "public"."profiles"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."savings_calculations"
    ADD CONSTRAINT "savings_calculations_award_id_fkey" FOREIGN KEY ("award_id") REFERENCES "public"."awards"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."savings_calculations"
    ADD CONSTRAINT "savings_calculations_baseline_id_fkey" FOREIGN KEY ("baseline_id") REFERENCES "public"."baselines"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."savings_calculations"
    ADD CONSTRAINT "savings_calculations_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "public"."profiles"("id");



ALTER TABLE ONLY "public"."savings_calculations"
    ADD CONSTRAINT "savings_calculations_event_id_fkey" FOREIGN KEY ("event_id") REFERENCES "public"."sourcing_events"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."savings_calculations"
    ADD CONSTRAINT "savings_calculations_executed_by_fkey" FOREIGN KEY ("executed_by") REFERENCES "public"."profiles"("id");



ALTER TABLE ONLY "public"."savings_calculations"
    ADD CONSTRAINT "savings_calculations_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id");



ALTER TABLE ONLY "public"."savings_calculations"
    ADD CONSTRAINT "savings_calculations_updated_by_fkey" FOREIGN KEY ("updated_by") REFERENCES "public"."profiles"("id");



ALTER TABLE ONLY "public"."savings_periods"
    ADD CONSTRAINT "savings_periods_event_id_fkey" FOREIGN KEY ("event_id") REFERENCES "public"."sourcing_events"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."savings_periods"
    ADD CONSTRAINT "savings_periods_savings_calculation_id_fkey" FOREIGN KEY ("savings_calculation_id") REFERENCES "public"."savings_calculations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."sourcing_events"
    ADD CONSTRAINT "sourcing_events_awarded_supplier_id_fkey" FOREIGN KEY ("awarded_supplier_id") REFERENCES "public"."suppliers"("id");



ALTER TABLE ONLY "public"."sourcing_events"
    ADD CONSTRAINT "sourcing_events_business_owner_id_fkey" FOREIGN KEY ("business_owner_id") REFERENCES "public"."profiles"("id");



ALTER TABLE ONLY "public"."sourcing_events"
    ADD CONSTRAINT "sourcing_events_business_unit_id_fkey" FOREIGN KEY ("business_unit_id") REFERENCES "public"."business_units"("id");



ALTER TABLE ONLY "public"."sourcing_events"
    ADD CONSTRAINT "sourcing_events_category_id_fkey" FOREIGN KEY ("category_id") REFERENCES "public"."categories"("id");



ALTER TABLE ONLY "public"."sourcing_events"
    ADD CONSTRAINT "sourcing_events_cost_center_id_fkey" FOREIGN KEY ("cost_center_id") REFERENCES "public"."cost_centers"("id");



ALTER TABLE ONLY "public"."sourcing_events"
    ADD CONSTRAINT "sourcing_events_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "public"."profiles"("id");



ALTER TABLE ONLY "public"."sourcing_events"
    ADD CONSTRAINT "sourcing_events_finance_owner_id_fkey" FOREIGN KEY ("finance_owner_id") REFERENCES "public"."profiles"("id");



ALTER TABLE ONLY "public"."sourcing_events"
    ADD CONSTRAINT "sourcing_events_incumbent_supplier_id_fkey" FOREIGN KEY ("incumbent_supplier_id") REFERENCES "public"."suppliers"("id");



ALTER TABLE ONLY "public"."sourcing_events"
    ADD CONSTRAINT "sourcing_events_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id");



ALTER TABLE ONLY "public"."sourcing_events"
    ADD CONSTRAINT "sourcing_events_procurement_owner_id_fkey" FOREIGN KEY ("procurement_owner_id") REFERENCES "public"."profiles"("id");



ALTER TABLE ONLY "public"."sourcing_events"
    ADD CONSTRAINT "sourcing_events_savings_disposition_by_fkey" FOREIGN KEY ("savings_disposition_by") REFERENCES "public"."profiles"("id");



ALTER TABLE ONLY "public"."sourcing_events"
    ADD CONSTRAINT "sourcing_events_updated_by_fkey" FOREIGN KEY ("updated_by") REFERENCES "public"."profiles"("id");



ALTER TABLE ONLY "public"."supplier_certifications"
    ADD CONSTRAINT "supplier_certifications_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "public"."profiles"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."supplier_certifications"
    ADD CONSTRAINT "supplier_certifications_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."supplier_certifications"
    ADD CONSTRAINT "supplier_certifications_supplier_workspace_fkey" FOREIGN KEY ("supplier_id", "organization_id") REFERENCES "public"."suppliers"("id", "organization_id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."supplier_certifications"
    ADD CONSTRAINT "supplier_certifications_updated_by_fkey" FOREIGN KEY ("updated_by") REFERENCES "public"."profiles"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."supplier_contacts"
    ADD CONSTRAINT "supplier_contacts_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "public"."profiles"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."supplier_contacts"
    ADD CONSTRAINT "supplier_contacts_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."supplier_contacts"
    ADD CONSTRAINT "supplier_contacts_supplier_workspace_fkey" FOREIGN KEY ("supplier_id", "organization_id") REFERENCES "public"."suppliers"("id", "organization_id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."supplier_contacts"
    ADD CONSTRAINT "supplier_contacts_updated_by_fkey" FOREIGN KEY ("updated_by") REFERENCES "public"."profiles"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."supplier_notes"
    ADD CONSTRAINT "supplier_notes_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "public"."profiles"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."supplier_notes"
    ADD CONSTRAINT "supplier_notes_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."supplier_notes"
    ADD CONSTRAINT "supplier_notes_supplier_workspace_fkey" FOREIGN KEY ("supplier_id", "organization_id") REFERENCES "public"."suppliers"("id", "organization_id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."supplier_offer_lines"
    ADD CONSTRAINT "supplier_offer_lines_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "public"."profiles"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."supplier_offer_lines"
    ADD CONSTRAINT "supplier_offer_lines_event_id_fkey" FOREIGN KEY ("event_id") REFERENCES "public"."sourcing_events"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."supplier_offer_lines"
    ADD CONSTRAINT "supplier_offer_lines_offer_id_fkey" FOREIGN KEY ("offer_id") REFERENCES "public"."supplier_offers"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."supplier_offer_lines"
    ADD CONSTRAINT "supplier_offer_lines_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id");



ALTER TABLE ONLY "public"."supplier_offer_lines"
    ADD CONSTRAINT "supplier_offer_lines_scope_line_id_fkey" FOREIGN KEY ("scope_line_id") REFERENCES "public"."event_scope_lines"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."supplier_offer_lines"
    ADD CONSTRAINT "supplier_offer_lines_updated_by_fkey" FOREIGN KEY ("updated_by") REFERENCES "public"."profiles"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."supplier_offers"
    ADD CONSTRAINT "supplier_offers_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "public"."profiles"("id");



ALTER TABLE ONLY "public"."supplier_offers"
    ADD CONSTRAINT "supplier_offers_event_id_fkey" FOREIGN KEY ("event_id") REFERENCES "public"."sourcing_events"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."supplier_offers"
    ADD CONSTRAINT "supplier_offers_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id");



ALTER TABLE ONLY "public"."supplier_offers"
    ADD CONSTRAINT "supplier_offers_supplier_id_fkey" FOREIGN KEY ("supplier_id") REFERENCES "public"."suppliers"("id");



ALTER TABLE ONLY "public"."supplier_offers"
    ADD CONSTRAINT "supplier_offers_updated_by_fkey" FOREIGN KEY ("updated_by") REFERENCES "public"."profiles"("id");



ALTER TABLE ONLY "public"."supplier_performance_reviews"
    ADD CONSTRAINT "supplier_performance_reviews_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "public"."profiles"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."supplier_performance_reviews"
    ADD CONSTRAINT "supplier_performance_reviews_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."supplier_performance_reviews"
    ADD CONSTRAINT "supplier_performance_reviews_supplier_workspace_fkey" FOREIGN KEY ("supplier_id", "organization_id") REFERENCES "public"."suppliers"("id", "organization_id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."supplier_performance_reviews"
    ADD CONSTRAINT "supplier_performance_reviews_updated_by_fkey" FOREIGN KEY ("updated_by") REFERENCES "public"."profiles"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."supplier_risks"
    ADD CONSTRAINT "supplier_risks_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "public"."profiles"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."supplier_risks"
    ADD CONSTRAINT "supplier_risks_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."supplier_risks"
    ADD CONSTRAINT "supplier_risks_supplier_workspace_fkey" FOREIGN KEY ("supplier_id", "organization_id") REFERENCES "public"."suppliers"("id", "organization_id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."supplier_risks"
    ADD CONSTRAINT "supplier_risks_updated_by_fkey" FOREIGN KEY ("updated_by") REFERENCES "public"."profiles"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."suppliers"
    ADD CONSTRAINT "suppliers_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id");



ALTER TABLE ONLY "public"."suppliers"
    ADD CONSTRAINT "suppliers_relationship_owner_id_fkey" FOREIGN KEY ("relationship_owner_id") REFERENCES "public"."profiles"("id");



ALTER TABLE "public"."audit_log" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "audit_log_select" ON "public"."audit_log" FOR SELECT TO "authenticated" USING (("organization_id" = ( SELECT "public"."current_org_id"() AS "current_org_id")));



ALTER TABLE "public"."award_lines" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."awards" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."baseline_lines" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."baselines" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."business_units" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "business_units_insert_by_admin" ON "public"."business_units" FOR INSERT TO "authenticated" WITH CHECK ((("organization_id" = ( SELECT "public"."current_org_id"() AS "current_org_id")) AND (EXISTS ( SELECT 1
   FROM "public"."profiles" "profile"
  WHERE (("profile"."id" = ( SELECT "auth"."uid"() AS "uid")) AND ("profile"."organization_id" = "business_units"."organization_id") AND ("profile"."role" = 'admin'::"text"))))));



CREATE POLICY "business_units_update_by_admin" ON "public"."business_units" FOR UPDATE TO "authenticated" USING ((("organization_id" = ( SELECT "public"."current_org_id"() AS "current_org_id")) AND (EXISTS ( SELECT 1
   FROM "public"."profiles" "profile"
  WHERE (("profile"."id" = ( SELECT "auth"."uid"() AS "uid")) AND ("profile"."organization_id" = "business_units"."organization_id") AND ("profile"."role" = 'admin'::"text")))))) WITH CHECK ((("organization_id" = ( SELECT "public"."current_org_id"() AS "current_org_id")) AND (EXISTS ( SELECT 1
   FROM "public"."profiles" "profile"
  WHERE (("profile"."id" = ( SELECT "auth"."uid"() AS "uid")) AND ("profile"."organization_id" = "business_units"."organization_id") AND ("profile"."role" = 'admin'::"text"))))));



ALTER TABLE "public"."categories" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "categories_insert_by_admin" ON "public"."categories" FOR INSERT TO "authenticated" WITH CHECK ((("organization_id" = ( SELECT "public"."current_org_id"() AS "current_org_id")) AND (EXISTS ( SELECT 1
   FROM "public"."profiles" "profile"
  WHERE (("profile"."id" = ( SELECT "auth"."uid"() AS "uid")) AND ("profile"."organization_id" = "categories"."organization_id") AND ("profile"."role" = 'admin'::"text"))))));



CREATE POLICY "categories_update_by_admin" ON "public"."categories" FOR UPDATE TO "authenticated" USING ((("organization_id" = ( SELECT "public"."current_org_id"() AS "current_org_id")) AND (EXISTS ( SELECT 1
   FROM "public"."profiles" "profile"
  WHERE (("profile"."id" = ( SELECT "auth"."uid"() AS "uid")) AND ("profile"."organization_id" = "categories"."organization_id") AND ("profile"."role" = 'admin'::"text")))))) WITH CHECK ((("organization_id" = ( SELECT "public"."current_org_id"() AS "current_org_id")) AND (EXISTS ( SELECT 1
   FROM "public"."profiles" "profile"
  WHERE (("profile"."id" = ( SELECT "auth"."uid"() AS "uid")) AND ("profile"."organization_id" = "categories"."organization_id") AND ("profile"."role" = 'admin'::"text"))))));



ALTER TABLE "public"."cost_centers" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "cost_centers_insert_by_admin" ON "public"."cost_centers" FOR INSERT TO "authenticated" WITH CHECK ((("organization_id" = ( SELECT "public"."current_org_id"() AS "current_org_id")) AND (EXISTS ( SELECT 1
   FROM "public"."profiles" "profile"
  WHERE (("profile"."id" = ( SELECT "auth"."uid"() AS "uid")) AND ("profile"."organization_id" = "cost_centers"."organization_id") AND ("profile"."role" = 'admin'::"text"))))));



CREATE POLICY "cost_centers_update_by_admin" ON "public"."cost_centers" FOR UPDATE TO "authenticated" USING ((("organization_id" = ( SELECT "public"."current_org_id"() AS "current_org_id")) AND (EXISTS ( SELECT 1
   FROM "public"."profiles" "profile"
  WHERE (("profile"."id" = ( SELECT "auth"."uid"() AS "uid")) AND ("profile"."organization_id" = "cost_centers"."organization_id") AND ("profile"."role" = 'admin'::"text")))))) WITH CHECK ((("organization_id" = ( SELECT "public"."current_org_id"() AS "current_org_id")) AND (EXISTS ( SELECT 1
   FROM "public"."profiles" "profile"
  WHERE (("profile"."id" = ( SELECT "auth"."uid"() AS "uid")) AND ("profile"."organization_id" = "cost_centers"."organization_id") AND ("profile"."role" = 'admin'::"text"))))));



ALTER TABLE "public"."event_scope_lines" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "org_delete" ON "public"."award_lines" FOR DELETE TO "authenticated" USING ((("organization_id" = "public"."current_org_id"()) AND (EXISTS ( SELECT 1
   FROM "public"."profiles" "profile"
  WHERE (("profile"."id" = "auth"."uid"()) AND ("profile"."organization_id" = "public"."current_org_id"()) AND ("profile"."role" = 'admin'::"text"))))));



CREATE POLICY "org_delete" ON "public"."awards" FOR DELETE TO "authenticated" USING ((("organization_id" = "public"."current_org_id"()) AND (EXISTS ( SELECT 1
   FROM "public"."profiles" "profile"
  WHERE (("profile"."id" = "auth"."uid"()) AND ("profile"."organization_id" = "public"."current_org_id"()) AND ("profile"."role" = 'admin'::"text"))))));



CREATE POLICY "org_delete" ON "public"."baseline_lines" FOR DELETE TO "authenticated" USING ((("organization_id" = "public"."current_org_id"()) AND (EXISTS ( SELECT 1
   FROM "public"."profiles" "profile"
  WHERE (("profile"."id" = "auth"."uid"()) AND ("profile"."organization_id" = "public"."current_org_id"()) AND ("profile"."role" = 'admin'::"text"))))));



CREATE POLICY "org_delete" ON "public"."baselines" FOR DELETE TO "authenticated" USING ((("organization_id" = "public"."current_org_id"()) AND (EXISTS ( SELECT 1
   FROM "public"."profiles" "profile"
  WHERE (("profile"."id" = "auth"."uid"()) AND ("profile"."organization_id" = "public"."current_org_id"()) AND ("profile"."role" = 'admin'::"text"))))));



CREATE POLICY "org_delete" ON "public"."event_scope_lines" FOR DELETE TO "authenticated" USING ((("organization_id" = "public"."current_org_id"()) AND (EXISTS ( SELECT 1
   FROM "public"."profiles" "profile"
  WHERE (("profile"."id" = "auth"."uid"()) AND ("profile"."organization_id" = "public"."current_org_id"()) AND ("profile"."role" = 'admin'::"text"))))));



CREATE POLICY "org_delete" ON "public"."realization_periods" FOR DELETE TO "authenticated" USING ((("organization_id" = "public"."current_org_id"()) AND (NOT COALESCE("finance_validated", false)) AND (EXISTS ( SELECT 1
   FROM "public"."profiles" "profile"
  WHERE (("profile"."id" = "auth"."uid"()) AND ("profile"."organization_id" = "public"."current_org_id"()) AND ("profile"."role" = 'admin'::"text"))))));



CREATE POLICY "org_delete" ON "public"."savings_calculation_lines" FOR DELETE TO "authenticated" USING ((("organization_id" = "public"."current_org_id"()) AND (EXISTS ( SELECT 1
   FROM "public"."profiles" "profile"
  WHERE (("profile"."id" = "auth"."uid"()) AND ("profile"."organization_id" = "public"."current_org_id"()) AND ("profile"."role" = 'admin'::"text"))))));



CREATE POLICY "org_delete" ON "public"."savings_calculations" FOR DELETE TO "authenticated" USING ((("organization_id" = "public"."current_org_id"()) AND ("calculation_status" = 'estimated'::"text") AND (EXISTS ( SELECT 1
   FROM "public"."profiles" "profile"
  WHERE (("profile"."id" = "auth"."uid"()) AND ("profile"."organization_id" = "public"."current_org_id"()) AND ("profile"."role" = 'admin'::"text"))))));



CREATE POLICY "org_delete" ON "public"."savings_periods" FOR DELETE TO "authenticated" USING (false);



CREATE POLICY "org_delete" ON "public"."sourcing_events" FOR DELETE TO "authenticated" USING ((("organization_id" = "public"."current_org_id"()) AND (EXISTS ( SELECT 1
   FROM "public"."profiles" "profile"
  WHERE (("profile"."id" = "auth"."uid"()) AND ("profile"."organization_id" = "public"."current_org_id"()) AND ("profile"."role" = 'admin'::"text"))))));



CREATE POLICY "org_delete" ON "public"."supplier_offer_lines" FOR DELETE TO "authenticated" USING ((("organization_id" = "public"."current_org_id"()) AND (EXISTS ( SELECT 1
   FROM "public"."profiles" "profile"
  WHERE (("profile"."id" = "auth"."uid"()) AND ("profile"."organization_id" = "public"."current_org_id"()) AND ("profile"."role" = 'admin'::"text"))))));



CREATE POLICY "org_delete" ON "public"."supplier_offers" FOR DELETE TO "authenticated" USING ((("organization_id" = "public"."current_org_id"()) AND (EXISTS ( SELECT 1
   FROM "public"."profiles" "profile"
  WHERE (("profile"."id" = "auth"."uid"()) AND ("profile"."organization_id" = "public"."current_org_id"()) AND ("profile"."role" = 'admin'::"text"))))));



CREATE POLICY "org_insert" ON "public"."award_lines" FOR INSERT TO "authenticated" WITH CHECK ((("organization_id" = "public"."current_org_id"()) AND (EXISTS ( SELECT 1
   FROM "public"."profiles" "profile"
  WHERE (("profile"."id" = "auth"."uid"()) AND ("profile"."organization_id" = "public"."current_org_id"()) AND ("profile"."role" = ANY (ARRAY['admin'::"text", 'procurement_user'::"text"])))))));



CREATE POLICY "org_insert" ON "public"."awards" FOR INSERT TO "authenticated" WITH CHECK ((("organization_id" = "public"."current_org_id"()) AND (EXISTS ( SELECT 1
   FROM "public"."profiles" "profile"
  WHERE (("profile"."id" = "auth"."uid"()) AND ("profile"."organization_id" = "public"."current_org_id"()) AND ("profile"."role" = ANY (ARRAY['admin'::"text", 'procurement_user'::"text"])))))));



CREATE POLICY "org_insert" ON "public"."baseline_lines" FOR INSERT TO "authenticated" WITH CHECK ((("organization_id" = "public"."current_org_id"()) AND (EXISTS ( SELECT 1
   FROM "public"."profiles" "profile"
  WHERE (("profile"."id" = "auth"."uid"()) AND ("profile"."organization_id" = "public"."current_org_id"()) AND ("profile"."role" = ANY (ARRAY['admin'::"text", 'procurement_user'::"text"])))))));



CREATE POLICY "org_insert" ON "public"."baselines" FOR INSERT TO "authenticated" WITH CHECK ((("organization_id" = "public"."current_org_id"()) AND (EXISTS ( SELECT 1
   FROM "public"."profiles" "profile"
  WHERE (("profile"."id" = "auth"."uid"()) AND ("profile"."organization_id" = "public"."current_org_id"()) AND ("profile"."role" = ANY (ARRAY['admin'::"text", 'procurement_user'::"text"])))))));



CREATE POLICY "org_insert" ON "public"."event_scope_lines" FOR INSERT TO "authenticated" WITH CHECK ((("organization_id" = "public"."current_org_id"()) AND (EXISTS ( SELECT 1
   FROM "public"."profiles" "profile"
  WHERE (("profile"."id" = "auth"."uid"()) AND ("profile"."organization_id" = "public"."current_org_id"()) AND ("profile"."role" = ANY (ARRAY['admin'::"text", 'procurement_user'::"text"])))))));



CREATE POLICY "org_insert" ON "public"."realization_periods" FOR INSERT TO "authenticated" WITH CHECK (false);



CREATE POLICY "org_insert" ON "public"."savings_calculation_lines" FOR INSERT TO "authenticated" WITH CHECK ((("organization_id" = "public"."current_org_id"()) AND (EXISTS ( SELECT 1
   FROM "public"."profiles" "profile"
  WHERE (("profile"."id" = "auth"."uid"()) AND ("profile"."organization_id" = "public"."current_org_id"()) AND ("profile"."role" = ANY (ARRAY['admin'::"text", 'procurement_user'::"text"])))))));



CREATE POLICY "org_insert" ON "public"."savings_calculations" FOR INSERT TO "authenticated" WITH CHECK ((("organization_id" = "public"."current_org_id"()) AND ("calculation_status" = 'estimated'::"text") AND (EXISTS ( SELECT 1
   FROM "public"."profiles" "profile"
  WHERE (("profile"."id" = "auth"."uid"()) AND ("profile"."organization_id" = "public"."current_org_id"()) AND ("profile"."role" = ANY (ARRAY['admin'::"text", 'procurement_user'::"text"])))))));



CREATE POLICY "org_insert" ON "public"."savings_periods" FOR INSERT TO "authenticated" WITH CHECK (false);



CREATE POLICY "org_insert" ON "public"."sourcing_events" FOR INSERT TO "authenticated" WITH CHECK ((("organization_id" = "public"."current_org_id"()) AND (EXISTS ( SELECT 1
   FROM "public"."profiles" "profile"
  WHERE (("profile"."id" = "auth"."uid"()) AND ("profile"."organization_id" = "public"."current_org_id"()) AND ("profile"."role" = ANY (ARRAY['admin'::"text", 'procurement_user'::"text"])))))));



CREATE POLICY "org_insert" ON "public"."supplier_offer_lines" FOR INSERT TO "authenticated" WITH CHECK ((("organization_id" = "public"."current_org_id"()) AND (EXISTS ( SELECT 1
   FROM "public"."profiles" "profile"
  WHERE (("profile"."id" = "auth"."uid"()) AND ("profile"."organization_id" = "public"."current_org_id"()) AND ("profile"."role" = ANY (ARRAY['admin'::"text", 'procurement_user'::"text"])))))));



CREATE POLICY "org_insert" ON "public"."supplier_offers" FOR INSERT TO "authenticated" WITH CHECK ((("organization_id" = "public"."current_org_id"()) AND (EXISTS ( SELECT 1
   FROM "public"."profiles" "profile"
  WHERE (("profile"."id" = "auth"."uid"()) AND ("profile"."organization_id" = "public"."current_org_id"()) AND ("profile"."role" = ANY (ARRAY['admin'::"text", 'procurement_user'::"text"])))))));



CREATE POLICY "org_select" ON "public"."award_lines" FOR SELECT TO "authenticated" USING (("organization_id" = "public"."current_org_id"()));



CREATE POLICY "org_select" ON "public"."awards" FOR SELECT TO "authenticated" USING (("organization_id" = "public"."current_org_id"()));



CREATE POLICY "org_select" ON "public"."baseline_lines" FOR SELECT TO "authenticated" USING (("organization_id" = "public"."current_org_id"()));



CREATE POLICY "org_select" ON "public"."baselines" FOR SELECT TO "authenticated" USING (("organization_id" = "public"."current_org_id"()));



CREATE POLICY "org_select" ON "public"."business_units" FOR SELECT TO "authenticated" USING (("organization_id" = "public"."current_org_id"()));



CREATE POLICY "org_select" ON "public"."categories" FOR SELECT TO "authenticated" USING (("organization_id" = "public"."current_org_id"()));



CREATE POLICY "org_select" ON "public"."cost_centers" FOR SELECT TO "authenticated" USING (("organization_id" = "public"."current_org_id"()));



CREATE POLICY "org_select" ON "public"."event_scope_lines" FOR SELECT TO "authenticated" USING (("organization_id" = "public"."current_org_id"()));



CREATE POLICY "org_select" ON "public"."realization_periods" FOR SELECT TO "authenticated" USING (("organization_id" = "public"."current_org_id"()));



CREATE POLICY "org_select" ON "public"."savings_calculation_lines" FOR SELECT TO "authenticated" USING (("organization_id" = "public"."current_org_id"()));



CREATE POLICY "org_select" ON "public"."savings_calculations" FOR SELECT TO "authenticated" USING (("organization_id" = "public"."current_org_id"()));



CREATE POLICY "org_select" ON "public"."savings_periods" FOR SELECT TO "authenticated" USING (("organization_id" = "public"."current_org_id"()));



CREATE POLICY "org_select" ON "public"."sourcing_events" FOR SELECT TO "authenticated" USING (("organization_id" = "public"."current_org_id"()));



CREATE POLICY "org_select" ON "public"."supplier_offer_lines" FOR SELECT TO "authenticated" USING (("organization_id" = "public"."current_org_id"()));



CREATE POLICY "org_select" ON "public"."supplier_offers" FOR SELECT TO "authenticated" USING (("organization_id" = "public"."current_org_id"()));



CREATE POLICY "org_select" ON "public"."suppliers" FOR SELECT TO "authenticated" USING (("organization_id" = "public"."current_org_id"()));



CREATE POLICY "org_update" ON "public"."award_lines" FOR UPDATE TO "authenticated" USING ((("organization_id" = "public"."current_org_id"()) AND (EXISTS ( SELECT 1
   FROM "public"."profiles" "profile"
  WHERE (("profile"."id" = "auth"."uid"()) AND ("profile"."organization_id" = "public"."current_org_id"()) AND ("profile"."role" = ANY (ARRAY['admin'::"text", 'procurement_user'::"text"]))))))) WITH CHECK ((("organization_id" = "public"."current_org_id"()) AND (EXISTS ( SELECT 1
   FROM "public"."profiles" "profile"
  WHERE (("profile"."id" = "auth"."uid"()) AND ("profile"."organization_id" = "public"."current_org_id"()) AND ("profile"."role" = ANY (ARRAY['admin'::"text", 'procurement_user'::"text"])))))));



CREATE POLICY "org_update" ON "public"."awards" FOR UPDATE TO "authenticated" USING ((("organization_id" = "public"."current_org_id"()) AND (EXISTS ( SELECT 1
   FROM "public"."profiles" "profile"
  WHERE (("profile"."id" = "auth"."uid"()) AND ("profile"."organization_id" = "public"."current_org_id"()) AND ("profile"."role" = ANY (ARRAY['admin'::"text", 'procurement_user'::"text"]))))))) WITH CHECK ((("organization_id" = "public"."current_org_id"()) AND (EXISTS ( SELECT 1
   FROM "public"."profiles" "profile"
  WHERE (("profile"."id" = "auth"."uid"()) AND ("profile"."organization_id" = "public"."current_org_id"()) AND ("profile"."role" = ANY (ARRAY['admin'::"text", 'procurement_user'::"text"])))))));



CREATE POLICY "org_update" ON "public"."baseline_lines" FOR UPDATE TO "authenticated" USING ((("organization_id" = "public"."current_org_id"()) AND (EXISTS ( SELECT 1
   FROM "public"."profiles" "profile"
  WHERE (("profile"."id" = "auth"."uid"()) AND ("profile"."organization_id" = "public"."current_org_id"()) AND ("profile"."role" = ANY (ARRAY['admin'::"text", 'procurement_user'::"text"]))))))) WITH CHECK ((("organization_id" = "public"."current_org_id"()) AND (EXISTS ( SELECT 1
   FROM "public"."profiles" "profile"
  WHERE (("profile"."id" = "auth"."uid"()) AND ("profile"."organization_id" = "public"."current_org_id"()) AND ("profile"."role" = ANY (ARRAY['admin'::"text", 'procurement_user'::"text"])))))));



CREATE POLICY "org_update" ON "public"."baselines" FOR UPDATE TO "authenticated" USING ((("organization_id" = "public"."current_org_id"()) AND (EXISTS ( SELECT 1
   FROM "public"."profiles" "profile"
  WHERE (("profile"."id" = "auth"."uid"()) AND ("profile"."organization_id" = "public"."current_org_id"()) AND ("profile"."role" = ANY (ARRAY['admin'::"text", 'procurement_user'::"text"]))))))) WITH CHECK ((("organization_id" = "public"."current_org_id"()) AND (EXISTS ( SELECT 1
   FROM "public"."profiles" "profile"
  WHERE (("profile"."id" = "auth"."uid"()) AND ("profile"."organization_id" = "public"."current_org_id"()) AND ("profile"."role" = ANY (ARRAY['admin'::"text", 'procurement_user'::"text"])))))));



CREATE POLICY "org_update" ON "public"."event_scope_lines" FOR UPDATE TO "authenticated" USING ((("organization_id" = "public"."current_org_id"()) AND (EXISTS ( SELECT 1
   FROM "public"."profiles" "profile"
  WHERE (("profile"."id" = "auth"."uid"()) AND ("profile"."organization_id" = "public"."current_org_id"()) AND ("profile"."role" = ANY (ARRAY['admin'::"text", 'procurement_user'::"text"]))))))) WITH CHECK ((("organization_id" = "public"."current_org_id"()) AND (EXISTS ( SELECT 1
   FROM "public"."profiles" "profile"
  WHERE (("profile"."id" = "auth"."uid"()) AND ("profile"."organization_id" = "public"."current_org_id"()) AND ("profile"."role" = ANY (ARRAY['admin'::"text", 'procurement_user'::"text"])))))));



CREATE POLICY "org_update" ON "public"."realization_periods" FOR UPDATE TO "authenticated" USING ((("organization_id" = "public"."current_org_id"()) AND (EXISTS ( SELECT 1
   FROM "public"."profiles" "profile"
  WHERE (("profile"."id" = "auth"."uid"()) AND ("profile"."organization_id" = "public"."current_org_id"()) AND ("profile"."role" = ANY (ARRAY['admin'::"text", 'procurement_user'::"text"]))))))) WITH CHECK ((("organization_id" = "public"."current_org_id"()) AND (EXISTS ( SELECT 1
   FROM "public"."profiles" "profile"
  WHERE (("profile"."id" = "auth"."uid"()) AND ("profile"."organization_id" = "public"."current_org_id"()) AND ("profile"."role" = ANY (ARRAY['admin'::"text", 'procurement_user'::"text"])))))));



CREATE POLICY "org_update" ON "public"."savings_calculation_lines" FOR UPDATE TO "authenticated" USING ((("organization_id" = "public"."current_org_id"()) AND (EXISTS ( SELECT 1
   FROM "public"."profiles" "profile"
  WHERE (("profile"."id" = "auth"."uid"()) AND ("profile"."organization_id" = "public"."current_org_id"()) AND ("profile"."role" = ANY (ARRAY['admin'::"text", 'procurement_user'::"text"]))))))) WITH CHECK ((("organization_id" = "public"."current_org_id"()) AND (EXISTS ( SELECT 1
   FROM "public"."profiles" "profile"
  WHERE (("profile"."id" = "auth"."uid"()) AND ("profile"."organization_id" = "public"."current_org_id"()) AND ("profile"."role" = ANY (ARRAY['admin'::"text", 'procurement_user'::"text"])))))));



CREATE POLICY "org_update" ON "public"."savings_calculations" FOR UPDATE TO "authenticated" USING ((("organization_id" = "public"."current_org_id"()) AND ("calculation_status" = 'estimated'::"text") AND (EXISTS ( SELECT 1
   FROM "public"."profiles" "profile"
  WHERE (("profile"."id" = "auth"."uid"()) AND ("profile"."organization_id" = "public"."current_org_id"()) AND ("profile"."role" = ANY (ARRAY['admin'::"text", 'procurement_user'::"text"]))))))) WITH CHECK ((("organization_id" = "public"."current_org_id"()) AND ("calculation_status" = 'estimated'::"text") AND (EXISTS ( SELECT 1
   FROM "public"."profiles" "profile"
  WHERE (("profile"."id" = "auth"."uid"()) AND ("profile"."organization_id" = "public"."current_org_id"()) AND ("profile"."role" = ANY (ARRAY['admin'::"text", 'procurement_user'::"text"])))))));



CREATE POLICY "org_update" ON "public"."savings_periods" FOR UPDATE TO "authenticated" USING ((("organization_id" = "public"."current_org_id"()) AND (EXISTS ( SELECT 1
   FROM "public"."savings_calculations" "calculation"
  WHERE (("calculation"."id" = "savings_periods"."savings_calculation_id") AND ("calculation"."organization_id" = "public"."current_org_id"()) AND ("calculation"."calculation_status" = 'estimated'::"text")))) AND (EXISTS ( SELECT 1
   FROM "public"."profiles" "profile"
  WHERE (("profile"."id" = "auth"."uid"()) AND ("profile"."organization_id" = "public"."current_org_id"()) AND ("profile"."role" = ANY (ARRAY['admin'::"text", 'procurement_user'::"text"]))))))) WITH CHECK ((("organization_id" = "public"."current_org_id"()) AND (EXISTS ( SELECT 1
   FROM "public"."savings_calculations" "calculation"
  WHERE (("calculation"."id" = "savings_periods"."savings_calculation_id") AND ("calculation"."organization_id" = "public"."current_org_id"()) AND ("calculation"."calculation_status" = 'estimated'::"text")))) AND (EXISTS ( SELECT 1
   FROM "public"."profiles" "profile"
  WHERE (("profile"."id" = "auth"."uid"()) AND ("profile"."organization_id" = "public"."current_org_id"()) AND ("profile"."role" = ANY (ARRAY['admin'::"text", 'procurement_user'::"text"])))))));



CREATE POLICY "org_update" ON "public"."sourcing_events" FOR UPDATE TO "authenticated" USING ((("organization_id" = "public"."current_org_id"()) AND (EXISTS ( SELECT 1
   FROM "public"."profiles" "profile"
  WHERE (("profile"."id" = "auth"."uid"()) AND ("profile"."organization_id" = "public"."current_org_id"()) AND ("profile"."role" = ANY (ARRAY['admin'::"text", 'procurement_user'::"text"]))))))) WITH CHECK ((("organization_id" = "public"."current_org_id"()) AND (EXISTS ( SELECT 1
   FROM "public"."profiles" "profile"
  WHERE (("profile"."id" = "auth"."uid"()) AND ("profile"."organization_id" = "public"."current_org_id"()) AND ("profile"."role" = ANY (ARRAY['admin'::"text", 'procurement_user'::"text"])))))));



CREATE POLICY "org_update" ON "public"."supplier_offer_lines" FOR UPDATE TO "authenticated" USING ((("organization_id" = "public"."current_org_id"()) AND (EXISTS ( SELECT 1
   FROM "public"."profiles" "profile"
  WHERE (("profile"."id" = "auth"."uid"()) AND ("profile"."organization_id" = "public"."current_org_id"()) AND ("profile"."role" = ANY (ARRAY['admin'::"text", 'procurement_user'::"text"]))))))) WITH CHECK ((("organization_id" = "public"."current_org_id"()) AND (EXISTS ( SELECT 1
   FROM "public"."profiles" "profile"
  WHERE (("profile"."id" = "auth"."uid"()) AND ("profile"."organization_id" = "public"."current_org_id"()) AND ("profile"."role" = ANY (ARRAY['admin'::"text", 'procurement_user'::"text"])))))));



CREATE POLICY "org_update" ON "public"."supplier_offers" FOR UPDATE TO "authenticated" USING ((("organization_id" = "public"."current_org_id"()) AND (EXISTS ( SELECT 1
   FROM "public"."profiles" "profile"
  WHERE (("profile"."id" = "auth"."uid"()) AND ("profile"."organization_id" = "public"."current_org_id"()) AND ("profile"."role" = ANY (ARRAY['admin'::"text", 'procurement_user'::"text"]))))))) WITH CHECK ((("organization_id" = "public"."current_org_id"()) AND (EXISTS ( SELECT 1
   FROM "public"."profiles" "profile"
  WHERE (("profile"."id" = "auth"."uid"()) AND ("profile"."organization_id" = "public"."current_org_id"()) AND ("profile"."role" = ANY (ARRAY['admin'::"text", 'procurement_user'::"text"])))))));



ALTER TABLE "public"."organization_settings" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "organization_settings_insert_by_admin" ON "public"."organization_settings" FOR INSERT TO "authenticated" WITH CHECK ((("organization_id" = ( SELECT "public"."current_org_id"() AS "current_org_id")) AND (EXISTS ( SELECT 1
   FROM "public"."profiles" "p"
  WHERE (("p"."id" = ( SELECT "auth"."uid"() AS "uid")) AND ("p"."organization_id" = "organization_settings"."organization_id") AND ("p"."role" = 'admin'::"text"))))));



CREATE POLICY "organization_settings_select" ON "public"."organization_settings" FOR SELECT TO "authenticated" USING (("organization_id" = ( SELECT "public"."current_org_id"() AS "current_org_id")));



CREATE POLICY "organization_settings_update_by_admin" ON "public"."organization_settings" FOR UPDATE TO "authenticated" USING ((("organization_id" = ( SELECT "public"."current_org_id"() AS "current_org_id")) AND (EXISTS ( SELECT 1
   FROM "public"."profiles" "p"
  WHERE (("p"."id" = ( SELECT "auth"."uid"() AS "uid")) AND ("p"."organization_id" = "organization_settings"."organization_id") AND ("p"."role" = 'admin'::"text")))))) WITH CHECK ((("organization_id" = ( SELECT "public"."current_org_id"() AS "current_org_id")) AND (EXISTS ( SELECT 1
   FROM "public"."profiles" "p"
  WHERE (("p"."id" = ( SELECT "auth"."uid"() AS "uid")) AND ("p"."organization_id" = "organization_settings"."organization_id") AND ("p"."role" = 'admin'::"text"))))));



CREATE POLICY "organization_update_by_admin" ON "public"."organizations" FOR UPDATE TO "authenticated" USING ((("id" = ( SELECT "public"."current_org_id"() AS "current_org_id")) AND (EXISTS ( SELECT 1
   FROM "public"."profiles" "p"
  WHERE (("p"."id" = ( SELECT "auth"."uid"() AS "uid")) AND ("p"."organization_id" = "organizations"."id") AND ("p"."role" = 'admin'::"text")))))) WITH CHECK ((("id" = ( SELECT "public"."current_org_id"() AS "current_org_id")) AND (EXISTS ( SELECT 1
   FROM "public"."profiles" "p"
  WHERE (("p"."id" = ( SELECT "auth"."uid"() AS "uid")) AND ("p"."organization_id" = "organizations"."id") AND ("p"."role" = 'admin'::"text"))))));



ALTER TABLE "public"."organizations" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "own_org_select" ON "public"."organizations" FOR SELECT TO "authenticated" USING (("id" = "public"."current_org_id"()));



ALTER TABLE "public"."profiles" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "profiles_select_org" ON "public"."profiles" FOR SELECT TO "authenticated" USING (("organization_id" = "public"."current_org_id"()));



CREATE POLICY "profiles_update_self" ON "public"."profiles" FOR UPDATE TO "authenticated" USING (("id" = ( SELECT "auth"."uid"() AS "uid"))) WITH CHECK (("id" = ( SELECT "auth"."uid"() AS "uid")));



ALTER TABLE "public"."project_choice_options" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "project_choice_options_insert_by_admin" ON "public"."project_choice_options" FOR INSERT TO "authenticated" WITH CHECK ((("organization_id" = ( SELECT "public"."current_org_id"() AS "current_org_id")) AND (EXISTS ( SELECT 1
   FROM "public"."profiles" "profile"
  WHERE (("profile"."id" = ( SELECT "auth"."uid"() AS "uid")) AND ("profile"."organization_id" = "project_choice_options"."organization_id") AND ("profile"."role" = 'admin'::"text"))))));



CREATE POLICY "project_choice_options_select" ON "public"."project_choice_options" FOR SELECT TO "authenticated" USING (("organization_id" = ( SELECT "public"."current_org_id"() AS "current_org_id")));



CREATE POLICY "project_choice_options_update_by_admin" ON "public"."project_choice_options" FOR UPDATE TO "authenticated" USING ((("organization_id" = ( SELECT "public"."current_org_id"() AS "current_org_id")) AND (EXISTS ( SELECT 1
   FROM "public"."profiles" "profile"
  WHERE (("profile"."id" = ( SELECT "auth"."uid"() AS "uid")) AND ("profile"."organization_id" = "project_choice_options"."organization_id") AND ("profile"."role" = 'admin'::"text")))))) WITH CHECK ((("organization_id" = ( SELECT "public"."current_org_id"() AS "current_org_id")) AND (EXISTS ( SELECT 1
   FROM "public"."profiles" "profile"
  WHERE (("profile"."id" = ( SELECT "auth"."uid"() AS "uid")) AND ("profile"."organization_id" = "project_choice_options"."organization_id") AND ("profile"."role" = 'admin'::"text"))))));



ALTER TABLE "public"."project_updates" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "project_updates_insert_org_author" ON "public"."project_updates" FOR INSERT TO "authenticated" WITH CHECK ((("organization_id" = ( SELECT "public"."current_org_id"() AS "current_org_id")) AND ("created_by" = ( SELECT "auth"."uid"() AS "uid")) AND (EXISTS ( SELECT 1
   FROM "public"."sourcing_events" "event"
  WHERE (("event"."id" = "project_updates"."event_id") AND ("event"."organization_id" = "project_updates"."organization_id"))))));



CREATE POLICY "project_updates_select_org" ON "public"."project_updates" FOR SELECT TO "authenticated" USING (("organization_id" = ( SELECT "public"."current_org_id"() AS "current_org_id")));



ALTER TABLE "public"."realization_periods" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."savings_calculation_lines" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."savings_calculations" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."savings_periods" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."sourcing_events" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."supplier_certifications" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "supplier_certifications_delete_by_editor" ON "public"."supplier_certifications" FOR DELETE TO "authenticated" USING ((("organization_id" = ( SELECT "public"."current_org_id"() AS "current_org_id")) AND (EXISTS ( SELECT 1
   FROM "public"."profiles" "profile"
  WHERE (("profile"."id" = ( SELECT "auth"."uid"() AS "uid")) AND ("profile"."organization_id" = "supplier_certifications"."organization_id") AND ("profile"."role" = ANY (ARRAY['admin'::"text", 'procurement_user'::"text"])))))));



CREATE POLICY "supplier_certifications_insert_by_editor" ON "public"."supplier_certifications" FOR INSERT TO "authenticated" WITH CHECK ((("organization_id" = ( SELECT "public"."current_org_id"() AS "current_org_id")) AND (EXISTS ( SELECT 1
   FROM "public"."profiles" "profile"
  WHERE (("profile"."id" = ( SELECT "auth"."uid"() AS "uid")) AND ("profile"."organization_id" = "supplier_certifications"."organization_id") AND ("profile"."role" = ANY (ARRAY['admin'::"text", 'procurement_user'::"text"])))))));



CREATE POLICY "supplier_certifications_select" ON "public"."supplier_certifications" FOR SELECT TO "authenticated" USING (("organization_id" = ( SELECT "public"."current_org_id"() AS "current_org_id")));



CREATE POLICY "supplier_certifications_update_by_editor" ON "public"."supplier_certifications" FOR UPDATE TO "authenticated" USING ((("organization_id" = ( SELECT "public"."current_org_id"() AS "current_org_id")) AND (EXISTS ( SELECT 1
   FROM "public"."profiles" "profile"
  WHERE (("profile"."id" = ( SELECT "auth"."uid"() AS "uid")) AND ("profile"."organization_id" = "supplier_certifications"."organization_id") AND ("profile"."role" = ANY (ARRAY['admin'::"text", 'procurement_user'::"text"]))))))) WITH CHECK ((("organization_id" = ( SELECT "public"."current_org_id"() AS "current_org_id")) AND (EXISTS ( SELECT 1
   FROM "public"."profiles" "profile"
  WHERE (("profile"."id" = ( SELECT "auth"."uid"() AS "uid")) AND ("profile"."organization_id" = "supplier_certifications"."organization_id") AND ("profile"."role" = ANY (ARRAY['admin'::"text", 'procurement_user'::"text"])))))));



ALTER TABLE "public"."supplier_contacts" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "supplier_contacts_delete_by_editor" ON "public"."supplier_contacts" FOR DELETE TO "authenticated" USING ((("organization_id" = ( SELECT "public"."current_org_id"() AS "current_org_id")) AND (EXISTS ( SELECT 1
   FROM "public"."profiles" "profile"
  WHERE (("profile"."id" = ( SELECT "auth"."uid"() AS "uid")) AND ("profile"."organization_id" = "supplier_contacts"."organization_id") AND ("profile"."role" = ANY (ARRAY['admin'::"text", 'procurement_user'::"text"])))))));



CREATE POLICY "supplier_contacts_insert_by_editor" ON "public"."supplier_contacts" FOR INSERT TO "authenticated" WITH CHECK ((("organization_id" = ( SELECT "public"."current_org_id"() AS "current_org_id")) AND (EXISTS ( SELECT 1
   FROM "public"."profiles" "profile"
  WHERE (("profile"."id" = ( SELECT "auth"."uid"() AS "uid")) AND ("profile"."organization_id" = "supplier_contacts"."organization_id") AND ("profile"."role" = ANY (ARRAY['admin'::"text", 'procurement_user'::"text"])))))));



CREATE POLICY "supplier_contacts_select" ON "public"."supplier_contacts" FOR SELECT TO "authenticated" USING (("organization_id" = ( SELECT "public"."current_org_id"() AS "current_org_id")));



CREATE POLICY "supplier_contacts_update_by_editor" ON "public"."supplier_contacts" FOR UPDATE TO "authenticated" USING ((("organization_id" = ( SELECT "public"."current_org_id"() AS "current_org_id")) AND (EXISTS ( SELECT 1
   FROM "public"."profiles" "profile"
  WHERE (("profile"."id" = ( SELECT "auth"."uid"() AS "uid")) AND ("profile"."organization_id" = "supplier_contacts"."organization_id") AND ("profile"."role" = ANY (ARRAY['admin'::"text", 'procurement_user'::"text"]))))))) WITH CHECK ((("organization_id" = ( SELECT "public"."current_org_id"() AS "current_org_id")) AND (EXISTS ( SELECT 1
   FROM "public"."profiles" "profile"
  WHERE (("profile"."id" = ( SELECT "auth"."uid"() AS "uid")) AND ("profile"."organization_id" = "supplier_contacts"."organization_id") AND ("profile"."role" = ANY (ARRAY['admin'::"text", 'procurement_user'::"text"])))))));



CREATE POLICY "supplier_delete_by_admin" ON "public"."suppliers" FOR DELETE TO "authenticated" USING ((("organization_id" = ( SELECT "public"."current_org_id"() AS "current_org_id")) AND (EXISTS ( SELECT 1
   FROM "public"."profiles" "p"
  WHERE (("p"."id" = ( SELECT "auth"."uid"() AS "uid")) AND ("p"."organization_id" = "suppliers"."organization_id") AND ("p"."role" = 'admin'::"text"))))));



CREATE POLICY "supplier_insert_by_editor" ON "public"."suppliers" FOR INSERT TO "authenticated" WITH CHECK ((("organization_id" = ( SELECT "public"."current_org_id"() AS "current_org_id")) AND (EXISTS ( SELECT 1
   FROM "public"."profiles" "p"
  WHERE (("p"."id" = ( SELECT "auth"."uid"() AS "uid")) AND ("p"."organization_id" = "suppliers"."organization_id") AND ("p"."role" = ANY (ARRAY['admin'::"text", 'procurement_user'::"text"])))))));



ALTER TABLE "public"."supplier_notes" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "supplier_notes_insert_by_editor" ON "public"."supplier_notes" FOR INSERT TO "authenticated" WITH CHECK ((("organization_id" = ( SELECT "public"."current_org_id"() AS "current_org_id")) AND (EXISTS ( SELECT 1
   FROM "public"."profiles" "profile"
  WHERE (("profile"."id" = ( SELECT "auth"."uid"() AS "uid")) AND ("profile"."organization_id" = "supplier_notes"."organization_id") AND ("profile"."role" = ANY (ARRAY['admin'::"text", 'procurement_user'::"text"])))))));



CREATE POLICY "supplier_notes_select" ON "public"."supplier_notes" FOR SELECT TO "authenticated" USING (("organization_id" = ( SELECT "public"."current_org_id"() AS "current_org_id")));



ALTER TABLE "public"."supplier_offer_lines" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."supplier_offers" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."supplier_performance_reviews" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "supplier_performance_reviews_delete_by_editor" ON "public"."supplier_performance_reviews" FOR DELETE TO "authenticated" USING ((("organization_id" = ( SELECT "public"."current_org_id"() AS "current_org_id")) AND (EXISTS ( SELECT 1
   FROM "public"."profiles" "profile"
  WHERE (("profile"."id" = ( SELECT "auth"."uid"() AS "uid")) AND ("profile"."organization_id" = "supplier_performance_reviews"."organization_id") AND ("profile"."role" = ANY (ARRAY['admin'::"text", 'procurement_user'::"text"])))))));



CREATE POLICY "supplier_performance_reviews_insert_by_editor" ON "public"."supplier_performance_reviews" FOR INSERT TO "authenticated" WITH CHECK ((("organization_id" = ( SELECT "public"."current_org_id"() AS "current_org_id")) AND (EXISTS ( SELECT 1
   FROM "public"."profiles" "profile"
  WHERE (("profile"."id" = ( SELECT "auth"."uid"() AS "uid")) AND ("profile"."organization_id" = "supplier_performance_reviews"."organization_id") AND ("profile"."role" = ANY (ARRAY['admin'::"text", 'procurement_user'::"text"])))))));



CREATE POLICY "supplier_performance_reviews_select" ON "public"."supplier_performance_reviews" FOR SELECT TO "authenticated" USING (("organization_id" = ( SELECT "public"."current_org_id"() AS "current_org_id")));



CREATE POLICY "supplier_performance_reviews_update_by_editor" ON "public"."supplier_performance_reviews" FOR UPDATE TO "authenticated" USING ((("organization_id" = ( SELECT "public"."current_org_id"() AS "current_org_id")) AND (EXISTS ( SELECT 1
   FROM "public"."profiles" "profile"
  WHERE (("profile"."id" = ( SELECT "auth"."uid"() AS "uid")) AND ("profile"."organization_id" = "supplier_performance_reviews"."organization_id") AND ("profile"."role" = ANY (ARRAY['admin'::"text", 'procurement_user'::"text"]))))))) WITH CHECK ((("organization_id" = ( SELECT "public"."current_org_id"() AS "current_org_id")) AND (EXISTS ( SELECT 1
   FROM "public"."profiles" "profile"
  WHERE (("profile"."id" = ( SELECT "auth"."uid"() AS "uid")) AND ("profile"."organization_id" = "supplier_performance_reviews"."organization_id") AND ("profile"."role" = ANY (ARRAY['admin'::"text", 'procurement_user'::"text"])))))));



ALTER TABLE "public"."supplier_risks" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "supplier_risks_delete_by_editor" ON "public"."supplier_risks" FOR DELETE TO "authenticated" USING ((("organization_id" = ( SELECT "public"."current_org_id"() AS "current_org_id")) AND (EXISTS ( SELECT 1
   FROM "public"."profiles" "profile"
  WHERE (("profile"."id" = ( SELECT "auth"."uid"() AS "uid")) AND ("profile"."organization_id" = "supplier_risks"."organization_id") AND ("profile"."role" = ANY (ARRAY['admin'::"text", 'procurement_user'::"text"])))))));



CREATE POLICY "supplier_risks_insert_by_editor" ON "public"."supplier_risks" FOR INSERT TO "authenticated" WITH CHECK ((("organization_id" = ( SELECT "public"."current_org_id"() AS "current_org_id")) AND (EXISTS ( SELECT 1
   FROM "public"."profiles" "profile"
  WHERE (("profile"."id" = ( SELECT "auth"."uid"() AS "uid")) AND ("profile"."organization_id" = "supplier_risks"."organization_id") AND ("profile"."role" = ANY (ARRAY['admin'::"text", 'procurement_user'::"text"])))))));



CREATE POLICY "supplier_risks_select" ON "public"."supplier_risks" FOR SELECT TO "authenticated" USING (("organization_id" = ( SELECT "public"."current_org_id"() AS "current_org_id")));



CREATE POLICY "supplier_risks_update_by_editor" ON "public"."supplier_risks" FOR UPDATE TO "authenticated" USING ((("organization_id" = ( SELECT "public"."current_org_id"() AS "current_org_id")) AND (EXISTS ( SELECT 1
   FROM "public"."profiles" "profile"
  WHERE (("profile"."id" = ( SELECT "auth"."uid"() AS "uid")) AND ("profile"."organization_id" = "supplier_risks"."organization_id") AND ("profile"."role" = ANY (ARRAY['admin'::"text", 'procurement_user'::"text"]))))))) WITH CHECK ((("organization_id" = ( SELECT "public"."current_org_id"() AS "current_org_id")) AND (EXISTS ( SELECT 1
   FROM "public"."profiles" "profile"
  WHERE (("profile"."id" = ( SELECT "auth"."uid"() AS "uid")) AND ("profile"."organization_id" = "supplier_risks"."organization_id") AND ("profile"."role" = ANY (ARRAY['admin'::"text", 'procurement_user'::"text"])))))));



CREATE POLICY "supplier_update_by_editor" ON "public"."suppliers" FOR UPDATE TO "authenticated" USING ((("organization_id" = ( SELECT "public"."current_org_id"() AS "current_org_id")) AND (EXISTS ( SELECT 1
   FROM "public"."profiles" "p"
  WHERE (("p"."id" = ( SELECT "auth"."uid"() AS "uid")) AND ("p"."organization_id" = "suppliers"."organization_id") AND ("p"."role" = ANY (ARRAY['admin'::"text", 'procurement_user'::"text"]))))))) WITH CHECK ((("organization_id" = ( SELECT "public"."current_org_id"() AS "current_org_id")) AND (EXISTS ( SELECT 1
   FROM "public"."profiles" "p"
  WHERE (("p"."id" = ( SELECT "auth"."uid"() AS "uid")) AND ("p"."organization_id" = "suppliers"."organization_id") AND ("p"."role" = ANY (ARRAY['admin'::"text", 'procurement_user'::"text"])))))));



ALTER TABLE "public"."suppliers" ENABLE ROW LEVEL SECURITY;


GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";



REVOKE ALL ON FUNCTION "public"."capture_workspace_audit"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."capture_workspace_audit"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."cascade_project_choice_rename"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."cascade_project_choice_rename"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."clone_org_data"("p_source" "uuid", "p_target" "uuid", "p_owner" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."clone_org_data"("p_source" "uuid", "p_target" "uuid", "p_owner" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."complete_sourcing_project"("p_event_id" "uuid", "p_disposition" "text", "p_reason" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."complete_sourcing_project"("p_event_id" "uuid", "p_disposition" "text", "p_reason" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."complete_sourcing_project"("p_event_id" "uuid", "p_disposition" "text", "p_reason" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."confirm_business_equivalency"("p_scope_line_id" "uuid", "p_confirmed" boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."confirm_business_equivalency"("p_scope_line_id" "uuid", "p_confirmed" boolean) TO "service_role";
GRANT ALL ON FUNCTION "public"."confirm_business_equivalency"("p_scope_line_id" "uuid", "p_confirmed" boolean) TO "authenticated";



REVOKE ALL ON FUNCTION "public"."correct_savings_execution"("p_calc_id" "uuid", "p_note" "text", "p_calculation" "jsonb", "p_periods" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."correct_savings_execution"("p_calc_id" "uuid", "p_note" "text", "p_calculation" "jsonb", "p_periods" "jsonb") TO "service_role";
GRANT ALL ON FUNCTION "public"."correct_savings_execution"("p_calc_id" "uuid", "p_note" "text", "p_calculation" "jsonb", "p_periods" "jsonb") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."current_org_id"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."current_org_id"() TO "service_role";
GRANT ALL ON FUNCTION "public"."current_org_id"() TO "authenticated";



REVOKE ALL ON FUNCTION "public"."derive_realization_period_fields"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."derive_realization_period_fields"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."derive_realization_status"("p_projected_reduction" numeric, "p_projected_avoidance" numeric, "p_realized_reduction" numeric, "p_realized_avoidance" numeric) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."derive_realization_status"("p_projected_reduction" numeric, "p_projected_avoidance" numeric, "p_realized_reduction" numeric, "p_realized_avoidance" numeric) TO "service_role";
GRANT ALL ON FUNCTION "public"."derive_realization_status"("p_projected_reduction" numeric, "p_projected_avoidance" numeric, "p_realized_reduction" numeric, "p_realized_avoidance" numeric) TO "authenticated";



REVOKE ALL ON FUNCTION "public"."enforce_completed_project_savings_disposition"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."enforce_completed_project_savings_disposition"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."enforce_project_business_unit_setting"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."enforce_project_business_unit_setting"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."enforce_project_category_setting"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."enforce_project_category_setting"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."enforce_project_choice_options"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."enforce_project_choice_options"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."enforce_project_cost_center_setting"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."enforce_project_cost_center_setting"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."enforce_project_description_setting"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."enforce_project_description_setting"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."enforce_project_incumbent_supplier_setting"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."enforce_project_incumbent_supplier_setting"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."enforce_project_owner_setting"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."enforce_project_owner_setting"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."enforce_project_updates_setting"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."enforce_project_updates_setting"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."enforce_savings_completion_invariant"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."enforce_savings_completion_invariant"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."enforce_savings_execution_invariant"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."enforce_savings_execution_invariant"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."enforce_savings_realization_setting"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."enforce_savings_realization_setting"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."enforce_sourcing_project_savings"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."enforce_sourcing_project_savings"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."enforce_support_project_setting"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."enforce_support_project_setting"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."handle_new_user"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."handle_new_user"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."mark_savings_schedule_executed"("p_savings_calculation_id" "uuid", "p_execution_note" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."mark_savings_schedule_executed"("p_savings_calculation_id" "uuid", "p_execution_note" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."mark_savings_schedule_executed"("p_savings_calculation_id" "uuid", "p_execution_note" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."normalize_project_choice_option"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."normalize_project_choice_option"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."prevent_last_project_choice_archive"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."prevent_last_project_choice_archive"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."prevent_profile_privilege_change"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."prevent_profile_privilege_change"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."prevent_realization_history_delete"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."prevent_realization_history_delete"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."protect_sourcing_completion_status"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."protect_sourcing_completion_status"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."replace_savings_schedule"("p_savings_calculation_id" "uuid", "p_schedule_start_month" integer, "p_schedule_start_year" integer, "p_schedule_period_type" "text", "p_periods" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."replace_savings_schedule"("p_savings_calculation_id" "uuid", "p_schedule_start_month" integer, "p_schedule_start_year" integer, "p_schedule_period_type" "text", "p_periods" "jsonb") TO "service_role";
GRANT ALL ON FUNCTION "public"."replace_savings_schedule"("p_savings_calculation_id" "uuid", "p_schedule_start_month" integer, "p_schedule_start_year" integer, "p_schedule_period_type" "text", "p_periods" "jsonb") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."reverse_savings_execution"("p_calc_id" "uuid", "p_note" "text", "p_disposition_action" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."reverse_savings_execution"("p_calc_id" "uuid", "p_note" "text", "p_disposition_action" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."reverse_savings_execution"("p_calc_id" "uuid", "p_note" "text", "p_disposition_action" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."select_baseline"("p_baseline_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."select_baseline"("p_baseline_id" "uuid") TO "service_role";
GRANT ALL ON FUNCTION "public"."select_baseline"("p_baseline_id" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."set_finance_validation"("p_realization_period_id" "uuid", "p_validated" boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."set_finance_validation"("p_realization_period_id" "uuid", "p_validated" boolean) TO "service_role";
GRANT ALL ON FUNCTION "public"."set_finance_validation"("p_realization_period_id" "uuid", "p_validated" boolean) TO "authenticated";



REVOKE ALL ON FUNCTION "public"."set_hard_reduction_override"("p_baseline_id" "uuid", "p_enabled" boolean, "p_reason" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."set_hard_reduction_override"("p_baseline_id" "uuid", "p_enabled" boolean, "p_reason" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."set_hard_reduction_override"("p_baseline_id" "uuid", "p_enabled" boolean, "p_reason" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."set_offer_role"("p_offer_id" "uuid", "p_role" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."set_offer_role"("p_offer_id" "uuid", "p_role" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."set_offer_role"("p_offer_id" "uuid", "p_role" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."set_single_primary_supplier_contact"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."set_single_primary_supplier_contact"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."set_supplier_normalized_name"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."set_supplier_normalized_name"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."stamp_money_record_actor"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."stamp_money_record_actor"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."stamp_supplier_certification_actor"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."stamp_supplier_certification_actor"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."stamp_supplier_contact_actor"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."stamp_supplier_contact_actor"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."stamp_supplier_note_actor"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."stamp_supplier_note_actor"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."stamp_supplier_performance_review_actor"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."stamp_supplier_performance_review_actor"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."stamp_supplier_risk_actor"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."stamp_supplier_risk_actor"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."sync_realization_periods"("p_event_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."sync_realization_periods"("p_event_id" "uuid") TO "service_role";
GRANT ALL ON FUNCTION "public"."sync_realization_periods"("p_event_id" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."update_updated_at"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."update_updated_at"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."update_workspace_settings"("p_organization_name" "text", "p_full_name" "text", "p_currency_code" "text", "p_locale" "text", "p_timezone" "text", "p_fiscal_year_start_month" integer, "p_date_format" "text", "p_default_recognition_method" "text", "p_require_baseline" boolean, "p_hard_reduction_approval_threshold" numeric) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."update_workspace_settings"("p_organization_name" "text", "p_full_name" "text", "p_currency_code" "text", "p_locale" "text", "p_timezone" "text", "p_fiscal_year_start_month" integer, "p_date_format" "text", "p_default_recognition_method" "text", "p_require_baseline" boolean, "p_hard_reduction_approval_threshold" numeric) TO "service_role";



REVOKE ALL ON FUNCTION "public"."update_workspace_settings"("p_organization_name" "text", "p_full_name" "text", "p_currency_code" "text", "p_locale" "text", "p_timezone" "text", "p_fiscal_year_start_month" integer, "p_date_format" "text", "p_default_recognition_method" "text", "p_require_baseline" boolean, "p_hard_reduction_approval_threshold" numeric, "p_support_projects_enabled" boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."update_workspace_settings"("p_organization_name" "text", "p_full_name" "text", "p_currency_code" "text", "p_locale" "text", "p_timezone" "text", "p_fiscal_year_start_month" integer, "p_date_format" "text", "p_default_recognition_method" "text", "p_require_baseline" boolean, "p_hard_reduction_approval_threshold" numeric, "p_support_projects_enabled" boolean) TO "service_role";



REVOKE ALL ON FUNCTION "public"."update_workspace_settings_v2"("p_organization_name" "text", "p_full_name" "text", "p_currency_code" "text", "p_locale" "text", "p_timezone" "text", "p_fiscal_year_start_month" integer, "p_date_format" "text", "p_default_recognition_method" "text", "p_require_baseline" boolean, "p_hard_reduction_approval_threshold" numeric, "p_support_projects_enabled" boolean, "p_project_descriptions_enabled" boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."update_workspace_settings_v2"("p_organization_name" "text", "p_full_name" "text", "p_currency_code" "text", "p_locale" "text", "p_timezone" "text", "p_fiscal_year_start_month" integer, "p_date_format" "text", "p_default_recognition_method" "text", "p_require_baseline" boolean, "p_hard_reduction_approval_threshold" numeric, "p_support_projects_enabled" boolean, "p_project_descriptions_enabled" boolean) TO "service_role";



REVOKE ALL ON FUNCTION "public"."update_workspace_settings_v3"("p_organization_name" "text", "p_full_name" "text", "p_currency_code" "text", "p_locale" "text", "p_timezone" "text", "p_fiscal_year_start_month" integer, "p_date_format" "text", "p_default_recognition_method" "text", "p_require_baseline" boolean, "p_hard_reduction_approval_threshold" numeric, "p_support_projects_enabled" boolean, "p_project_descriptions_enabled" boolean, "p_project_owners_enabled" boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."update_workspace_settings_v3"("p_organization_name" "text", "p_full_name" "text", "p_currency_code" "text", "p_locale" "text", "p_timezone" "text", "p_fiscal_year_start_month" integer, "p_date_format" "text", "p_default_recognition_method" "text", "p_require_baseline" boolean, "p_hard_reduction_approval_threshold" numeric, "p_support_projects_enabled" boolean, "p_project_descriptions_enabled" boolean, "p_project_owners_enabled" boolean) TO "service_role";



REVOKE ALL ON FUNCTION "public"."update_workspace_settings_v4"("p_organization_name" "text", "p_full_name" "text", "p_currency_code" "text", "p_locale" "text", "p_timezone" "text", "p_fiscal_year_start_month" integer, "p_date_format" "text", "p_default_recognition_method" "text", "p_require_baseline" boolean, "p_hard_reduction_approval_threshold" numeric, "p_support_projects_enabled" boolean, "p_project_descriptions_enabled" boolean, "p_project_owners_enabled" boolean, "p_project_cost_centers_enabled" boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."update_workspace_settings_v4"("p_organization_name" "text", "p_full_name" "text", "p_currency_code" "text", "p_locale" "text", "p_timezone" "text", "p_fiscal_year_start_month" integer, "p_date_format" "text", "p_default_recognition_method" "text", "p_require_baseline" boolean, "p_hard_reduction_approval_threshold" numeric, "p_support_projects_enabled" boolean, "p_project_descriptions_enabled" boolean, "p_project_owners_enabled" boolean, "p_project_cost_centers_enabled" boolean) TO "service_role";



REVOKE ALL ON FUNCTION "public"."update_workspace_settings_v5"("p_organization_name" "text", "p_full_name" "text", "p_currency_code" "text", "p_locale" "text", "p_timezone" "text", "p_fiscal_year_start_month" integer, "p_date_format" "text", "p_default_recognition_method" "text", "p_require_baseline" boolean, "p_hard_reduction_approval_threshold" numeric, "p_support_projects_enabled" boolean, "p_project_descriptions_enabled" boolean, "p_project_owners_enabled" boolean, "p_project_cost_centers_enabled" boolean, "p_project_categories_enabled" boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."update_workspace_settings_v5"("p_organization_name" "text", "p_full_name" "text", "p_currency_code" "text", "p_locale" "text", "p_timezone" "text", "p_fiscal_year_start_month" integer, "p_date_format" "text", "p_default_recognition_method" "text", "p_require_baseline" boolean, "p_hard_reduction_approval_threshold" numeric, "p_support_projects_enabled" boolean, "p_project_descriptions_enabled" boolean, "p_project_owners_enabled" boolean, "p_project_cost_centers_enabled" boolean, "p_project_categories_enabled" boolean) TO "service_role";



REVOKE ALL ON FUNCTION "public"."update_workspace_settings_v6"("p_organization_name" "text", "p_full_name" "text", "p_currency_code" "text", "p_locale" "text", "p_timezone" "text", "p_fiscal_year_start_month" integer, "p_date_format" "text", "p_default_recognition_method" "text", "p_require_baseline" boolean, "p_hard_reduction_approval_threshold" numeric, "p_support_projects_enabled" boolean, "p_project_descriptions_enabled" boolean, "p_project_owners_enabled" boolean, "p_project_cost_centers_enabled" boolean, "p_project_categories_enabled" boolean, "p_project_business_units_enabled" boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."update_workspace_settings_v6"("p_organization_name" "text", "p_full_name" "text", "p_currency_code" "text", "p_locale" "text", "p_timezone" "text", "p_fiscal_year_start_month" integer, "p_date_format" "text", "p_default_recognition_method" "text", "p_require_baseline" boolean, "p_hard_reduction_approval_threshold" numeric, "p_support_projects_enabled" boolean, "p_project_descriptions_enabled" boolean, "p_project_owners_enabled" boolean, "p_project_cost_centers_enabled" boolean, "p_project_categories_enabled" boolean, "p_project_business_units_enabled" boolean) TO "service_role";



REVOKE ALL ON FUNCTION "public"."update_workspace_settings_v7"("p_organization_name" "text", "p_full_name" "text", "p_currency_code" "text", "p_locale" "text", "p_timezone" "text", "p_fiscal_year_start_month" integer, "p_date_format" "text", "p_default_recognition_method" "text", "p_require_baseline" boolean, "p_hard_reduction_approval_threshold" numeric, "p_support_projects_enabled" boolean, "p_project_descriptions_enabled" boolean, "p_project_owners_enabled" boolean, "p_project_cost_centers_enabled" boolean, "p_project_categories_enabled" boolean, "p_project_business_units_enabled" boolean, "p_project_updates_enabled" boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."update_workspace_settings_v7"("p_organization_name" "text", "p_full_name" "text", "p_currency_code" "text", "p_locale" "text", "p_timezone" "text", "p_fiscal_year_start_month" integer, "p_date_format" "text", "p_default_recognition_method" "text", "p_require_baseline" boolean, "p_hard_reduction_approval_threshold" numeric, "p_support_projects_enabled" boolean, "p_project_descriptions_enabled" boolean, "p_project_owners_enabled" boolean, "p_project_cost_centers_enabled" boolean, "p_project_categories_enabled" boolean, "p_project_business_units_enabled" boolean, "p_project_updates_enabled" boolean) TO "service_role";



REVOKE ALL ON FUNCTION "public"."update_workspace_settings_v8"("p_organization_name" "text", "p_full_name" "text", "p_currency_code" "text", "p_locale" "text", "p_timezone" "text", "p_fiscal_year_start_month" integer, "p_date_format" "text", "p_default_recognition_method" "text", "p_require_baseline" boolean, "p_hard_reduction_approval_threshold" numeric, "p_support_projects_enabled" boolean, "p_project_descriptions_enabled" boolean, "p_project_owners_enabled" boolean, "p_project_cost_centers_enabled" boolean, "p_project_categories_enabled" boolean, "p_project_business_units_enabled" boolean, "p_project_updates_enabled" boolean, "p_project_incumbent_suppliers_enabled" boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."update_workspace_settings_v8"("p_organization_name" "text", "p_full_name" "text", "p_currency_code" "text", "p_locale" "text", "p_timezone" "text", "p_fiscal_year_start_month" integer, "p_date_format" "text", "p_default_recognition_method" "text", "p_require_baseline" boolean, "p_hard_reduction_approval_threshold" numeric, "p_support_projects_enabled" boolean, "p_project_descriptions_enabled" boolean, "p_project_owners_enabled" boolean, "p_project_cost_centers_enabled" boolean, "p_project_categories_enabled" boolean, "p_project_business_units_enabled" boolean, "p_project_updates_enabled" boolean, "p_project_incumbent_suppliers_enabled" boolean) TO "service_role";



REVOKE ALL ON FUNCTION "public"."update_workspace_settings_v9"("p_organization_name" "text", "p_full_name" "text", "p_currency_code" "text", "p_locale" "text", "p_timezone" "text", "p_fiscal_year_start_month" integer, "p_date_format" "text", "p_default_recognition_method" "text", "p_require_baseline" boolean, "p_hard_reduction_approval_threshold" numeric, "p_support_projects_enabled" boolean, "p_project_descriptions_enabled" boolean, "p_project_owners_enabled" boolean, "p_project_cost_centers_enabled" boolean, "p_project_categories_enabled" boolean, "p_project_business_units_enabled" boolean, "p_project_updates_enabled" boolean, "p_project_incumbent_suppliers_enabled" boolean, "p_savings_realization_enabled" boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."update_workspace_settings_v9"("p_organization_name" "text", "p_full_name" "text", "p_currency_code" "text", "p_locale" "text", "p_timezone" "text", "p_fiscal_year_start_month" integer, "p_date_format" "text", "p_default_recognition_method" "text", "p_require_baseline" boolean, "p_hard_reduction_approval_threshold" numeric, "p_support_projects_enabled" boolean, "p_project_descriptions_enabled" boolean, "p_project_owners_enabled" boolean, "p_project_cost_centers_enabled" boolean, "p_project_categories_enabled" boolean, "p_project_business_units_enabled" boolean, "p_project_updates_enabled" boolean, "p_project_incumbent_suppliers_enabled" boolean, "p_savings_realization_enabled" boolean) TO "service_role";
GRANT ALL ON FUNCTION "public"."update_workspace_settings_v9"("p_organization_name" "text", "p_full_name" "text", "p_currency_code" "text", "p_locale" "text", "p_timezone" "text", "p_fiscal_year_start_month" integer, "p_date_format" "text", "p_default_recognition_method" "text", "p_require_baseline" boolean, "p_hard_reduction_approval_threshold" numeric, "p_support_projects_enabled" boolean, "p_project_descriptions_enabled" boolean, "p_project_owners_enabled" boolean, "p_project_cost_centers_enabled" boolean, "p_project_categories_enabled" boolean, "p_project_business_units_enabled" boolean, "p_project_updates_enabled" boolean, "p_project_incumbent_suppliers_enabled" boolean, "p_savings_realization_enabled" boolean) TO "authenticated";



GRANT ALL ON TABLE "public"."audit_log" TO "service_role";
GRANT SELECT ON TABLE "public"."audit_log" TO "authenticated";



GRANT ALL ON TABLE "public"."award_lines" TO "service_role";
GRANT SELECT,DELETE ON TABLE "public"."award_lines" TO "authenticated";



GRANT INSERT("id") ON TABLE "public"."award_lines" TO "authenticated";



GRANT INSERT("organization_id") ON TABLE "public"."award_lines" TO "authenticated";



GRANT INSERT("award_id") ON TABLE "public"."award_lines" TO "authenticated";



GRANT INSERT("event_id") ON TABLE "public"."award_lines" TO "authenticated";



GRANT INSERT("scope_line_id"),UPDATE("scope_line_id") ON TABLE "public"."award_lines" TO "authenticated";



GRANT INSERT("line_number"),UPDATE("line_number") ON TABLE "public"."award_lines" TO "authenticated";



GRANT INSERT("awarded_unit_price"),UPDATE("awarded_unit_price") ON TABLE "public"."award_lines" TO "authenticated";



GRANT INSERT("awarded_quantity"),UPDATE("awarded_quantity") ON TABLE "public"."award_lines" TO "authenticated";



GRANT INSERT("awarded_extended_amount"),UPDATE("awarded_extended_amount") ON TABLE "public"."award_lines" TO "authenticated";



GRANT INSERT("awarded_recurring_amount"),UPDATE("awarded_recurring_amount") ON TABLE "public"."award_lines" TO "authenticated";



GRANT INSERT("awarded_one_time_amount"),UPDATE("awarded_one_time_amount") ON TABLE "public"."award_lines" TO "authenticated";



GRANT INSERT("awarded_term_months"),UPDATE("awarded_term_months") ON TABLE "public"."award_lines" TO "authenticated";



GRANT INSERT("annualized_award_amount"),UPDATE("annualized_award_amount") ON TABLE "public"."award_lines" TO "authenticated";



GRANT ALL ON TABLE "public"."awards" TO "service_role";
GRANT SELECT,DELETE ON TABLE "public"."awards" TO "authenticated";



GRANT INSERT("id") ON TABLE "public"."awards" TO "authenticated";



GRANT INSERT("organization_id") ON TABLE "public"."awards" TO "authenticated";



GRANT INSERT("event_id") ON TABLE "public"."awards" TO "authenticated";



GRANT INSERT("supplier_id"),UPDATE("supplier_id") ON TABLE "public"."awards" TO "authenticated";



GRANT INSERT("offer_id"),UPDATE("offer_id") ON TABLE "public"."awards" TO "authenticated";



GRANT INSERT("award_name"),UPDATE("award_name") ON TABLE "public"."awards" TO "authenticated";



GRANT INSERT("award_date"),UPDATE("award_date") ON TABLE "public"."awards" TO "authenticated";



GRANT INSERT("award_total_amount"),UPDATE("award_total_amount") ON TABLE "public"."awards" TO "authenticated";



GRANT INSERT("award_status"),UPDATE("award_status") ON TABLE "public"."awards" TO "authenticated";



GRANT INSERT("award_notes"),UPDATE("award_notes") ON TABLE "public"."awards" TO "authenticated";



GRANT ALL ON TABLE "public"."baseline_lines" TO "service_role";
GRANT SELECT,DELETE ON TABLE "public"."baseline_lines" TO "authenticated";



GRANT INSERT("id") ON TABLE "public"."baseline_lines" TO "authenticated";



GRANT INSERT("organization_id") ON TABLE "public"."baseline_lines" TO "authenticated";



GRANT INSERT("baseline_id") ON TABLE "public"."baseline_lines" TO "authenticated";



GRANT INSERT("event_id") ON TABLE "public"."baseline_lines" TO "authenticated";



GRANT INSERT("scope_line_id"),UPDATE("scope_line_id") ON TABLE "public"."baseline_lines" TO "authenticated";



GRANT INSERT("line_number"),UPDATE("line_number") ON TABLE "public"."baseline_lines" TO "authenticated";



GRANT INSERT("baseline_unit_price"),UPDATE("baseline_unit_price") ON TABLE "public"."baseline_lines" TO "authenticated";



GRANT INSERT("baseline_quantity"),UPDATE("baseline_quantity") ON TABLE "public"."baseline_lines" TO "authenticated";



GRANT INSERT("baseline_extended_amount"),UPDATE("baseline_extended_amount") ON TABLE "public"."baseline_lines" TO "authenticated";



GRANT INSERT("baseline_recurring_amount"),UPDATE("baseline_recurring_amount") ON TABLE "public"."baseline_lines" TO "authenticated";



GRANT INSERT("baseline_one_time_amount"),UPDATE("baseline_one_time_amount") ON TABLE "public"."baseline_lines" TO "authenticated";



GRANT INSERT("baseline_term_months"),UPDATE("baseline_term_months") ON TABLE "public"."baseline_lines" TO "authenticated";



GRANT INSERT("annualized_baseline_amount"),UPDATE("annualized_baseline_amount") ON TABLE "public"."baseline_lines" TO "authenticated";



GRANT INSERT("normalized_quantity"),UPDATE("normalized_quantity") ON TABLE "public"."baseline_lines" TO "authenticated";



GRANT INSERT("normalized_unit_price"),UPDATE("normalized_unit_price") ON TABLE "public"."baseline_lines" TO "authenticated";



GRANT INSERT("normalized_extended_amount"),UPDATE("normalized_extended_amount") ON TABLE "public"."baseline_lines" TO "authenticated";



GRANT INSERT("tax_amount_included"),UPDATE("tax_amount_included") ON TABLE "public"."baseline_lines" TO "authenticated";



GRANT INSERT("freight_amount_included"),UPDATE("freight_amount_included") ON TABLE "public"."baseline_lines" TO "authenticated";



GRANT INSERT("source_document_id"),UPDATE("source_document_id") ON TABLE "public"."baseline_lines" TO "authenticated";



GRANT INSERT("notes"),UPDATE("notes") ON TABLE "public"."baseline_lines" TO "authenticated";



GRANT ALL ON TABLE "public"."baselines" TO "service_role";
GRANT SELECT,DELETE ON TABLE "public"."baselines" TO "authenticated";



GRANT INSERT("id") ON TABLE "public"."baselines" TO "authenticated";



GRANT INSERT("organization_id") ON TABLE "public"."baselines" TO "authenticated";



GRANT INSERT("event_id") ON TABLE "public"."baselines" TO "authenticated";



GRANT INSERT("baseline_name"),UPDATE("baseline_name") ON TABLE "public"."baselines" TO "authenticated";



GRANT INSERT("baseline_type"),UPDATE("baseline_type") ON TABLE "public"."baselines" TO "authenticated";



GRANT INSERT("baseline_source"),UPDATE("baseline_source") ON TABLE "public"."baselines" TO "authenticated";



GRANT INSERT("baseline_period_start"),UPDATE("baseline_period_start") ON TABLE "public"."baselines" TO "authenticated";



GRANT INSERT("baseline_period_end"),UPDATE("baseline_period_end") ON TABLE "public"."baselines" TO "authenticated";



GRANT INSERT("baseline_currency_code"),UPDATE("baseline_currency_code") ON TABLE "public"."baselines" TO "authenticated";



GRANT INSERT("baseline_fx_rate_to_usd"),UPDATE("baseline_fx_rate_to_usd") ON TABLE "public"."baselines" TO "authenticated";



GRANT INSERT("baseline_total_amount"),UPDATE("baseline_total_amount") ON TABLE "public"."baselines" TO "authenticated";



GRANT INSERT("baseline_normalized_amount"),UPDATE("baseline_normalized_amount") ON TABLE "public"."baselines" TO "authenticated";



GRANT INSERT("normalization_notes"),UPDATE("normalization_notes") ON TABLE "public"."baselines" TO "authenticated";



GRANT INSERT("baseline_lock_status"),UPDATE("baseline_lock_status") ON TABLE "public"."baselines" TO "authenticated";



GRANT INSERT("baseline_lock_date"),UPDATE("baseline_lock_date") ON TABLE "public"."baselines" TO "authenticated";



GRANT INSERT("official_for_hard_savings"),UPDATE("official_for_hard_savings") ON TABLE "public"."baselines" TO "authenticated";



GRANT INSERT("official_for_cost_avoidance"),UPDATE("official_for_cost_avoidance") ON TABLE "public"."baselines" TO "authenticated";



GRANT INSERT("official_for_demand_reduction"),UPDATE("official_for_demand_reduction") ON TABLE "public"."baselines" TO "authenticated";



GRANT INSERT("baseline_term_months"),UPDATE("baseline_term_months") ON TABLE "public"."baselines" TO "authenticated";



GRANT ALL ON TABLE "public"."business_units" TO "service_role";
GRANT SELECT,INSERT,UPDATE ON TABLE "public"."business_units" TO "authenticated";



GRANT ALL ON TABLE "public"."categories" TO "service_role";
GRANT SELECT,INSERT,UPDATE ON TABLE "public"."categories" TO "authenticated";



GRANT ALL ON TABLE "public"."cost_centers" TO "service_role";
GRANT SELECT,INSERT,UPDATE ON TABLE "public"."cost_centers" TO "authenticated";



GRANT ALL ON TABLE "public"."event_scope_lines" TO "service_role";
GRANT SELECT,DELETE ON TABLE "public"."event_scope_lines" TO "authenticated";



GRANT INSERT("id") ON TABLE "public"."event_scope_lines" TO "authenticated";



GRANT INSERT("organization_id") ON TABLE "public"."event_scope_lines" TO "authenticated";



GRANT INSERT("event_id") ON TABLE "public"."event_scope_lines" TO "authenticated";



GRANT INSERT("line_number"),UPDATE("line_number") ON TABLE "public"."event_scope_lines" TO "authenticated";



GRANT INSERT("category_id"),UPDATE("category_id") ON TABLE "public"."event_scope_lines" TO "authenticated";



GRANT INSERT("item_service_name"),UPDATE("item_service_name") ON TABLE "public"."event_scope_lines" TO "authenticated";



GRANT INSERT("item_description"),UPDATE("item_description") ON TABLE "public"."event_scope_lines" TO "authenticated";



GRANT INSERT("uom"),UPDATE("uom") ON TABLE "public"."event_scope_lines" TO "authenticated";



GRANT INSERT("location_id"),UPDATE("location_id") ON TABLE "public"."event_scope_lines" TO "authenticated";



GRANT INSERT("baseline_quantity"),UPDATE("baseline_quantity") ON TABLE "public"."event_scope_lines" TO "authenticated";



GRANT INSERT("forecast_quantity"),UPDATE("forecast_quantity") ON TABLE "public"."event_scope_lines" TO "authenticated";



GRANT INSERT("final_quantity"),UPDATE("final_quantity") ON TABLE "public"."event_scope_lines" TO "authenticated";



GRANT INSERT("scope_change_flag"),UPDATE("scope_change_flag") ON TABLE "public"."event_scope_lines" TO "authenticated";



GRANT INSERT("scope_change_description"),UPDATE("scope_change_description") ON TABLE "public"."event_scope_lines" TO "authenticated";



GRANT ALL ON TABLE "public"."organization_settings" TO "service_role";
GRANT SELECT ON TABLE "public"."organization_settings" TO "authenticated";



GRANT ALL ON TABLE "public"."organizations" TO "service_role";
GRANT SELECT ON TABLE "public"."organizations" TO "authenticated";



GRANT ALL ON TABLE "public"."profiles" TO "service_role";
GRANT SELECT ON TABLE "public"."profiles" TO "authenticated";



GRANT ALL ON TABLE "public"."project_choice_options" TO "service_role";
GRANT SELECT,INSERT,UPDATE ON TABLE "public"."project_choice_options" TO "authenticated";



GRANT ALL ON TABLE "public"."project_updates" TO "service_role";
GRANT SELECT,INSERT ON TABLE "public"."project_updates" TO "authenticated";



GRANT ALL ON TABLE "public"."realization_periods" TO "service_role";
GRANT SELECT,DELETE ON TABLE "public"."realization_periods" TO "authenticated";



GRANT UPDATE("actual_amount") ON TABLE "public"."realization_periods" TO "authenticated";



GRANT UPDATE("leakage_reason") ON TABLE "public"."realization_periods" TO "authenticated";



GRANT UPDATE("evidence_document_id") ON TABLE "public"."realization_periods" TO "authenticated";



GRANT UPDATE("notes") ON TABLE "public"."realization_periods" TO "authenticated";



GRANT UPDATE("realized_reduction_amount") ON TABLE "public"."realization_periods" TO "authenticated";



GRANT UPDATE("realized_avoidance_amount") ON TABLE "public"."realization_periods" TO "authenticated";



GRANT ALL ON TABLE "public"."savings_calculation_lines" TO "service_role";
GRANT SELECT,DELETE ON TABLE "public"."savings_calculation_lines" TO "authenticated";



GRANT INSERT("id") ON TABLE "public"."savings_calculation_lines" TO "authenticated";



GRANT INSERT("organization_id") ON TABLE "public"."savings_calculation_lines" TO "authenticated";



GRANT INSERT("savings_calculation_id") ON TABLE "public"."savings_calculation_lines" TO "authenticated";



GRANT INSERT("event_id") ON TABLE "public"."savings_calculation_lines" TO "authenticated";



GRANT INSERT("scope_line_id"),UPDATE("scope_line_id") ON TABLE "public"."savings_calculation_lines" TO "authenticated";



GRANT INSERT("line_number"),UPDATE("line_number") ON TABLE "public"."savings_calculation_lines" TO "authenticated";



GRANT INSERT("baseline_unit_price"),UPDATE("baseline_unit_price") ON TABLE "public"."savings_calculation_lines" TO "authenticated";



GRANT INSERT("baseline_quantity"),UPDATE("baseline_quantity") ON TABLE "public"."savings_calculation_lines" TO "authenticated";



GRANT INSERT("baseline_extended_amount"),UPDATE("baseline_extended_amount") ON TABLE "public"."savings_calculation_lines" TO "authenticated";



GRANT INSERT("awarded_unit_price"),UPDATE("awarded_unit_price") ON TABLE "public"."savings_calculation_lines" TO "authenticated";



GRANT INSERT("awarded_quantity"),UPDATE("awarded_quantity") ON TABLE "public"."savings_calculation_lines" TO "authenticated";



GRANT INSERT("awarded_extended_amount"),UPDATE("awarded_extended_amount") ON TABLE "public"."savings_calculation_lines" TO "authenticated";



GRANT INSERT("savings_amount"),UPDATE("savings_amount") ON TABLE "public"."savings_calculation_lines" TO "authenticated";



GRANT INSERT("savings_percentage"),UPDATE("savings_percentage") ON TABLE "public"."savings_calculation_lines" TO "authenticated";



GRANT INSERT("savings_type"),UPDATE("savings_type") ON TABLE "public"."savings_calculation_lines" TO "authenticated";



GRANT ALL ON TABLE "public"."savings_calculations" TO "service_role";
GRANT SELECT,DELETE ON TABLE "public"."savings_calculations" TO "authenticated";



GRANT INSERT("id") ON TABLE "public"."savings_calculations" TO "authenticated";



GRANT INSERT("organization_id") ON TABLE "public"."savings_calculations" TO "authenticated";



GRANT INSERT("event_id") ON TABLE "public"."savings_calculations" TO "authenticated";



GRANT INSERT("baseline_id"),UPDATE("baseline_id") ON TABLE "public"."savings_calculations" TO "authenticated";



GRANT INSERT("award_id"),UPDATE("award_id") ON TABLE "public"."savings_calculations" TO "authenticated";



GRANT INSERT("calculation_name"),UPDATE("calculation_name") ON TABLE "public"."savings_calculations" TO "authenticated";



GRANT INSERT("savings_type"),UPDATE("savings_type") ON TABLE "public"."savings_calculations" TO "authenticated";



GRANT INSERT("baseline_total_amount"),UPDATE("baseline_total_amount") ON TABLE "public"."savings_calculations" TO "authenticated";



GRANT INSERT("award_total_amount"),UPDATE("award_total_amount") ON TABLE "public"."savings_calculations" TO "authenticated";



GRANT INSERT("gross_savings_amount"),UPDATE("gross_savings_amount") ON TABLE "public"."savings_calculations" TO "authenticated";



GRANT INSERT("savings_percentage"),UPDATE("savings_percentage") ON TABLE "public"."savings_calculations" TO "authenticated";



GRANT INSERT("net_savings_amount"),UPDATE("net_savings_amount") ON TABLE "public"."savings_calculations" TO "authenticated";



GRANT INSERT("recognition_notes"),UPDATE("recognition_notes") ON TABLE "public"."savings_calculations" TO "authenticated";



GRANT INSERT("savings_start_date"),UPDATE("savings_start_date") ON TABLE "public"."savings_calculations" TO "authenticated";



GRANT INSERT("savings_end_date"),UPDATE("savings_end_date") ON TABLE "public"."savings_calculations" TO "authenticated";



GRANT INSERT("cost_reduction_amount"),UPDATE("cost_reduction_amount") ON TABLE "public"."savings_calculations" TO "authenticated";



GRANT INSERT("cost_avoidance_amount"),UPDATE("cost_avoidance_amount") ON TABLE "public"."savings_calculations" TO "authenticated";



GRANT INSERT("opening_proposal_amount"),UPDATE("opening_proposal_amount") ON TABLE "public"."savings_calculations" TO "authenticated";



GRANT INSERT("schedule_start_month"),UPDATE("schedule_start_month") ON TABLE "public"."savings_calculations" TO "authenticated";



GRANT INSERT("schedule_start_year"),UPDATE("schedule_start_year") ON TABLE "public"."savings_calculations" TO "authenticated";



GRANT INSERT("schedule_period_type"),UPDATE("schedule_period_type") ON TABLE "public"."savings_calculations" TO "authenticated";



GRANT INSERT("schedule_period_count"),UPDATE("schedule_period_count") ON TABLE "public"."savings_calculations" TO "authenticated";



GRANT ALL ON TABLE "public"."savings_periods" TO "service_role";
GRANT SELECT ON TABLE "public"."savings_periods" TO "authenticated";



GRANT UPDATE("baseline_amount") ON TABLE "public"."savings_periods" TO "authenticated";



GRANT UPDATE("opening_amount") ON TABLE "public"."savings_periods" TO "authenticated";



GRANT UPDATE("final_amount") ON TABLE "public"."savings_periods" TO "authenticated";



GRANT UPDATE("cost_reduction_amount") ON TABLE "public"."savings_periods" TO "authenticated";



GRANT UPDATE("cost_avoidance_amount") ON TABLE "public"."savings_periods" TO "authenticated";



GRANT UPDATE("total_savings_amount") ON TABLE "public"."savings_periods" TO "authenticated";



GRANT UPDATE("is_edited") ON TABLE "public"."savings_periods" TO "authenticated";



GRANT UPDATE("notes") ON TABLE "public"."savings_periods" TO "authenticated";



GRANT ALL ON TABLE "public"."sourcing_events" TO "service_role";
GRANT SELECT,DELETE ON TABLE "public"."sourcing_events" TO "authenticated";



GRANT INSERT("id") ON TABLE "public"."sourcing_events" TO "authenticated";



GRANT INSERT("organization_id") ON TABLE "public"."sourcing_events" TO "authenticated";



GRANT INSERT("event_name"),UPDATE("event_name") ON TABLE "public"."sourcing_events" TO "authenticated";



GRANT INSERT("event_description"),UPDATE("event_description") ON TABLE "public"."sourcing_events" TO "authenticated";



GRANT INSERT("event_type"),UPDATE("event_type") ON TABLE "public"."sourcing_events" TO "authenticated";



GRANT INSERT("sourcing_method"),UPDATE("sourcing_method") ON TABLE "public"."sourcing_events" TO "authenticated";



GRANT INSERT("category_id"),UPDATE("category_id") ON TABLE "public"."sourcing_events" TO "authenticated";



GRANT INSERT("business_unit_id"),UPDATE("business_unit_id") ON TABLE "public"."sourcing_events" TO "authenticated";



GRANT INSERT("cost_center_id"),UPDATE("cost_center_id") ON TABLE "public"."sourcing_events" TO "authenticated";



GRANT INSERT("incumbent_supplier_id"),UPDATE("incumbent_supplier_id") ON TABLE "public"."sourcing_events" TO "authenticated";



GRANT INSERT("procurement_owner_id"),UPDATE("procurement_owner_id") ON TABLE "public"."sourcing_events" TO "authenticated";



GRANT INSERT("business_owner_id"),UPDATE("business_owner_id") ON TABLE "public"."sourcing_events" TO "authenticated";



GRANT INSERT("finance_owner_id"),UPDATE("finance_owner_id") ON TABLE "public"."sourcing_events" TO "authenticated";



GRANT INSERT("event_status"),UPDATE("event_status") ON TABLE "public"."sourcing_events" TO "authenticated";



GRANT INSERT("currency_code"),UPDATE("currency_code") ON TABLE "public"."sourcing_events" TO "authenticated";



GRANT INSERT("fx_rate_to_usd"),UPDATE("fx_rate_to_usd") ON TABLE "public"."sourcing_events" TO "authenticated";



GRANT INSERT("event_start_date"),UPDATE("event_start_date") ON TABLE "public"."sourcing_events" TO "authenticated";



GRANT INSERT("event_close_date"),UPDATE("event_close_date") ON TABLE "public"."sourcing_events" TO "authenticated";



GRANT INSERT("contract_start_date"),UPDATE("contract_start_date") ON TABLE "public"."sourcing_events" TO "authenticated";



GRANT INSERT("contract_end_date"),UPDATE("contract_end_date") ON TABLE "public"."sourcing_events" TO "authenticated";



GRANT INSERT("recognition_start_date"),UPDATE("recognition_start_date") ON TABLE "public"."sourcing_events" TO "authenticated";



GRANT INSERT("recognition_end_date"),UPDATE("recognition_end_date") ON TABLE "public"."sourcing_events" TO "authenticated";



GRANT INSERT("official_reporting_basis"),UPDATE("official_reporting_basis") ON TABLE "public"."sourcing_events" TO "authenticated";



GRANT INSERT("project_type"),UPDATE("project_type") ON TABLE "public"."sourcing_events" TO "authenticated";



GRANT INSERT("buyer_name"),UPDATE("buyer_name") ON TABLE "public"."sourcing_events" TO "authenticated";



GRANT INSERT("notes"),UPDATE("notes") ON TABLE "public"."sourcing_events" TO "authenticated";



GRANT INSERT("project_due_date"),UPDATE("project_due_date") ON TABLE "public"."sourcing_events" TO "authenticated";



GRANT ALL ON TABLE "public"."supplier_certifications" TO "service_role";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."supplier_certifications" TO "authenticated";



GRANT ALL ON TABLE "public"."supplier_contacts" TO "service_role";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."supplier_contacts" TO "authenticated";



GRANT ALL ON TABLE "public"."supplier_notes" TO "service_role";
GRANT SELECT,INSERT ON TABLE "public"."supplier_notes" TO "authenticated";



GRANT ALL ON TABLE "public"."supplier_offer_lines" TO "service_role";
GRANT SELECT,DELETE ON TABLE "public"."supplier_offer_lines" TO "authenticated";



GRANT INSERT("id") ON TABLE "public"."supplier_offer_lines" TO "authenticated";



GRANT INSERT("organization_id") ON TABLE "public"."supplier_offer_lines" TO "authenticated";



GRANT INSERT("offer_id") ON TABLE "public"."supplier_offer_lines" TO "authenticated";



GRANT INSERT("event_id") ON TABLE "public"."supplier_offer_lines" TO "authenticated";



GRANT INSERT("scope_line_id"),UPDATE("scope_line_id") ON TABLE "public"."supplier_offer_lines" TO "authenticated";



GRANT INSERT("line_number"),UPDATE("line_number") ON TABLE "public"."supplier_offer_lines" TO "authenticated";



GRANT INSERT("offer_unit_price"),UPDATE("offer_unit_price") ON TABLE "public"."supplier_offer_lines" TO "authenticated";



GRANT INSERT("offer_quantity"),UPDATE("offer_quantity") ON TABLE "public"."supplier_offer_lines" TO "authenticated";



GRANT INSERT("offer_extended_amount"),UPDATE("offer_extended_amount") ON TABLE "public"."supplier_offer_lines" TO "authenticated";



GRANT INSERT("offer_recurring_amount"),UPDATE("offer_recurring_amount") ON TABLE "public"."supplier_offer_lines" TO "authenticated";



GRANT INSERT("offer_one_time_amount"),UPDATE("offer_one_time_amount") ON TABLE "public"."supplier_offer_lines" TO "authenticated";



GRANT INSERT("offer_term_months"),UPDATE("offer_term_months") ON TABLE "public"."supplier_offer_lines" TO "authenticated";



GRANT INSERT("annualized_offer_amount"),UPDATE("annualized_offer_amount") ON TABLE "public"."supplier_offer_lines" TO "authenticated";



GRANT INSERT("compliance_status"),UPDATE("compliance_status") ON TABLE "public"."supplier_offer_lines" TO "authenticated";



GRANT INSERT("exclusion_notes"),UPDATE("exclusion_notes") ON TABLE "public"."supplier_offer_lines" TO "authenticated";



GRANT ALL ON TABLE "public"."supplier_offers" TO "service_role";
GRANT SELECT,DELETE ON TABLE "public"."supplier_offers" TO "authenticated";



GRANT INSERT("id") ON TABLE "public"."supplier_offers" TO "authenticated";



GRANT INSERT("organization_id") ON TABLE "public"."supplier_offers" TO "authenticated";



GRANT INSERT("event_id") ON TABLE "public"."supplier_offers" TO "authenticated";



GRANT INSERT("supplier_id"),UPDATE("supplier_id") ON TABLE "public"."supplier_offers" TO "authenticated";



GRANT INSERT("offer_type"),UPDATE("offer_type") ON TABLE "public"."supplier_offers" TO "authenticated";



GRANT INSERT("offer_round"),UPDATE("offer_round") ON TABLE "public"."supplier_offers" TO "authenticated";



GRANT INSERT("offer_date"),UPDATE("offer_date") ON TABLE "public"."supplier_offers" TO "authenticated";



GRANT INSERT("offer_currency_code"),UPDATE("offer_currency_code") ON TABLE "public"."supplier_offers" TO "authenticated";



GRANT INSERT("fx_rate_to_usd"),UPDATE("fx_rate_to_usd") ON TABLE "public"."supplier_offers" TO "authenticated";



GRANT INSERT("offer_total_amount"),UPDATE("offer_total_amount") ON TABLE "public"."supplier_offers" TO "authenticated";



GRANT INSERT("offer_valid_until"),UPDATE("offer_valid_until") ON TABLE "public"."supplier_offers" TO "authenticated";



GRANT INSERT("compliant_bid_flag"),UPDATE("compliant_bid_flag") ON TABLE "public"."supplier_offers" TO "authenticated";



GRANT INSERT("selected_for_award_flag"),UPDATE("selected_for_award_flag") ON TABLE "public"."supplier_offers" TO "authenticated";



GRANT INSERT("source_document_id"),UPDATE("source_document_id") ON TABLE "public"."supplier_offers" TO "authenticated";



GRANT INSERT("notes"),UPDATE("notes") ON TABLE "public"."supplier_offers" TO "authenticated";



GRANT INSERT("offer_term_months"),UPDATE("offer_term_months") ON TABLE "public"."supplier_offers" TO "authenticated";



GRANT ALL ON TABLE "public"."supplier_performance_reviews" TO "service_role";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."supplier_performance_reviews" TO "authenticated";



GRANT ALL ON TABLE "public"."supplier_risks" TO "service_role";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."supplier_risks" TO "authenticated";



GRANT ALL ON TABLE "public"."suppliers" TO "service_role";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."suppliers" TO "authenticated";



ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "service_role";
