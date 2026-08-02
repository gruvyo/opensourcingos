-- =====================================================================
-- OpenSourcingOS foundational schema baseline.
--
-- Source: the generated public-schema snapshot at commit 32e4f41,
-- captured immediately after the per-tester workspace release and before
-- the reviewed forward migrations in this directory.
--
-- This migration exists so a fresh Supabase project can replay the complete
-- history. Do not replace it with the retired one-off migration scripts.
--
-- Supabase-managed schemas (auth, storage, realtime, ...) are excluded
-- deliberately: they are not ours to change.
--
-- The auth.users signup trigger is added at the end because auth is managed
-- by Supabase and is therefore absent from a public-only schema dump.
-- =====================================================================

--
-- PostgreSQL database dump
--


-- Dumped from database version 17.6
-- Dumped by pg_dump version 18.4

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: public; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA IF NOT EXISTS public;


--
-- Name: SCHEMA public; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON SCHEMA public IS 'standard public schema';


--
-- Name: clone_org_data(uuid, uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.clone_org_data(p_source uuid, p_target uuid, p_owner uuid) RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $_$
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
$_$;


--
-- Name: FUNCTION clone_org_data(p_source uuid, p_target uuid, p_owner uuid); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.clone_org_data(p_source uuid, p_target uuid, p_owner uuid) IS 'Copy every business row from one organization into another, allocating fresh ids and repointing references. Used to seed a new tester workspace.';


--
-- Name: current_org_id(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.current_org_id() RETURNS uuid
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select organization_id from public.profiles where id = auth.uid()
$$;


--
-- Name: handle_new_user(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.handle_new_user() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
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
$$;


--
-- Name: prevent_profile_privilege_change(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.prevent_profile_privilege_change() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
begin
  if new.organization_id is distinct from old.organization_id then
    raise exception 'organization_id cannot be changed by the user';
  end if;
  return new;
end $$;


--
-- Name: update_updated_at(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;


SET default_table_access_method = heap;

--
-- Name: award_lines; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.award_lines (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id uuid,
    award_id uuid,
    event_id uuid,
    scope_line_id uuid,
    line_number integer NOT NULL,
    awarded_unit_price numeric(15,4),
    awarded_quantity numeric(15,2),
    awarded_extended_amount numeric(15,2) DEFAULT 0,
    awarded_recurring_amount numeric(15,2) DEFAULT 0,
    awarded_one_time_amount numeric(15,2) DEFAULT 0,
    awarded_term_months numeric(10,2),
    annualized_award_amount numeric(15,2) DEFAULT 0,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);

ALTER TABLE ONLY public.award_lines FORCE ROW LEVEL SECURITY;


--
-- Name: awards; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.awards (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id uuid,
    event_id uuid,
    supplier_id uuid,
    offer_id uuid,
    award_name text NOT NULL,
    award_date date,
    award_total_amount numeric(15,2) DEFAULT 0,
    award_status text DEFAULT 'Recommended'::text,
    award_approved_by uuid,
    award_approval_date timestamp with time zone,
    award_notes text,
    created_at timestamp with time zone DEFAULT now(),
    created_by uuid,
    updated_at timestamp with time zone DEFAULT now(),
    updated_by uuid,
    CONSTRAINT awards_award_status_check CHECK ((award_status = ANY (ARRAY['Recommended'::text, 'Approved'::text, 'Rejected'::text, 'On Hold'::text])))
);

ALTER TABLE ONLY public.awards FORCE ROW LEVEL SECURITY;


--
-- Name: baseline_lines; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.baseline_lines (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id uuid,
    baseline_id uuid,
    event_id uuid,
    scope_line_id uuid,
    line_number integer NOT NULL,
    baseline_unit_price numeric(15,4),
    baseline_quantity numeric(15,2),
    baseline_extended_amount numeric(15,2) DEFAULT 0,
    baseline_recurring_amount numeric(15,2) DEFAULT 0,
    baseline_one_time_amount numeric(15,2) DEFAULT 0,
    baseline_term_months numeric(10,2),
    annualized_baseline_amount numeric(15,2) DEFAULT 0,
    normalized_quantity numeric(15,2),
    normalized_unit_price numeric(15,4),
    normalized_extended_amount numeric(15,2) DEFAULT 0,
    tax_amount_included numeric(15,2) DEFAULT 0,
    freight_amount_included numeric(15,2) DEFAULT 0,
    source_document_id text,
    notes text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);

ALTER TABLE ONLY public.baseline_lines FORCE ROW LEVEL SECURITY;


--
-- Name: baselines; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.baselines (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id uuid,
    event_id uuid,
    baseline_name text NOT NULL,
    baseline_type text NOT NULL,
    baseline_source text,
    baseline_period_start date,
    baseline_period_end date,
    baseline_currency_code text DEFAULT 'USD'::text,
    baseline_fx_rate_to_usd numeric(10,4) DEFAULT 1.0000,
    baseline_total_amount numeric(15,2) DEFAULT 0,
    baseline_normalized_amount numeric(15,2) DEFAULT 0,
    normalization_notes text,
    baseline_lock_status text DEFAULT 'Draft'::text,
    baseline_lock_date timestamp with time zone,
    baseline_approved_by uuid,
    baseline_approval_date timestamp with time zone,
    official_for_hard_savings boolean DEFAULT false,
    official_for_cost_avoidance boolean DEFAULT false,
    official_for_demand_reduction boolean DEFAULT false,
    created_at timestamp with time zone DEFAULT now(),
    created_by uuid,
    updated_at timestamp with time zone DEFAULT now(),
    updated_by uuid,
    baseline_term_months numeric,
    is_selected boolean DEFAULT false NOT NULL,
    hard_reduction_override boolean DEFAULT false NOT NULL,
    hard_reduction_override_reason text,
    hard_reduction_override_by uuid,
    hard_reduction_override_at timestamp with time zone,
    CONSTRAINT baselines_baseline_lock_status_check CHECK ((baseline_lock_status = ANY (ARRAY['Draft'::text, 'Locked'::text, 'Submitted'::text, 'Approved'::text, 'Rejected'::text]))),
    CONSTRAINT chk_baseline_lock_status CHECK ((baseline_lock_status = ANY (ARRAY['Draft'::text, 'Locked'::text, 'Submitted'::text, 'Approved'::text, 'Rejected'::text]))),
    CONSTRAINT chk_hard_reduction_override_reason CHECK (((hard_reduction_override = false) OR ((hard_reduction_override_reason IS NOT NULL) AND (length(btrim(hard_reduction_override_reason)) >= 10))))
);

ALTER TABLE ONLY public.baselines FORCE ROW LEVEL SECURITY;


--
-- Name: COLUMN baselines.baseline_term_months; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.baselines.baseline_term_months IS 'Term the baseline_total_amount covers, in months. Used to derive a monthly rate (amount / months) so baselines and offers of different lengths can be compared like with like. NULL means the term was not captured.';


--
-- Name: COLUMN baselines.is_selected; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.baselines.is_selected IS 'True for the one baseline this project measures against. At most one per event.';


--
-- Name: COLUMN baselines.hard_reduction_override; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.baselines.hard_reduction_override IS 'True when a buyer has declared this baseline good enough to book a HARD cost reduction despite its type being classified as soft. Never changes the Total -- only moves money between the Reduction and Avoidance lines.';


--
-- Name: COLUMN baselines.hard_reduction_override_reason; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.baselines.hard_reduction_override_reason IS 'Why this baseline is defensible as own-spend despite its type. Required when the override is on, minimum 10 characters, enforced by CHECK.';


--
-- Name: business_units; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.business_units (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id uuid,
    business_unit_name text NOT NULL,
    parent_business_unit_id uuid,
    active_flag boolean DEFAULT true,
    created_at timestamp with time zone DEFAULT now()
);

ALTER TABLE ONLY public.business_units FORCE ROW LEVEL SECURITY;


--
-- Name: categories; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.categories (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id uuid,
    category_name text NOT NULL,
    parent_category_id uuid,
    default_baseline_type text,
    created_at timestamp with time zone DEFAULT now()
);

ALTER TABLE ONLY public.categories FORCE ROW LEVEL SECURITY;


--
-- Name: cost_centers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.cost_centers (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id uuid,
    cost_center_name text NOT NULL,
    business_unit_id uuid,
    gl_account_default text,
    active_flag boolean DEFAULT true,
    created_at timestamp with time zone DEFAULT now()
);

ALTER TABLE ONLY public.cost_centers FORCE ROW LEVEL SECURITY;


--
-- Name: event_scope_lines; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.event_scope_lines (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id uuid,
    event_id uuid,
    line_number integer NOT NULL,
    category_id uuid,
    item_service_name text NOT NULL,
    item_description text,
    uom text,
    location_id text,
    baseline_quantity numeric(15,2),
    forecast_quantity numeric(15,2),
    final_quantity numeric(15,2),
    scope_change_flag boolean DEFAULT false,
    scope_change_description text,
    business_equivalency_confirmed boolean DEFAULT false,
    business_equivalency_confirmed_by uuid,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);

ALTER TABLE ONLY public.event_scope_lines FORCE ROW LEVEL SECURITY;


--
-- Name: organizations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.organizations (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    is_demo_template boolean DEFAULT false NOT NULL
);

ALTER TABLE ONLY public.organizations FORCE ROW LEVEL SECURITY;


--
-- Name: COLUMN organizations.is_demo_template; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.organizations.is_demo_template IS 'True for the single frozen organization that new signups are seeded from. Not a tenant anyone logs into.';


--
-- Name: profiles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.profiles (
    id uuid NOT NULL,
    organization_id uuid,
    email text,
    full_name text,
    role text DEFAULT 'viewer'::text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    CONSTRAINT profiles_role_check CHECK ((role = ANY (ARRAY['admin'::text, 'procurement_user'::text, 'viewer'::text])))
);

ALTER TABLE ONLY public.profiles FORCE ROW LEVEL SECURITY;


--
-- Name: realization_periods; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.realization_periods (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id uuid,
    event_id uuid,
    savings_calculation_id uuid,
    period_name text NOT NULL,
    period_start_date date NOT NULL,
    period_end_date date NOT NULL,
    baseline_amount numeric(15,2) DEFAULT 0,
    actual_amount numeric(15,2) DEFAULT 0,
    projected_savings numeric(15,2) DEFAULT 0,
    realized_savings numeric(15,2) DEFAULT 0,
    leakage_amount numeric(15,2) DEFAULT 0,
    leakage_reason text,
    realization_status text DEFAULT 'Pending'::text,
    evidence_document_id text,
    finance_validated boolean DEFAULT false,
    finance_validated_by uuid,
    finance_validation_date timestamp with time zone,
    notes text,
    created_at timestamp with time zone DEFAULT now(),
    created_by uuid,
    updated_at timestamp with time zone DEFAULT now(),
    updated_by uuid,
    CONSTRAINT chk_realization_status CHECK ((realization_status = ANY (ARRAY['Pending'::text, 'In Progress'::text, 'Realized'::text, 'Partially Realized'::text, 'Not Realized'::text, 'Leaked'::text]))),
    CONSTRAINT realization_periods_realization_status_check CHECK ((realization_status = ANY (ARRAY['Pending'::text, 'In Progress'::text, 'Realized'::text, 'Partially Realized'::text, 'Not Realized'::text, 'Leaked'::text])))
);

ALTER TABLE ONLY public.realization_periods FORCE ROW LEVEL SECURITY;


--
-- Name: savings_calculation_lines; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.savings_calculation_lines (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id uuid,
    savings_calculation_id uuid,
    event_id uuid,
    scope_line_id uuid,
    line_number integer NOT NULL,
    baseline_unit_price numeric(15,4),
    baseline_quantity numeric(15,2),
    baseline_extended_amount numeric(15,2) DEFAULT 0,
    awarded_unit_price numeric(15,4),
    awarded_quantity numeric(15,2),
    awarded_extended_amount numeric(15,2) DEFAULT 0,
    savings_amount numeric(15,2) DEFAULT 0,
    savings_percentage numeric(9,2) DEFAULT 0,
    savings_type text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);

ALTER TABLE ONLY public.savings_calculation_lines FORCE ROW LEVEL SECURITY;


--
-- Name: savings_calculations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.savings_calculations (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id uuid,
    event_id uuid,
    baseline_id uuid,
    award_id uuid,
    calculation_name text NOT NULL,
    savings_type text NOT NULL,
    baseline_total_amount numeric(15,2) DEFAULT 0,
    award_total_amount numeric(15,2) DEFAULT 0,
    gross_savings_amount numeric(15,2) DEFAULT 0,
    savings_percentage numeric(9,2) DEFAULT 0,
    net_savings_amount numeric(15,2) DEFAULT 0,
    calculation_status text DEFAULT 'Draft'::text,
    recognition_notes text,
    created_at timestamp with time zone DEFAULT now(),
    created_by uuid,
    updated_at timestamp with time zone DEFAULT now(),
    updated_by uuid,
    savings_start_date date,
    savings_end_date date,
    cost_reduction_amount numeric DEFAULT 0,
    cost_avoidance_amount numeric DEFAULT 0,
    opening_proposal_amount numeric,
    schedule_start_month integer,
    schedule_start_year integer,
    schedule_period_type text,
    schedule_period_count integer,
    CONSTRAINT chk_calculation_status CHECK ((calculation_status = ANY (ARRAY['identified'::text, 'negotiated'::text, 'contracted'::text, 'realized'::text]))),
    CONSTRAINT chk_schedule_period_count CHECK (((schedule_period_count IS NULL) OR ((schedule_period_count >= 1) AND (schedule_period_count <= 600)))),
    CONSTRAINT chk_schedule_period_type CHECK (((schedule_period_type IS NULL) OR (schedule_period_type = ANY (ARRAY['monthly'::text, 'annual'::text, 'one_time'::text])))),
    CONSTRAINT chk_schedule_start_month CHECK (((schedule_start_month IS NULL) OR ((schedule_start_month >= 1) AND (schedule_start_month <= 12)))),
    CONSTRAINT chk_schedule_start_year CHECK (((schedule_start_year IS NULL) OR ((schedule_start_year >= 2000) AND (schedule_start_year <= 2100)))),
    CONSTRAINT savings_calculations_savings_type_check CHECK ((savings_type = ANY (ARRAY['Cost Reduction'::text, 'Cost Avoidance'::text, 'Demand Reduction'::text, 'TCO Improvement'::text, 'Working Capital'::text])))
);

ALTER TABLE ONLY public.savings_calculations FORCE ROW LEVEL SECURITY;


--
-- Name: COLUMN savings_calculations.gross_savings_amount; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.savings_calculations.gross_savings_amount IS 'THE CHAIN TOTAL (Opening - Final) - the reported headline. Equals cost_reduction_amount + cost_avoidance_amount exactly. When no opening was captured this collapses to Cost Reduction (Baseline - Final).';


--
-- Name: COLUMN savings_calculations.savings_percentage; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.savings_calculations.savings_percentage IS 'Total savings as a percentage of BASELINE spend (never of the opening ask or the awarded amount). NULL means not applicable -- no baseline anchor. Written only by reportableSavingsPct() in lib/savings.';


--
-- Name: COLUMN savings_calculations.cost_reduction_amount; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.savings_calculations.cost_reduction_amount IS 'Baseline - Final. Hard, hits the P&L. MAY BE NEGATIVE (a genuine cost increase) - show in parentheses, never sign-flip, never relabel as savings. NULL means NOT APPLICABLE (no baseline anchor), distinct from 0.';


--
-- Name: COLUMN savings_calculations.cost_avoidance_amount; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.savings_calculations.cost_avoidance_amount IS 'Opening - Baseline. Soft. With no baseline anchor the whole span books here.';


--
-- Name: COLUMN savings_calculations.opening_proposal_amount; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.savings_calculations.opening_proposal_amount IS 'The vendor''s opening proposal - the third anchor in the chain (Opening -> Baseline -> Final). NULL means no opening was captured, which is distinct from 0. Cost Avoidance = Opening - Baseline. Total procurement performance = Opening - Final = Reduction + Avoidance.';


--
-- Name: COLUMN savings_calculations.schedule_start_month; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.savings_calculations.schedule_start_month IS 'Month (1-12) the savings start being booked. With schedule_start_year this replaces date arithmetic entirely -- see savings_periods.';


--
-- Name: COLUMN savings_calculations.schedule_period_type; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.savings_calculations.schedule_period_type IS 'monthly | annual | one_time. Determines how many months one schedule row covers (1, 12, or the whole deal term). All three book the same total.';


--
-- Name: COLUMN savings_calculations.schedule_period_count; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.savings_calculations.schedule_period_count IS 'How many rows the schedule has. Defaults to whatever covers the deal term exactly; a term that is not a whole number of periods ends in a short one.';


--
-- Name: savings_periods; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.savings_periods (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id uuid NOT NULL,
    event_id uuid NOT NULL,
    savings_calculation_id uuid NOT NULL,
    period_number integer NOT NULL,
    period_month integer NOT NULL,
    period_year integer NOT NULL,
    period_months numeric DEFAULT 0 NOT NULL,
    baseline_amount numeric,
    opening_amount numeric,
    final_amount numeric DEFAULT 0 NOT NULL,
    cost_reduction_amount numeric,
    cost_avoidance_amount numeric DEFAULT 0 NOT NULL,
    total_savings_amount numeric DEFAULT 0 NOT NULL,
    is_edited boolean DEFAULT false NOT NULL,
    notes text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by uuid,
    CONSTRAINT chk_savings_periods_month CHECK (((period_month >= 1) AND (period_month <= 12))),
    CONSTRAINT chk_savings_periods_months CHECK ((period_months >= (0)::numeric)),
    CONSTRAINT chk_savings_periods_number CHECK ((period_number >= 1)),
    CONSTRAINT chk_savings_periods_year CHECK (((period_year >= 2000) AND (period_year <= 2100)))
);

ALTER TABLE ONLY public.savings_periods FORCE ROW LEVEL SECURITY;


--
-- Name: TABLE savings_periods; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.savings_periods IS 'The savings schedule: one row per period, each carrying the three anchors and the derived chain. Generated from the anchors, then editable. Grouping these rows by calendar year is what produces fiscal-year and YoY reporting.';


--
-- Name: COLUMN savings_periods.period_months; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.savings_periods.period_months IS 'Months of the deal term this row books. Zero past the end of the term.';


--
-- Name: COLUMN savings_periods.cost_reduction_amount; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.savings_periods.cost_reduction_amount IS 'Baseline - Final for this period. NULL means NOT APPLICABLE (no baseline anchor), which is distinct from zero. May legitimately be negative.';


--
-- Name: COLUMN savings_periods.is_edited; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.savings_periods.is_edited IS 'True when the amounts were overridden by hand rather than generated.';


--
-- Name: sourcing_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sourcing_events (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id uuid,
    event_name text NOT NULL,
    event_description text,
    event_type text NOT NULL,
    sourcing_method text,
    category_id uuid,
    business_unit_id uuid,
    cost_center_id uuid,
    incumbent_supplier_id uuid,
    awarded_supplier_id uuid,
    procurement_owner_id uuid,
    business_owner_id uuid,
    finance_owner_id uuid,
    event_status text DEFAULT 'Pipeline'::text,
    currency_code text DEFAULT 'USD'::text,
    fx_rate_to_usd numeric(10,4) DEFAULT 1.0000,
    event_start_date date,
    event_close_date date,
    contract_start_date date,
    contract_end_date date,
    recognition_start_date date,
    recognition_end_date date,
    official_reporting_basis text,
    created_at timestamp with time zone DEFAULT now(),
    created_by uuid,
    updated_at timestamp with time zone DEFAULT now(),
    updated_by uuid,
    project_type text DEFAULT 'Sourcing'::text,
    buyer_name text,
    notes text,
    CONSTRAINT sourcing_events_event_status_check CHECK ((event_status = ANY (ARRAY['Pipeline'::text, 'Scoped'::text, 'Baseline Pending'::text, 'Baseline Approved'::text, 'In Market'::text, 'Negotiation'::text, 'Award Recommended'::text, 'Award Approved'::text, 'Contracted'::text, 'Implemented'::text, 'Realized'::text, 'Finance Validated'::text, 'Closed'::text, 'Cancelled'::text, 'Rejected'::text, 'Not Started'::text, 'In Progress'::text, 'Hold'::text, 'Complete'::text]))),
    CONSTRAINT sourcing_events_project_type_check CHECK ((project_type = ANY (ARRAY['Sourcing'::text, 'Support'::text])))
);

ALTER TABLE ONLY public.sourcing_events FORCE ROW LEVEL SECURITY;


--
-- Name: supplier_offer_lines; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.supplier_offer_lines (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id uuid,
    offer_id uuid,
    event_id uuid,
    scope_line_id uuid,
    line_number integer NOT NULL,
    offer_unit_price numeric(15,4),
    offer_quantity numeric(15,2),
    offer_extended_amount numeric(15,2) DEFAULT 0,
    offer_recurring_amount numeric(15,2) DEFAULT 0,
    offer_one_time_amount numeric(15,2) DEFAULT 0,
    offer_term_months numeric(10,2),
    annualized_offer_amount numeric(15,2) DEFAULT 0,
    compliance_status text DEFAULT 'Compliant'::text,
    exclusion_notes text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    CONSTRAINT chk_compliance_status CHECK ((compliance_status = ANY (ARRAY['Compliant'::text, 'Non-Compliant'::text, 'Conditional'::text, 'Pending Review'::text]))),
    CONSTRAINT supplier_offer_lines_compliance_status_check CHECK ((compliance_status = ANY (ARRAY['Compliant'::text, 'Non-Compliant'::text, 'Conditional'::text, 'Pending Review'::text])))
);

ALTER TABLE ONLY public.supplier_offer_lines FORCE ROW LEVEL SECURITY;


--
-- Name: supplier_offers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.supplier_offers (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id uuid,
    event_id uuid,
    supplier_id uuid,
    offer_type text DEFAULT 'Initial'::text,
    offer_round integer DEFAULT 1,
    offer_date date,
    offer_currency_code text DEFAULT 'USD'::text,
    fx_rate_to_usd numeric(10,4) DEFAULT 1.0000,
    offer_total_amount numeric(15,2) DEFAULT 0,
    offer_valid_until date,
    compliant_bid_flag boolean DEFAULT true,
    selected_for_award_flag boolean DEFAULT false,
    source_document_id text,
    notes text,
    created_at timestamp with time zone DEFAULT now(),
    created_by uuid,
    updated_at timestamp with time zone DEFAULT now(),
    updated_by uuid,
    offer_term_months numeric,
    offer_role text,
    CONSTRAINT chk_offer_role CHECK (((offer_role IS NULL) OR (offer_role = ANY (ARRAY['opening'::text, 'final'::text])))),
    CONSTRAINT chk_offer_type CHECK ((offer_type = ANY (ARRAY['Initial'::text, 'Revised'::text, 'Best and Final (BAFO)'::text, 'Counter'::text, 'Final'::text])))
);

ALTER TABLE ONLY public.supplier_offers FORCE ROW LEVEL SECURITY;


--
-- Name: COLUMN supplier_offers.offer_term_months; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.supplier_offers.offer_term_months IS 'Term the offer_total_amount covers, in months. Used to derive a monthly rate. Any annual escalator should be priced into offer_total_amount. NULL means the term was not captured.';


--
-- Name: COLUMN supplier_offers.offer_role; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.supplier_offers.offer_role IS 'Role in the savings chain: opening (the vendor first ask, drives Cost Avoidance), final (what was signed, drives Cost Reduction), or NULL for other rounds. Marking an offer as final IS the award decision.';


--
-- Name: suppliers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.suppliers (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id uuid,
    supplier_name text NOT NULL,
    supplier_normalized_name text,
    supplier_status text DEFAULT 'Active'::text,
    preferred_flag boolean DEFAULT false,
    diversity_flag boolean DEFAULT false,
    risk_rating text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    CONSTRAINT suppliers_risk_rating_check CHECK (((risk_rating = ANY (ARRAY['Low'::text, 'Medium'::text, 'High'::text])) OR (risk_rating IS NULL))),
    CONSTRAINT suppliers_supplier_status_check CHECK ((supplier_status = ANY (ARRAY['Active'::text, 'Inactive'::text, 'Prospective'::text, 'Blocked'::text, 'Under Review'::text])))
);

ALTER TABLE ONLY public.suppliers FORCE ROW LEVEL SECURITY;


--
-- Name: award_lines award_lines_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.award_lines
    ADD CONSTRAINT award_lines_pkey PRIMARY KEY (id);


--
-- Name: awards awards_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.awards
    ADD CONSTRAINT awards_pkey PRIMARY KEY (id);


--
-- Name: baseline_lines baseline_lines_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.baseline_lines
    ADD CONSTRAINT baseline_lines_pkey PRIMARY KEY (id);


--
-- Name: baselines baselines_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.baselines
    ADD CONSTRAINT baselines_pkey PRIMARY KEY (id);


--
-- Name: business_units business_units_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.business_units
    ADD CONSTRAINT business_units_pkey PRIMARY KEY (id);


--
-- Name: categories categories_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.categories
    ADD CONSTRAINT categories_pkey PRIMARY KEY (id);


--
-- Name: cost_centers cost_centers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cost_centers
    ADD CONSTRAINT cost_centers_pkey PRIMARY KEY (id);


--
-- Name: event_scope_lines event_scope_lines_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.event_scope_lines
    ADD CONSTRAINT event_scope_lines_pkey PRIMARY KEY (id);


--
-- Name: organizations organizations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organizations
    ADD CONSTRAINT organizations_pkey PRIMARY KEY (id);


--
-- Name: profiles profiles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.profiles
    ADD CONSTRAINT profiles_pkey PRIMARY KEY (id);


--
-- Name: realization_periods realization_periods_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.realization_periods
    ADD CONSTRAINT realization_periods_pkey PRIMARY KEY (id);


--
-- Name: savings_calculation_lines savings_calculation_lines_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.savings_calculation_lines
    ADD CONSTRAINT savings_calculation_lines_pkey PRIMARY KEY (id);


--
-- Name: savings_calculations savings_calculations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.savings_calculations
    ADD CONSTRAINT savings_calculations_pkey PRIMARY KEY (id);


--
-- Name: savings_periods savings_periods_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.savings_periods
    ADD CONSTRAINT savings_periods_pkey PRIMARY KEY (id);


--
-- Name: sourcing_events sourcing_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sourcing_events
    ADD CONSTRAINT sourcing_events_pkey PRIMARY KEY (id);


--
-- Name: supplier_offer_lines supplier_offer_lines_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.supplier_offer_lines
    ADD CONSTRAINT supplier_offer_lines_pkey PRIMARY KEY (id);


--
-- Name: supplier_offers supplier_offers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.supplier_offers
    ADD CONSTRAINT supplier_offers_pkey PRIMARY KEY (id);


--
-- Name: suppliers suppliers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.suppliers
    ADD CONSTRAINT suppliers_pkey PRIMARY KEY (id);


--
-- Name: idx_award_lines_award; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_award_lines_award ON public.award_lines USING btree (award_id);


--
-- Name: idx_award_lines_event; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_award_lines_event ON public.award_lines USING btree (event_id);


--
-- Name: idx_award_lines_org; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_award_lines_org ON public.award_lines USING btree (organization_id);


--
-- Name: idx_awards_event; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_awards_event ON public.awards USING btree (event_id);


--
-- Name: idx_awards_offer; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_awards_offer ON public.awards USING btree (offer_id);


--
-- Name: idx_awards_org; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_awards_org ON public.awards USING btree (organization_id);


--
-- Name: idx_baseline_lines_baseline; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_baseline_lines_baseline ON public.baseline_lines USING btree (baseline_id);


--
-- Name: idx_baseline_lines_event; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_baseline_lines_event ON public.baseline_lines USING btree (event_id);


--
-- Name: idx_baseline_lines_org; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_baseline_lines_org ON public.baseline_lines USING btree (organization_id);


--
-- Name: idx_baselines_event; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_baselines_event ON public.baselines USING btree (event_id);


--
-- Name: idx_baselines_org; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_baselines_org ON public.baselines USING btree (organization_id);


--
-- Name: idx_business_units_org; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_business_units_org ON public.business_units USING btree (organization_id);


--
-- Name: idx_categories_org; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_categories_org ON public.categories USING btree (organization_id);


--
-- Name: idx_cost_centers_org; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_cost_centers_org ON public.cost_centers USING btree (organization_id);


--
-- Name: idx_event_scope_lines_event; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_event_scope_lines_event ON public.event_scope_lines USING btree (event_id);


--
-- Name: idx_event_scope_lines_org; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_event_scope_lines_org ON public.event_scope_lines USING btree (organization_id);


--
-- Name: idx_realization_periods_calc; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_realization_periods_calc ON public.realization_periods USING btree (savings_calculation_id);


--
-- Name: idx_realization_periods_event; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_realization_periods_event ON public.realization_periods USING btree (event_id);


--
-- Name: idx_realization_periods_org; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_realization_periods_org ON public.realization_periods USING btree (organization_id);


--
-- Name: idx_savings_calculation_lines_calc; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_savings_calculation_lines_calc ON public.savings_calculation_lines USING btree (savings_calculation_id);


--
-- Name: idx_savings_calculations_award; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_savings_calculations_award ON public.savings_calculations USING btree (award_id);


--
-- Name: idx_savings_calculations_baseline; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_savings_calculations_baseline ON public.savings_calculations USING btree (baseline_id);


--
-- Name: idx_savings_calculations_event; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_savings_calculations_event ON public.savings_calculations USING btree (event_id);


--
-- Name: idx_savings_calculations_org; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_savings_calculations_org ON public.savings_calculations USING btree (organization_id);


--
-- Name: idx_savings_periods_calc; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_savings_periods_calc ON public.savings_periods USING btree (savings_calculation_id);


--
-- Name: idx_savings_periods_event; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_savings_periods_event ON public.savings_periods USING btree (event_id);


--
-- Name: idx_savings_periods_org; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_savings_periods_org ON public.savings_periods USING btree (organization_id);


--
-- Name: idx_savings_periods_year; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_savings_periods_year ON public.savings_periods USING btree (organization_id, period_year);


--
-- Name: idx_sourcing_events_awarded; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_sourcing_events_awarded ON public.sourcing_events USING btree (awarded_supplier_id);


--
-- Name: idx_sourcing_events_bu; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_sourcing_events_bu ON public.sourcing_events USING btree (business_unit_id);


--
-- Name: idx_sourcing_events_category; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_sourcing_events_category ON public.sourcing_events USING btree (category_id);


--
-- Name: idx_sourcing_events_incumbent; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_sourcing_events_incumbent ON public.sourcing_events USING btree (incumbent_supplier_id);


--
-- Name: idx_sourcing_events_org; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_sourcing_events_org ON public.sourcing_events USING btree (organization_id);


--
-- Name: idx_supplier_offer_lines_event; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_supplier_offer_lines_event ON public.supplier_offer_lines USING btree (event_id);


--
-- Name: idx_supplier_offer_lines_offer; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_supplier_offer_lines_offer ON public.supplier_offer_lines USING btree (offer_id);


--
-- Name: idx_supplier_offer_lines_org; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_supplier_offer_lines_org ON public.supplier_offer_lines USING btree (organization_id);


--
-- Name: idx_supplier_offers_event; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_supplier_offers_event ON public.supplier_offers USING btree (event_id);


--
-- Name: idx_supplier_offers_org; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_supplier_offers_org ON public.supplier_offers USING btree (organization_id);


--
-- Name: idx_suppliers_org; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_suppliers_org ON public.suppliers USING btree (organization_id);


--
-- Name: uq_baselines_official_cost_avoidance; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_baselines_official_cost_avoidance ON public.baselines USING btree (event_id) WHERE official_for_cost_avoidance;


--
-- Name: uq_baselines_official_demand_reduction; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_baselines_official_demand_reduction ON public.baselines USING btree (event_id) WHERE official_for_demand_reduction;


--
-- Name: uq_baselines_official_hard_savings; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_baselines_official_hard_savings ON public.baselines USING btree (event_id) WHERE official_for_hard_savings;


--
-- Name: uq_baselines_selected; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_baselines_selected ON public.baselines USING btree (event_id) WHERE is_selected;


--
-- Name: uq_offers_final; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_offers_final ON public.supplier_offers USING btree (event_id) WHERE (offer_role = 'final'::text);


--
-- Name: uq_offers_opening; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_offers_opening ON public.supplier_offers USING btree (event_id) WHERE (offer_role = 'opening'::text);


--
-- Name: uq_organizations_demo_template; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_organizations_demo_template ON public.organizations USING btree (is_demo_template) WHERE is_demo_template;


--
-- Name: uq_savings_periods_calc_number; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_savings_periods_calc_number ON public.savings_periods USING btree (savings_calculation_id, period_number);


--
-- Name: uq_supplier_offers_selected_award; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_supplier_offers_selected_award ON public.supplier_offers USING btree (event_id) WHERE selected_for_award_flag;


--
-- Name: award_lines award_lines_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER award_lines_updated_at BEFORE UPDATE ON public.award_lines FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();


--
-- Name: awards awards_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER awards_updated_at BEFORE UPDATE ON public.awards FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();


--
-- Name: baseline_lines baseline_lines_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER baseline_lines_updated_at BEFORE UPDATE ON public.baseline_lines FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();


--
-- Name: baselines baselines_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER baselines_updated_at BEFORE UPDATE ON public.baselines FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();


--
-- Name: realization_periods realization_periods_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER realization_periods_updated_at BEFORE UPDATE ON public.realization_periods FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();


--
-- Name: savings_calculation_lines savings_calculation_lines_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER savings_calculation_lines_updated_at BEFORE UPDATE ON public.savings_calculation_lines FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();


--
-- Name: savings_calculations savings_calculations_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER savings_calculations_updated_at BEFORE UPDATE ON public.savings_calculations FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();


--
-- Name: supplier_offer_lines supplier_offer_lines_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER supplier_offer_lines_updated_at BEFORE UPDATE ON public.supplier_offer_lines FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();


--
-- Name: supplier_offers supplier_offers_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER supplier_offers_updated_at BEFORE UPDATE ON public.supplier_offers FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();


--
-- Name: profiles trg_prevent_profile_privilege_change; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_prevent_profile_privilege_change BEFORE UPDATE ON public.profiles FOR EACH ROW EXECUTE FUNCTION public.prevent_profile_privilege_change();


--
-- Name: award_lines award_lines_award_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.award_lines
    ADD CONSTRAINT award_lines_award_id_fkey FOREIGN KEY (award_id) REFERENCES public.awards(id) ON DELETE CASCADE;


--
-- Name: award_lines award_lines_event_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.award_lines
    ADD CONSTRAINT award_lines_event_id_fkey FOREIGN KEY (event_id) REFERENCES public.sourcing_events(id) ON DELETE CASCADE;


--
-- Name: award_lines award_lines_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.award_lines
    ADD CONSTRAINT award_lines_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: award_lines award_lines_scope_line_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.award_lines
    ADD CONSTRAINT award_lines_scope_line_id_fkey FOREIGN KEY (scope_line_id) REFERENCES public.event_scope_lines(id) ON DELETE SET NULL;


--
-- Name: awards awards_award_approved_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.awards
    ADD CONSTRAINT awards_award_approved_by_fkey FOREIGN KEY (award_approved_by) REFERENCES public.profiles(id);


--
-- Name: awards awards_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.awards
    ADD CONSTRAINT awards_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.profiles(id);


--
-- Name: awards awards_event_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.awards
    ADD CONSTRAINT awards_event_id_fkey FOREIGN KEY (event_id) REFERENCES public.sourcing_events(id) ON DELETE CASCADE;


--
-- Name: awards awards_offer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.awards
    ADD CONSTRAINT awards_offer_id_fkey FOREIGN KEY (offer_id) REFERENCES public.supplier_offers(id) ON DELETE SET NULL;


--
-- Name: awards awards_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.awards
    ADD CONSTRAINT awards_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: awards awards_supplier_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.awards
    ADD CONSTRAINT awards_supplier_id_fkey FOREIGN KEY (supplier_id) REFERENCES public.suppliers(id);


--
-- Name: awards awards_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.awards
    ADD CONSTRAINT awards_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.profiles(id);


--
-- Name: baseline_lines baseline_lines_baseline_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.baseline_lines
    ADD CONSTRAINT baseline_lines_baseline_id_fkey FOREIGN KEY (baseline_id) REFERENCES public.baselines(id) ON DELETE CASCADE;


--
-- Name: baseline_lines baseline_lines_event_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.baseline_lines
    ADD CONSTRAINT baseline_lines_event_id_fkey FOREIGN KEY (event_id) REFERENCES public.sourcing_events(id) ON DELETE CASCADE;


--
-- Name: baseline_lines baseline_lines_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.baseline_lines
    ADD CONSTRAINT baseline_lines_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: baseline_lines baseline_lines_scope_line_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.baseline_lines
    ADD CONSTRAINT baseline_lines_scope_line_id_fkey FOREIGN KEY (scope_line_id) REFERENCES public.event_scope_lines(id) ON DELETE SET NULL;


--
-- Name: baselines baselines_baseline_approved_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.baselines
    ADD CONSTRAINT baselines_baseline_approved_by_fkey FOREIGN KEY (baseline_approved_by) REFERENCES public.profiles(id);


--
-- Name: baselines baselines_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.baselines
    ADD CONSTRAINT baselines_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.profiles(id);


--
-- Name: baselines baselines_event_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.baselines
    ADD CONSTRAINT baselines_event_id_fkey FOREIGN KEY (event_id) REFERENCES public.sourcing_events(id) ON DELETE CASCADE;


--
-- Name: baselines baselines_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.baselines
    ADD CONSTRAINT baselines_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: baselines baselines_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.baselines
    ADD CONSTRAINT baselines_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.profiles(id);


--
-- Name: business_units business_units_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.business_units
    ADD CONSTRAINT business_units_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: business_units business_units_parent_business_unit_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.business_units
    ADD CONSTRAINT business_units_parent_business_unit_id_fkey FOREIGN KEY (parent_business_unit_id) REFERENCES public.business_units(id);


--
-- Name: categories categories_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.categories
    ADD CONSTRAINT categories_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: categories categories_parent_category_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.categories
    ADD CONSTRAINT categories_parent_category_id_fkey FOREIGN KEY (parent_category_id) REFERENCES public.categories(id);


--
-- Name: cost_centers cost_centers_business_unit_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cost_centers
    ADD CONSTRAINT cost_centers_business_unit_id_fkey FOREIGN KEY (business_unit_id) REFERENCES public.business_units(id);


--
-- Name: cost_centers cost_centers_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cost_centers
    ADD CONSTRAINT cost_centers_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: event_scope_lines event_scope_lines_business_equivalency_confirmed_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.event_scope_lines
    ADD CONSTRAINT event_scope_lines_business_equivalency_confirmed_by_fkey FOREIGN KEY (business_equivalency_confirmed_by) REFERENCES public.profiles(id);


--
-- Name: event_scope_lines event_scope_lines_category_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.event_scope_lines
    ADD CONSTRAINT event_scope_lines_category_id_fkey FOREIGN KEY (category_id) REFERENCES public.categories(id);


--
-- Name: event_scope_lines event_scope_lines_event_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.event_scope_lines
    ADD CONSTRAINT event_scope_lines_event_id_fkey FOREIGN KEY (event_id) REFERENCES public.sourcing_events(id) ON DELETE CASCADE;


--
-- Name: event_scope_lines event_scope_lines_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.event_scope_lines
    ADD CONSTRAINT event_scope_lines_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: profiles profiles_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.profiles
    ADD CONSTRAINT profiles_id_fkey FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: profiles profiles_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.profiles
    ADD CONSTRAINT profiles_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: realization_periods realization_periods_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.realization_periods
    ADD CONSTRAINT realization_periods_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.profiles(id);


--
-- Name: realization_periods realization_periods_event_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.realization_periods
    ADD CONSTRAINT realization_periods_event_id_fkey FOREIGN KEY (event_id) REFERENCES public.sourcing_events(id) ON DELETE CASCADE;


--
-- Name: realization_periods realization_periods_finance_validated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.realization_periods
    ADD CONSTRAINT realization_periods_finance_validated_by_fkey FOREIGN KEY (finance_validated_by) REFERENCES public.profiles(id);


--
-- Name: realization_periods realization_periods_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.realization_periods
    ADD CONSTRAINT realization_periods_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: realization_periods realization_periods_savings_calculation_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.realization_periods
    ADD CONSTRAINT realization_periods_savings_calculation_id_fkey FOREIGN KEY (savings_calculation_id) REFERENCES public.savings_calculations(id) ON DELETE SET NULL;


--
-- Name: realization_periods realization_periods_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.realization_periods
    ADD CONSTRAINT realization_periods_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.profiles(id);


--
-- Name: savings_calculation_lines savings_calculation_lines_event_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.savings_calculation_lines
    ADD CONSTRAINT savings_calculation_lines_event_id_fkey FOREIGN KEY (event_id) REFERENCES public.sourcing_events(id) ON DELETE CASCADE;


--
-- Name: savings_calculation_lines savings_calculation_lines_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.savings_calculation_lines
    ADD CONSTRAINT savings_calculation_lines_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: savings_calculation_lines savings_calculation_lines_savings_calculation_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.savings_calculation_lines
    ADD CONSTRAINT savings_calculation_lines_savings_calculation_id_fkey FOREIGN KEY (savings_calculation_id) REFERENCES public.savings_calculations(id) ON DELETE CASCADE;


--
-- Name: savings_calculation_lines savings_calculation_lines_scope_line_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.savings_calculation_lines
    ADD CONSTRAINT savings_calculation_lines_scope_line_id_fkey FOREIGN KEY (scope_line_id) REFERENCES public.event_scope_lines(id) ON DELETE SET NULL;


--
-- Name: savings_calculations savings_calculations_award_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.savings_calculations
    ADD CONSTRAINT savings_calculations_award_id_fkey FOREIGN KEY (award_id) REFERENCES public.awards(id) ON DELETE SET NULL;


--
-- Name: savings_calculations savings_calculations_baseline_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.savings_calculations
    ADD CONSTRAINT savings_calculations_baseline_id_fkey FOREIGN KEY (baseline_id) REFERENCES public.baselines(id) ON DELETE SET NULL;


--
-- Name: savings_calculations savings_calculations_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.savings_calculations
    ADD CONSTRAINT savings_calculations_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.profiles(id);


--
-- Name: savings_calculations savings_calculations_event_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.savings_calculations
    ADD CONSTRAINT savings_calculations_event_id_fkey FOREIGN KEY (event_id) REFERENCES public.sourcing_events(id) ON DELETE CASCADE;


--
-- Name: savings_calculations savings_calculations_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.savings_calculations
    ADD CONSTRAINT savings_calculations_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: savings_calculations savings_calculations_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.savings_calculations
    ADD CONSTRAINT savings_calculations_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.profiles(id);


--
-- Name: savings_periods savings_periods_event_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.savings_periods
    ADD CONSTRAINT savings_periods_event_id_fkey FOREIGN KEY (event_id) REFERENCES public.sourcing_events(id) ON DELETE CASCADE;


--
-- Name: savings_periods savings_periods_savings_calculation_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.savings_periods
    ADD CONSTRAINT savings_periods_savings_calculation_id_fkey FOREIGN KEY (savings_calculation_id) REFERENCES public.savings_calculations(id) ON DELETE CASCADE;


--
-- Name: sourcing_events sourcing_events_awarded_supplier_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sourcing_events
    ADD CONSTRAINT sourcing_events_awarded_supplier_id_fkey FOREIGN KEY (awarded_supplier_id) REFERENCES public.suppliers(id);


--
-- Name: sourcing_events sourcing_events_business_owner_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sourcing_events
    ADD CONSTRAINT sourcing_events_business_owner_id_fkey FOREIGN KEY (business_owner_id) REFERENCES public.profiles(id);


--
-- Name: sourcing_events sourcing_events_business_unit_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sourcing_events
    ADD CONSTRAINT sourcing_events_business_unit_id_fkey FOREIGN KEY (business_unit_id) REFERENCES public.business_units(id);


--
-- Name: sourcing_events sourcing_events_category_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sourcing_events
    ADD CONSTRAINT sourcing_events_category_id_fkey FOREIGN KEY (category_id) REFERENCES public.categories(id);


--
-- Name: sourcing_events sourcing_events_cost_center_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sourcing_events
    ADD CONSTRAINT sourcing_events_cost_center_id_fkey FOREIGN KEY (cost_center_id) REFERENCES public.cost_centers(id);


--
-- Name: sourcing_events sourcing_events_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sourcing_events
    ADD CONSTRAINT sourcing_events_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.profiles(id);


--
-- Name: sourcing_events sourcing_events_finance_owner_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sourcing_events
    ADD CONSTRAINT sourcing_events_finance_owner_id_fkey FOREIGN KEY (finance_owner_id) REFERENCES public.profiles(id);


--
-- Name: sourcing_events sourcing_events_incumbent_supplier_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sourcing_events
    ADD CONSTRAINT sourcing_events_incumbent_supplier_id_fkey FOREIGN KEY (incumbent_supplier_id) REFERENCES public.suppliers(id);


--
-- Name: sourcing_events sourcing_events_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sourcing_events
    ADD CONSTRAINT sourcing_events_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: sourcing_events sourcing_events_procurement_owner_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sourcing_events
    ADD CONSTRAINT sourcing_events_procurement_owner_id_fkey FOREIGN KEY (procurement_owner_id) REFERENCES public.profiles(id);


--
-- Name: sourcing_events sourcing_events_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sourcing_events
    ADD CONSTRAINT sourcing_events_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.profiles(id);


--
-- Name: supplier_offer_lines supplier_offer_lines_event_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.supplier_offer_lines
    ADD CONSTRAINT supplier_offer_lines_event_id_fkey FOREIGN KEY (event_id) REFERENCES public.sourcing_events(id) ON DELETE CASCADE;


--
-- Name: supplier_offer_lines supplier_offer_lines_offer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.supplier_offer_lines
    ADD CONSTRAINT supplier_offer_lines_offer_id_fkey FOREIGN KEY (offer_id) REFERENCES public.supplier_offers(id) ON DELETE CASCADE;


--
-- Name: supplier_offer_lines supplier_offer_lines_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.supplier_offer_lines
    ADD CONSTRAINT supplier_offer_lines_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: supplier_offer_lines supplier_offer_lines_scope_line_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.supplier_offer_lines
    ADD CONSTRAINT supplier_offer_lines_scope_line_id_fkey FOREIGN KEY (scope_line_id) REFERENCES public.event_scope_lines(id) ON DELETE SET NULL;


--
-- Name: supplier_offers supplier_offers_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.supplier_offers
    ADD CONSTRAINT supplier_offers_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.profiles(id);


--
-- Name: supplier_offers supplier_offers_event_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.supplier_offers
    ADD CONSTRAINT supplier_offers_event_id_fkey FOREIGN KEY (event_id) REFERENCES public.sourcing_events(id) ON DELETE CASCADE;


--
-- Name: supplier_offers supplier_offers_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.supplier_offers
    ADD CONSTRAINT supplier_offers_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: supplier_offers supplier_offers_supplier_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.supplier_offers
    ADD CONSTRAINT supplier_offers_supplier_id_fkey FOREIGN KEY (supplier_id) REFERENCES public.suppliers(id);


--
-- Name: supplier_offers supplier_offers_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.supplier_offers
    ADD CONSTRAINT supplier_offers_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.profiles(id);


--
-- Name: suppliers suppliers_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.suppliers
    ADD CONSTRAINT suppliers_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: award_lines; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.award_lines ENABLE ROW LEVEL SECURITY;

--
-- Name: awards; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.awards ENABLE ROW LEVEL SECURITY;

--
-- Name: baseline_lines; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.baseline_lines ENABLE ROW LEVEL SECURITY;

--
-- Name: baselines; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.baselines ENABLE ROW LEVEL SECURITY;

--
-- Name: business_units; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.business_units ENABLE ROW LEVEL SECURITY;

--
-- Name: categories; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.categories ENABLE ROW LEVEL SECURITY;

--
-- Name: cost_centers; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.cost_centers ENABLE ROW LEVEL SECURITY;

--
-- Name: event_scope_lines; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.event_scope_lines ENABLE ROW LEVEL SECURITY;

--
-- Name: award_lines org_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY org_delete ON public.award_lines FOR DELETE TO authenticated USING ((organization_id = public.current_org_id()));


--
-- Name: awards org_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY org_delete ON public.awards FOR DELETE TO authenticated USING ((organization_id = public.current_org_id()));


--
-- Name: baseline_lines org_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY org_delete ON public.baseline_lines FOR DELETE TO authenticated USING ((organization_id = public.current_org_id()));


--
-- Name: baselines org_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY org_delete ON public.baselines FOR DELETE TO authenticated USING ((organization_id = public.current_org_id()));


--
-- Name: business_units org_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY org_delete ON public.business_units FOR DELETE TO authenticated USING ((organization_id = public.current_org_id()));


--
-- Name: categories org_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY org_delete ON public.categories FOR DELETE TO authenticated USING ((organization_id = public.current_org_id()));


--
-- Name: cost_centers org_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY org_delete ON public.cost_centers FOR DELETE TO authenticated USING ((organization_id = public.current_org_id()));


--
-- Name: event_scope_lines org_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY org_delete ON public.event_scope_lines FOR DELETE TO authenticated USING ((organization_id = public.current_org_id()));


--
-- Name: realization_periods org_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY org_delete ON public.realization_periods FOR DELETE TO authenticated USING ((organization_id = public.current_org_id()));


--
-- Name: savings_calculation_lines org_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY org_delete ON public.savings_calculation_lines FOR DELETE TO authenticated USING ((organization_id = public.current_org_id()));


--
-- Name: savings_calculations org_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY org_delete ON public.savings_calculations FOR DELETE TO authenticated USING ((organization_id = public.current_org_id()));


--
-- Name: savings_periods org_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY org_delete ON public.savings_periods FOR DELETE TO authenticated USING ((organization_id = public.current_org_id()));


--
-- Name: sourcing_events org_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY org_delete ON public.sourcing_events FOR DELETE TO authenticated USING ((organization_id = public.current_org_id()));


--
-- Name: supplier_offer_lines org_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY org_delete ON public.supplier_offer_lines FOR DELETE TO authenticated USING ((organization_id = public.current_org_id()));


--
-- Name: supplier_offers org_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY org_delete ON public.supplier_offers FOR DELETE TO authenticated USING ((organization_id = public.current_org_id()));


--
-- Name: suppliers org_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY org_delete ON public.suppliers FOR DELETE TO authenticated USING ((organization_id = public.current_org_id()));


--
-- Name: award_lines org_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY org_insert ON public.award_lines FOR INSERT TO authenticated WITH CHECK ((organization_id = public.current_org_id()));


--
-- Name: awards org_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY org_insert ON public.awards FOR INSERT TO authenticated WITH CHECK ((organization_id = public.current_org_id()));


--
-- Name: baseline_lines org_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY org_insert ON public.baseline_lines FOR INSERT TO authenticated WITH CHECK ((organization_id = public.current_org_id()));


--
-- Name: baselines org_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY org_insert ON public.baselines FOR INSERT TO authenticated WITH CHECK ((organization_id = public.current_org_id()));


--
-- Name: business_units org_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY org_insert ON public.business_units FOR INSERT TO authenticated WITH CHECK ((organization_id = public.current_org_id()));


--
-- Name: categories org_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY org_insert ON public.categories FOR INSERT TO authenticated WITH CHECK ((organization_id = public.current_org_id()));


--
-- Name: cost_centers org_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY org_insert ON public.cost_centers FOR INSERT TO authenticated WITH CHECK ((organization_id = public.current_org_id()));


--
-- Name: event_scope_lines org_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY org_insert ON public.event_scope_lines FOR INSERT TO authenticated WITH CHECK ((organization_id = public.current_org_id()));


--
-- Name: realization_periods org_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY org_insert ON public.realization_periods FOR INSERT TO authenticated WITH CHECK ((organization_id = public.current_org_id()));


--
-- Name: savings_calculation_lines org_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY org_insert ON public.savings_calculation_lines FOR INSERT TO authenticated WITH CHECK ((organization_id = public.current_org_id()));


--
-- Name: savings_calculations org_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY org_insert ON public.savings_calculations FOR INSERT TO authenticated WITH CHECK ((organization_id = public.current_org_id()));


--
-- Name: savings_periods org_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY org_insert ON public.savings_periods FOR INSERT TO authenticated WITH CHECK ((organization_id = public.current_org_id()));


--
-- Name: sourcing_events org_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY org_insert ON public.sourcing_events FOR INSERT TO authenticated WITH CHECK ((organization_id = public.current_org_id()));


--
-- Name: supplier_offer_lines org_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY org_insert ON public.supplier_offer_lines FOR INSERT TO authenticated WITH CHECK ((organization_id = public.current_org_id()));


--
-- Name: supplier_offers org_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY org_insert ON public.supplier_offers FOR INSERT TO authenticated WITH CHECK ((organization_id = public.current_org_id()));


--
-- Name: suppliers org_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY org_insert ON public.suppliers FOR INSERT TO authenticated WITH CHECK ((organization_id = public.current_org_id()));


--
-- Name: award_lines org_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY org_select ON public.award_lines FOR SELECT TO authenticated USING ((organization_id = public.current_org_id()));


--
-- Name: awards org_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY org_select ON public.awards FOR SELECT TO authenticated USING ((organization_id = public.current_org_id()));


--
-- Name: baseline_lines org_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY org_select ON public.baseline_lines FOR SELECT TO authenticated USING ((organization_id = public.current_org_id()));


--
-- Name: baselines org_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY org_select ON public.baselines FOR SELECT TO authenticated USING ((organization_id = public.current_org_id()));


--
-- Name: business_units org_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY org_select ON public.business_units FOR SELECT TO authenticated USING ((organization_id = public.current_org_id()));


--
-- Name: categories org_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY org_select ON public.categories FOR SELECT TO authenticated USING ((organization_id = public.current_org_id()));


--
-- Name: cost_centers org_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY org_select ON public.cost_centers FOR SELECT TO authenticated USING ((organization_id = public.current_org_id()));


--
-- Name: event_scope_lines org_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY org_select ON public.event_scope_lines FOR SELECT TO authenticated USING ((organization_id = public.current_org_id()));


--
-- Name: realization_periods org_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY org_select ON public.realization_periods FOR SELECT TO authenticated USING ((organization_id = public.current_org_id()));


--
-- Name: savings_calculation_lines org_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY org_select ON public.savings_calculation_lines FOR SELECT TO authenticated USING ((organization_id = public.current_org_id()));


--
-- Name: savings_calculations org_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY org_select ON public.savings_calculations FOR SELECT TO authenticated USING ((organization_id = public.current_org_id()));


--
-- Name: savings_periods org_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY org_select ON public.savings_periods FOR SELECT TO authenticated USING ((organization_id = public.current_org_id()));


--
-- Name: sourcing_events org_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY org_select ON public.sourcing_events FOR SELECT TO authenticated USING ((organization_id = public.current_org_id()));


--
-- Name: supplier_offer_lines org_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY org_select ON public.supplier_offer_lines FOR SELECT TO authenticated USING ((organization_id = public.current_org_id()));


--
-- Name: supplier_offers org_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY org_select ON public.supplier_offers FOR SELECT TO authenticated USING ((organization_id = public.current_org_id()));


--
-- Name: suppliers org_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY org_select ON public.suppliers FOR SELECT TO authenticated USING ((organization_id = public.current_org_id()));


--
-- Name: award_lines org_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY org_update ON public.award_lines FOR UPDATE TO authenticated USING ((organization_id = public.current_org_id())) WITH CHECK ((organization_id = public.current_org_id()));


--
-- Name: awards org_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY org_update ON public.awards FOR UPDATE TO authenticated USING ((organization_id = public.current_org_id())) WITH CHECK ((organization_id = public.current_org_id()));


--
-- Name: baseline_lines org_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY org_update ON public.baseline_lines FOR UPDATE TO authenticated USING ((organization_id = public.current_org_id())) WITH CHECK ((organization_id = public.current_org_id()));


--
-- Name: baselines org_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY org_update ON public.baselines FOR UPDATE TO authenticated USING ((organization_id = public.current_org_id())) WITH CHECK ((organization_id = public.current_org_id()));


--
-- Name: business_units org_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY org_update ON public.business_units FOR UPDATE TO authenticated USING ((organization_id = public.current_org_id())) WITH CHECK ((organization_id = public.current_org_id()));


--
-- Name: categories org_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY org_update ON public.categories FOR UPDATE TO authenticated USING ((organization_id = public.current_org_id())) WITH CHECK ((organization_id = public.current_org_id()));


--
-- Name: cost_centers org_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY org_update ON public.cost_centers FOR UPDATE TO authenticated USING ((organization_id = public.current_org_id())) WITH CHECK ((organization_id = public.current_org_id()));


--
-- Name: event_scope_lines org_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY org_update ON public.event_scope_lines FOR UPDATE TO authenticated USING ((organization_id = public.current_org_id())) WITH CHECK ((organization_id = public.current_org_id()));


--
-- Name: realization_periods org_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY org_update ON public.realization_periods FOR UPDATE TO authenticated USING ((organization_id = public.current_org_id())) WITH CHECK ((organization_id = public.current_org_id()));


--
-- Name: savings_calculation_lines org_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY org_update ON public.savings_calculation_lines FOR UPDATE TO authenticated USING ((organization_id = public.current_org_id())) WITH CHECK ((organization_id = public.current_org_id()));


--
-- Name: savings_calculations org_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY org_update ON public.savings_calculations FOR UPDATE TO authenticated USING ((organization_id = public.current_org_id())) WITH CHECK ((organization_id = public.current_org_id()));


--
-- Name: savings_periods org_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY org_update ON public.savings_periods FOR UPDATE TO authenticated USING ((organization_id = public.current_org_id())) WITH CHECK ((organization_id = public.current_org_id()));


--
-- Name: sourcing_events org_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY org_update ON public.sourcing_events FOR UPDATE TO authenticated USING ((organization_id = public.current_org_id())) WITH CHECK ((organization_id = public.current_org_id()));


--
-- Name: supplier_offer_lines org_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY org_update ON public.supplier_offer_lines FOR UPDATE TO authenticated USING ((organization_id = public.current_org_id())) WITH CHECK ((organization_id = public.current_org_id()));


--
-- Name: supplier_offers org_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY org_update ON public.supplier_offers FOR UPDATE TO authenticated USING ((organization_id = public.current_org_id())) WITH CHECK ((organization_id = public.current_org_id()));


--
-- Name: suppliers org_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY org_update ON public.suppliers FOR UPDATE TO authenticated USING ((organization_id = public.current_org_id())) WITH CHECK ((organization_id = public.current_org_id()));


--
-- Name: organizations; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.organizations ENABLE ROW LEVEL SECURITY;

--
-- Name: organizations own_org_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY own_org_select ON public.organizations FOR SELECT TO authenticated USING ((id = public.current_org_id()));


--
-- Name: profiles; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

--
-- Name: profiles profiles_select_org; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY profiles_select_org ON public.profiles FOR SELECT TO authenticated USING ((organization_id = public.current_org_id()));


--
-- Name: profiles profiles_update_self; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY profiles_update_self ON public.profiles FOR UPDATE TO authenticated USING ((id = auth.uid())) WITH CHECK ((id = auth.uid()));


--
-- Name: realization_periods; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.realization_periods ENABLE ROW LEVEL SECURITY;

--
-- Name: savings_calculation_lines; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.savings_calculation_lines ENABLE ROW LEVEL SECURITY;

--
-- Name: savings_calculations; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.savings_calculations ENABLE ROW LEVEL SECURITY;

--
-- Name: savings_periods; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.savings_periods ENABLE ROW LEVEL SECURITY;

--
-- Name: sourcing_events; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.sourcing_events ENABLE ROW LEVEL SECURITY;

--
-- Name: supplier_offer_lines; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.supplier_offer_lines ENABLE ROW LEVEL SECURITY;

--
-- Name: supplier_offers; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.supplier_offers ENABLE ROW LEVEL SECURITY;

--
-- Name: suppliers; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;

--
-- Name: SCHEMA public; Type: ACL; Schema: -; Owner: -
--

GRANT USAGE ON SCHEMA public TO postgres;
GRANT USAGE ON SCHEMA public TO anon;
GRANT USAGE ON SCHEMA public TO authenticated;
GRANT USAGE ON SCHEMA public TO service_role;


--
-- Name: FUNCTION clone_org_data(p_source uuid, p_target uuid, p_owner uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.clone_org_data(p_source uuid, p_target uuid, p_owner uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.clone_org_data(p_source uuid, p_target uuid, p_owner uuid) TO anon;
GRANT ALL ON FUNCTION public.clone_org_data(p_source uuid, p_target uuid, p_owner uuid) TO authenticated;
GRANT ALL ON FUNCTION public.clone_org_data(p_source uuid, p_target uuid, p_owner uuid) TO service_role;


--
-- Name: FUNCTION current_org_id(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.current_org_id() FROM PUBLIC;
GRANT ALL ON FUNCTION public.current_org_id() TO anon;
GRANT ALL ON FUNCTION public.current_org_id() TO authenticated;
GRANT ALL ON FUNCTION public.current_org_id() TO service_role;


--
-- Name: FUNCTION handle_new_user(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.handle_new_user() TO anon;
GRANT ALL ON FUNCTION public.handle_new_user() TO authenticated;
GRANT ALL ON FUNCTION public.handle_new_user() TO service_role;


--
-- Name: FUNCTION prevent_profile_privilege_change(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.prevent_profile_privilege_change() TO anon;
GRANT ALL ON FUNCTION public.prevent_profile_privilege_change() TO authenticated;
GRANT ALL ON FUNCTION public.prevent_profile_privilege_change() TO service_role;


--
-- Name: FUNCTION update_updated_at(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.update_updated_at() TO anon;
GRANT ALL ON FUNCTION public.update_updated_at() TO authenticated;
GRANT ALL ON FUNCTION public.update_updated_at() TO service_role;


--
-- Name: TABLE award_lines; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.award_lines TO anon;
GRANT ALL ON TABLE public.award_lines TO authenticated;
GRANT ALL ON TABLE public.award_lines TO service_role;


--
-- Name: TABLE awards; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.awards TO anon;
GRANT ALL ON TABLE public.awards TO authenticated;
GRANT ALL ON TABLE public.awards TO service_role;


--
-- Name: TABLE baseline_lines; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.baseline_lines TO anon;
GRANT ALL ON TABLE public.baseline_lines TO authenticated;
GRANT ALL ON TABLE public.baseline_lines TO service_role;


--
-- Name: TABLE baselines; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.baselines TO anon;
GRANT ALL ON TABLE public.baselines TO authenticated;
GRANT ALL ON TABLE public.baselines TO service_role;


--
-- Name: TABLE business_units; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.business_units TO anon;
GRANT ALL ON TABLE public.business_units TO authenticated;
GRANT ALL ON TABLE public.business_units TO service_role;


--
-- Name: TABLE categories; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.categories TO anon;
GRANT ALL ON TABLE public.categories TO authenticated;
GRANT ALL ON TABLE public.categories TO service_role;


--
-- Name: TABLE cost_centers; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.cost_centers TO anon;
GRANT ALL ON TABLE public.cost_centers TO authenticated;
GRANT ALL ON TABLE public.cost_centers TO service_role;


--
-- Name: TABLE event_scope_lines; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.event_scope_lines TO anon;
GRANT ALL ON TABLE public.event_scope_lines TO authenticated;
GRANT ALL ON TABLE public.event_scope_lines TO service_role;


--
-- Name: TABLE organizations; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.organizations TO anon;
GRANT ALL ON TABLE public.organizations TO authenticated;
GRANT ALL ON TABLE public.organizations TO service_role;


--
-- Name: TABLE profiles; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.profiles TO anon;
GRANT ALL ON TABLE public.profiles TO authenticated;
GRANT ALL ON TABLE public.profiles TO service_role;


--
-- Name: TABLE realization_periods; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.realization_periods TO anon;
GRANT ALL ON TABLE public.realization_periods TO authenticated;
GRANT ALL ON TABLE public.realization_periods TO service_role;


--
-- Name: TABLE savings_calculation_lines; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.savings_calculation_lines TO anon;
GRANT ALL ON TABLE public.savings_calculation_lines TO authenticated;
GRANT ALL ON TABLE public.savings_calculation_lines TO service_role;


--
-- Name: TABLE savings_calculations; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.savings_calculations TO anon;
GRANT ALL ON TABLE public.savings_calculations TO authenticated;
GRANT ALL ON TABLE public.savings_calculations TO service_role;


--
-- Name: TABLE savings_periods; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.savings_periods TO anon;
GRANT ALL ON TABLE public.savings_periods TO authenticated;
GRANT ALL ON TABLE public.savings_periods TO service_role;


--
-- Name: TABLE sourcing_events; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.sourcing_events TO anon;
GRANT ALL ON TABLE public.sourcing_events TO authenticated;
GRANT ALL ON TABLE public.sourcing_events TO service_role;


--
-- Name: TABLE supplier_offer_lines; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.supplier_offer_lines TO anon;
GRANT ALL ON TABLE public.supplier_offer_lines TO authenticated;
GRANT ALL ON TABLE public.supplier_offer_lines TO service_role;


--
-- Name: TABLE supplier_offers; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.supplier_offers TO anon;
GRANT ALL ON TABLE public.supplier_offers TO authenticated;
GRANT ALL ON TABLE public.supplier_offers TO service_role;


--
-- Name: TABLE suppliers; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.suppliers TO anon;
GRANT ALL ON TABLE public.suppliers TO authenticated;
GRANT ALL ON TABLE public.suppliers TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR SEQUENCES; Type: DEFAULT ACL; Schema: public; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR SEQUENCES; Type: DEFAULT ACL; Schema: public; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON SEQUENCES TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON SEQUENCES TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON SEQUENCES TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON SEQUENCES TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR FUNCTIONS; Type: DEFAULT ACL; Schema: public; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON FUNCTIONS TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON FUNCTIONS TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON FUNCTIONS TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON FUNCTIONS TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR FUNCTIONS; Type: DEFAULT ACL; Schema: public; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON FUNCTIONS TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON FUNCTIONS TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON FUNCTIONS TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON FUNCTIONS TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: public; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: public; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON TABLES TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON TABLES TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON TABLES TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON TABLES TO service_role;


--
-- PostgreSQL database dump complete
--


-- The supported Supabase user-management pattern is a trigger on auth.users.
-- It must be part of bootstrap even though auth is not part of schema.sql.
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();
