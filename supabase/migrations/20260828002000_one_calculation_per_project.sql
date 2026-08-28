-- A sourcing project owns one mutable savings calculation. This partial
-- unique index preserves the existing allowance for legacy unlinked rows while
-- rejecting a second calculation for any real project.
--
-- Forward rollback, if ever required:
--   drop index public.uq_savings_calculations_event;

create unique index uq_savings_calculations_event
  on public.savings_calculations (event_id)
  where event_id is not null;
