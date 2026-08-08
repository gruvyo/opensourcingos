create index if not exists idx_savings_calculations_executed_by
  on public.savings_calculations (executed_by)
  where executed_by is not null;

create index if not exists idx_sourcing_events_savings_disposition_by
  on public.sourcing_events (savings_disposition_by)
  where savings_disposition_by is not null;
