begin;

-- The BEFORE trigger always replaces this placeholder with the canonical
-- value. The default tells generated API types that callers may continue to
-- omit this database-managed column.
alter table public.suppliers
  alter column supplier_normalized_name set default '';

commit;
