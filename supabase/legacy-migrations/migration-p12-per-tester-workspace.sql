-- =====================================================================
-- P12: A PRIVATE WORKSPACE PER TESTER
-- =====================================================================
-- Every signup currently lands in the FIRST organization in the table:
--
--   (SELECT id FROM public.organizations LIMIT 1)
--
-- With one organization on file, that means everyone shares Joe's. For a
-- demo that is open on purpose it is not a data-theft problem -- the data
-- is seeded, not real -- but it is a feedback problem: any tester can edit
-- or delete the showcase projects every other tester is looking at, and
-- people who are afraid to click things give useless feedback.
--
-- After this migration each signup gets:
--   * its own organization,
--   * its own profile in it,
--   * its own private COPY of the demo projects to break freely.
--
-- Existing row-level security then does the rest, unchanged: every policy
-- is already scoped to organization_id, so workspaces cannot see each
-- other. Nothing about the security model is weakened here -- the hole was
-- never RLS, it was the trigger handing everyone the same membership card.
--
-- THE TEMPLATE. Cloning from Joe's own organization would mean his edits
-- leak into every future signup, and his mistakes too. So a dedicated
-- template organization is created once, seeded from whatever is on file
-- now, and frozen. Re-seed it deliberately later by cloning into it again.
--
-- SIGNUP MUST NEVER FAIL BECAUSE OF DEMO DATA. handle_new_user() runs
-- inside the auth transaction: if it raises, the signup itself fails. The
-- clone is therefore wrapped so that a failure logs a warning and leaves
-- the tester with an empty-but-working workspace, rather than an account
-- they cannot create at all.
-- =====================================================================

begin;

-- ---------------------------------------------------------------------
-- 1) Mark which organization is the template to copy from.
-- ---------------------------------------------------------------------
alter table public.organizations
  add column if not exists is_demo_template boolean not null default false;

comment on column public.organizations.is_demo_template is
  'True for the single frozen organization that new signups are seeded from. '
  'Not a tenant anyone logs into.';

-- At most one, so a signup can never pick an arbitrary template.
create unique index if not exists uq_organizations_demo_template
  on public.organizations((is_demo_template)) where is_demo_template;

-- ---------------------------------------------------------------------
-- 2) The clone.
--
-- Column lists are read from information_schema at run time rather than
-- written out here. There are twelve tables and the schema is still
-- moving; a hand-written list would silently stop copying any column
-- added later, and a demo workspace missing a column nobody noticed is
-- exactly the kind of quiet wrong this project keeps producing.
--
-- Two passes. The first allocates a new id for every row being copied, so
-- that the second can resolve references between tables in any direction
-- without caring about order.
-- ---------------------------------------------------------------------
create or replace function public.clone_org_data(
  p_source uuid,
  p_target uuid,
  p_owner  uuid
)
returns integer
language plpgsql
security definer
set search_path = public
as $fn$
declare
  -- Dependency order matters for the INSERT pass because of foreign keys.
  v_tables text[] := array[
    'categories', 'business_units', 'cost_centers', 'suppliers',
    'sourcing_events', 'event_scope_lines',
    'baselines', 'baseline_lines',
    'supplier_offers', 'supplier_offer_lines',
    'savings_calculations', 'savings_periods'
  ];
  -- Columns pointing at a person rather than at a cloned row.
  v_person_cols text[] := array['created_by', 'updated_by', 'procurement_owner_id',
                                'hard_reduction_override_by', 'finance_validated_by'];
  t         text;
  v_cols    text;
  v_total   integer := 0;
  v_count   integer;
begin
  create temp table _idmap (old uuid primary key, new uuid not null) on commit drop;

  -- Pass 1: allocate an id for every row we are about to copy.
  foreach t in array v_tables loop
    execute format(
      'insert into _idmap (old, new) select id, gen_random_uuid() from public.%I where organization_id = $1',
      t) using p_source;
  end loop;

  -- Pass 2: copy, rewriting ids as we go.
  foreach t in array v_tables loop
    select string_agg(
             case
               -- The row's own new identity.
               when c.column_name = 'id'
                 then '(select m.new from _idmap m where m.old = s.id)'
               -- Land it in the new workspace.
               when c.column_name = 'organization_id'
                 then '$2'
               -- Whoever signed up now owns everything in their copy.
               when c.column_name = any(v_person_cols)
                 then '$3'
               -- Any other uuid is a reference. If it points at something we
               -- cloned, repoint it; if it points at something we did not
               -- (a retired awards row, say), NULL it rather than leave a
               -- reference reaching into another workspace.
               when c.data_type = 'uuid'
                 then format('(select m.new from _idmap m where m.old = s.%I)', c.column_name)
               else format('s.%I', c.column_name)
             end,
             ', ' order by c.ordinal_position)
      into v_cols
      from information_schema.columns c
     where c.table_schema = 'public' and c.table_name = t;

    execute format(
      'insert into public.%I select %s from public.%I s where s.organization_id = $1',
      t, v_cols, t) using p_source, p_target, p_owner;

    get diagnostics v_count = row_count;
    v_total := v_total + v_count;
  end loop;

  drop table _idmap;
  return v_total;
end
$fn$;

revoke all on function public.clone_org_data(uuid, uuid, uuid) from public;

comment on function public.clone_org_data(uuid, uuid, uuid) is
  'Copy every business row from one organization into another, allocating '
  'fresh ids and repointing references. Used to seed a new tester workspace.';

-- ---------------------------------------------------------------------
-- 3) Build the template, once, from what is on file today.
-- ---------------------------------------------------------------------
do $seed$
declare
  v_template uuid;
  v_source   uuid;
  v_rows     integer;
begin
  if exists (select 1 from public.organizations where is_demo_template) then
    raise notice 'template already exists, leaving it alone';
    return;
  end if;

  -- Seed from the organization that actually has projects in it.
  select e.organization_id into v_source
    from public.sourcing_events e
   group by e.organization_id
   order by count(*) desc
   limit 1;

  if v_source is null then
    raise notice 'no organization has any projects; skipping template creation';
    return;
  end if;

  insert into public.organizations (name, is_demo_template)
  values ('Demo template (do not log in)', true)
  returning id into v_template;

  select public.clone_org_data(v_source, v_template, null) into v_rows;
  raise notice 'template seeded with % rows', v_rows;
end
$seed$;

-- ---------------------------------------------------------------------
-- 4) Signup: own organization, own profile, own copy of the demo.
-- ---------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_org      uuid;
  v_template uuid;
  v_name     text := coalesce(new.raw_user_meta_data->>'full_name', new.email);
begin
  insert into public.organizations (name)
  values (v_name || ' (workspace)')
  returning id into v_org;

  insert into public.profiles (id, email, full_name, organization_id)
  values (new.id, new.email, v_name, v_org);

  -- Demo data is a convenience. If seeding breaks, the person still gets an
  -- account -- raising here would abort the auth transaction and they could
  -- not sign up at all.
  begin
    select id into v_template from public.organizations where is_demo_template limit 1;
    if v_template is not null then
      perform public.clone_org_data(v_template, v_org, new.id);
    end if;
  exception when others then
    raise warning 'demo seed failed for %: %', new.email, sqlerrm;
  end;

  return new;
end
$fn$;

commit;

-- ---------------------------------------------------------------------
-- VERIFY (run separately)
-- ---------------------------------------------------------------------
-- One template, holding a full copy of the showcase data:
-- select o.name, o.is_demo_template,
--        (select count(*) from public.sourcing_events e where e.organization_id = o.id) as projects
--   from public.organizations o order by o.is_demo_template desc, o.name;
--
-- Nobody should ever be a member of the template:
-- select count(*) from public.profiles p
--   join public.organizations o on o.id = p.organization_id where o.is_demo_template;
--   -> must be 0
--
-- After a test signup, that person's workspace should mirror the template:
-- select o.name, count(e.*) as projects
--   from public.organizations o
--   left join public.sourcing_events e on e.organization_id = o.id
--  group by o.name order by o.name;
