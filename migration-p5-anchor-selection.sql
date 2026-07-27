-- =====================================================================
-- P5: ANCHOR SELECTION (Baseline / Opening / Final)
-- =====================================================================
-- Step 2 of the period model.
--
-- A project accumulates several baselines and several offer rounds. The
-- savings calculation only ever needs THREE of them:
--
--     Opening  ->  Baseline  ->  Final
--
-- So the record itself carries which role it plays, and the calculation is
-- DERIVED from those selections rather than re-typed by hand. This replaces
-- both "Select for Award" and "Create Award from Offer": marking an offer as
-- the Final offer IS the award decision.
--
-- Partial unique indexes enforce at most one of each role per project, so the
-- chain can never be ambiguous.
-- =====================================================================

begin;

-- Which baseline is THE baseline for this project.
alter table public.baselines
  add column if not exists is_selected boolean not null default false;

-- Which role an offer plays in the chain. NULL = just another round on file.
alter table public.supplier_offers
  add column if not exists offer_role text;

alter table public.supplier_offers drop constraint if exists chk_offer_role;
alter table public.supplier_offers add constraint chk_offer_role
  check (offer_role is null or offer_role in ('opening', 'final'));

comment on column public.baselines.is_selected is
  'True for the one baseline this project measures against. At most one per event.';
comment on column public.supplier_offers.offer_role is
  'Role in the savings chain: opening (the vendor first ask, drives Cost Avoidance), '
  'final (what was signed, drives Cost Reduction), or NULL for other rounds. '
  'Marking an offer as final IS the award decision.';

-- At most one of each role per project.
create unique index if not exists uq_baselines_selected
  on public.baselines(event_id) where is_selected;
create unique index if not exists uq_offers_opening
  on public.supplier_offers(event_id) where offer_role = 'opening';
create unique index if not exists uq_offers_final
  on public.supplier_offers(event_id) where offer_role = 'final';

-- ---------------------------------------------------------------------
-- Sensible defaults from what is already on file, so existing projects are
-- not blank. Each statement picks exactly one row per event.
-- ---------------------------------------------------------------------

-- The official (or earliest) baseline becomes the selected one.
update public.baselines b set is_selected = true
 where not exists (select 1 from public.baselines x
                    where x.event_id = b.event_id and x.is_selected)
   and b.id = (select id from public.baselines y
                where y.event_id = b.event_id
             order by y.official_for_hard_savings desc nulls last, y.created_at asc
                limit 1);

-- Lowest offer_round becomes the opening.
update public.supplier_offers o set offer_role = 'opening'
 where o.offer_role is null
   and not exists (select 1 from public.supplier_offers x
                    where x.event_id = o.event_id and x.offer_role = 'opening')
   and o.id = (select id from public.supplier_offers y
                where y.event_id = o.event_id
             order by y.offer_round asc nulls last, y.created_at asc
                limit 1);

-- A previously award-flagged offer, else the highest round, becomes the final.
update public.supplier_offers o set offer_role = 'final'
 where o.offer_role is null
   and not exists (select 1 from public.supplier_offers x
                    where x.event_id = o.event_id and x.offer_role = 'final')
   and o.id = (select id from public.supplier_offers y
                where y.event_id = o.event_id and y.offer_role is null
             order by y.selected_for_award_flag desc nulls last,
                      y.offer_round desc nulls last, y.created_at desc
                limit 1);

commit;

-- ---------------------------------------------------------------------
-- VERIFY (run separately) - each event should show at most one of each
-- ---------------------------------------------------------------------
-- select e.event_name,
--        (select count(*) from public.baselines b
--          where b.event_id = e.id and b.is_selected)              as baselines_selected,
--        (select count(*) from public.supplier_offers o
--          where o.event_id = e.id and o.offer_role = 'opening')   as openings,
--        (select count(*) from public.supplier_offers o
--          where o.event_id = e.id and o.offer_role = 'final')     as finals
--   from public.sourcing_events e
--  order by e.event_name;
