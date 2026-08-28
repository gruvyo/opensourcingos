begin;

-- Modification 4A: protect money-core decision tuples and make record
-- provenance server-owned. Five detail tables predate the actor columns used
-- by their parent records, so add and conservatively backfill them first.

alter table public.event_scope_lines
  add column created_by uuid references public.profiles(id) on delete set null,
  add column updated_by uuid references public.profiles(id) on delete set null;
alter table public.baseline_lines
  add column created_by uuid references public.profiles(id) on delete set null,
  add column updated_by uuid references public.profiles(id) on delete set null;
alter table public.supplier_offer_lines
  add column created_by uuid references public.profiles(id) on delete set null,
  add column updated_by uuid references public.profiles(id) on delete set null;
alter table public.award_lines
  add column created_by uuid references public.profiles(id) on delete set null,
  add column updated_by uuid references public.profiles(id) on delete set null;
alter table public.savings_calculation_lines
  add column created_by uuid references public.profiles(id) on delete set null,
  add column updated_by uuid references public.profiles(id) on delete set null;

update public.event_scope_lines line
set created_by = event.created_by,
    updated_by = coalesce(event.updated_by, event.created_by)
from public.sourcing_events event
where event.id = line.event_id
  and event.organization_id = line.organization_id;

update public.baseline_lines line
set created_by = baseline.created_by,
    updated_by = coalesce(baseline.updated_by, baseline.created_by)
from public.baselines baseline
where baseline.id = line.baseline_id
  and baseline.organization_id = line.organization_id;

update public.supplier_offer_lines line
set created_by = offer.created_by,
    updated_by = coalesce(offer.updated_by, offer.created_by)
from public.supplier_offers offer
where offer.id = line.offer_id
  and offer.organization_id = line.organization_id;

update public.award_lines line
set created_by = award.created_by,
    updated_by = coalesce(award.updated_by, award.created_by)
from public.awards award
where award.id = line.award_id
  and award.organization_id = line.organization_id;

update public.savings_calculation_lines line
set created_by = calculation.created_by,
    updated_by = coalesce(calculation.updated_by, calculation.created_by)
from public.savings_calculations calculation
where calculation.id = line.savings_calculation_id
  and calculation.organization_id = line.organization_id;

create function public.stamp_money_record_actor()
returns trigger
language plpgsql
set search_path to 'pg_catalog', 'public'
as $$
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

revoke all on function public.stamp_money_record_actor()
  from public, anon, authenticated;
grant execute on function public.stamp_money_record_actor() to service_role;

create trigger sourcing_events_actor
before insert or update on public.sourcing_events
for each row execute function public.stamp_money_record_actor();
create trigger event_scope_lines_actor
before insert or update on public.event_scope_lines
for each row execute function public.stamp_money_record_actor();
create trigger baselines_actor
before insert or update on public.baselines
for each row execute function public.stamp_money_record_actor();
create trigger baseline_lines_actor
before insert or update on public.baseline_lines
for each row execute function public.stamp_money_record_actor();
create trigger supplier_offers_actor
before insert or update on public.supplier_offers
for each row execute function public.stamp_money_record_actor();
create trigger supplier_offer_lines_actor
before insert or update on public.supplier_offer_lines
for each row execute function public.stamp_money_record_actor();
create trigger awards_actor
before insert or update on public.awards
for each row execute function public.stamp_money_record_actor();
create trigger award_lines_actor
before insert or update on public.award_lines
for each row execute function public.stamp_money_record_actor();
create trigger savings_calculations_actor
before insert or update on public.savings_calculations
for each row execute function public.stamp_money_record_actor();
create trigger savings_calculation_lines_actor
before insert or update on public.savings_calculation_lines
for each row execute function public.stamp_money_record_actor();
create trigger savings_periods_actor
before insert or update on public.savings_periods
for each row execute function public.stamp_money_record_actor();
create trigger realization_periods_actor
before insert or update on public.realization_periods
for each row execute function public.stamp_money_record_actor();

-- Hard-reduction classification is one guarded decision tuple. The browser
-- supplies intent and reason only; the database supplies actor and timestamp.
create function public.set_hard_reduction_override(
  p_baseline_id uuid,
  p_enabled boolean,
  p_reason text default null
)
returns void
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $$
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

-- Business-equivalency confirmation is likewise a guarded tuple. Clearing a
-- confirmation clears its prior actor instead of leaving misleading history.
create function public.confirm_business_equivalency(
  p_scope_line_id uuid,
  p_confirmed boolean
)
returns void
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $$
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

-- Finance validation is intentionally admin-only. It is an attestation, not
-- an ordinary realization edit, so it cannot be asserted by procurement.
create function public.set_finance_validation(
  p_realization_period_id uuid,
  p_validated boolean
)
returns void
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $$
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

revoke all on function public.set_hard_reduction_override(uuid, boolean, text)
  from public, anon, authenticated;
revoke all on function public.confirm_business_equivalency(uuid, boolean)
  from public, anon, authenticated;
revoke all on function public.set_finance_validation(uuid, boolean)
  from public, anon, authenticated;
grant execute on function public.set_hard_reduction_override(uuid, boolean, text)
  to authenticated;
grant execute on function public.confirm_business_equivalency(uuid, boolean)
  to authenticated;
grant execute on function public.set_finance_validation(uuid, boolean)
  to authenticated;

-- Replace broad table grants with reviewed column manifests. Actor columns,
-- protected decision tuples, timestamps, workspace keys, and row identifiers
-- are deliberately absent from UPDATE and protected tuples are absent from
-- INSERT. Existing direct line editing remains available until 4B moves role
-- enforcement into RLS.
revoke insert, update on public.event_scope_lines from authenticated;
grant insert (
  id, organization_id, event_id, line_number, category_id,
  item_service_name, item_description, uom, location_id,
  baseline_quantity, forecast_quantity, final_quantity,
  scope_change_flag, scope_change_description
) on public.event_scope_lines to authenticated;
grant update (
  line_number, category_id, item_service_name, item_description, uom,
  location_id, baseline_quantity, forecast_quantity, final_quantity,
  scope_change_flag, scope_change_description
) on public.event_scope_lines to authenticated;

revoke insert, update on public.baseline_lines from authenticated;
grant insert (
  id, organization_id, baseline_id, event_id, scope_line_id, line_number,
  baseline_unit_price, baseline_quantity, baseline_extended_amount,
  baseline_recurring_amount, baseline_one_time_amount, baseline_term_months,
  annualized_baseline_amount, normalized_quantity, normalized_unit_price,
  normalized_extended_amount, tax_amount_included, freight_amount_included,
  source_document_id, notes
) on public.baseline_lines to authenticated;
grant update (
  scope_line_id, line_number, baseline_unit_price, baseline_quantity,
  baseline_extended_amount, baseline_recurring_amount,
  baseline_one_time_amount, baseline_term_months,
  annualized_baseline_amount, normalized_quantity, normalized_unit_price,
  normalized_extended_amount, tax_amount_included, freight_amount_included,
  source_document_id, notes
) on public.baseline_lines to authenticated;

revoke insert, update on public.supplier_offer_lines from authenticated;
grant insert (
  id, organization_id, offer_id, event_id, scope_line_id, line_number,
  offer_unit_price, offer_quantity, offer_extended_amount,
  offer_recurring_amount, offer_one_time_amount, offer_term_months,
  annualized_offer_amount, compliance_status, exclusion_notes
) on public.supplier_offer_lines to authenticated;
grant update (
  scope_line_id, line_number, offer_unit_price, offer_quantity,
  offer_extended_amount, offer_recurring_amount, offer_one_time_amount,
  offer_term_months, annualized_offer_amount, compliance_status,
  exclusion_notes
) on public.supplier_offer_lines to authenticated;

revoke insert, update on public.realization_periods from authenticated;
grant insert (
  id, organization_id, event_id, savings_calculation_id, savings_period_id,
  period_name, period_start_date, period_end_date, baseline_amount,
  actual_amount, projected_savings, realized_savings, leakage_amount,
  leakage_reason, realization_status, evidence_document_id, notes
) on public.realization_periods to authenticated;
grant update (
  period_name, period_start_date, period_end_date, baseline_amount,
  actual_amount, projected_savings, realized_savings, leakage_amount,
  leakage_reason, realization_status, evidence_document_id, notes
) on public.realization_periods to authenticated;

-- The three existing atomic writers already narrowed these tables. Remove
-- actor columns that remained in their reviewed manifests; trigger functions
-- and SECURITY DEFINER RPCs retain authority to write them.
revoke insert (created_by, updated_by), update (updated_by)
  on public.sourcing_events from authenticated;
revoke insert (created_by, updated_by), update (updated_by)
  on public.baselines from authenticated;
revoke insert (
  hard_reduction_override, hard_reduction_override_reason,
  hard_reduction_override_by, hard_reduction_override_at
), update (
  hard_reduction_override, hard_reduction_override_reason,
  hard_reduction_override_by, hard_reduction_override_at
) on public.baselines from authenticated;
revoke insert (created_by, updated_by), update (updated_by)
  on public.supplier_offers from authenticated;
revoke insert (created_by, updated_by), update (updated_by)
  on public.savings_calculations from authenticated;
revoke update (updated_by) on public.savings_periods from authenticated;

-- The existing decision writers continue to work through definer rights after
-- actor columns are removed from direct Data API access.
alter function public.select_baseline(uuid) security definer;
alter function public.set_offer_role(uuid, text) security definer;
alter function public.replace_savings_schedule(uuid, integer, integer, text, jsonb)
  security definer;

commit;
