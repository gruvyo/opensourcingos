begin;

create index idx_supplier_performance_reviews_supplier_workspace
  on public.supplier_performance_reviews (supplier_id, organization_id);

commit;
