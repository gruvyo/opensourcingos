begin;

create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public, pg_catalog;

select plan(6);

select ok(
  exists (
    select 1
    from pg_catalog.pg_constraint
    where conrelid = 'public.suppliers'::regclass
      and conname = 'suppliers_website_url_check'
      and convalidated
  ),
  'supplier websites have a validated database constraint'
);

select ok(
  (select pg_get_constraintdef(oid) ~* 'https.*char_length|char_length.*https'
   from pg_catalog.pg_constraint
   where conrelid = 'public.suppliers'::regclass
     and conname = 'suppliers_website_url_check'),
  'the supplier website constraint limits both scheme and length'
);

select is(
  (select count(*)::bigint
   from pg_catalog.pg_constraint
   where conrelid in ('public.supplier_certifications'::regclass, 'public.supplier_risks'::regclass)
     and conname in ('supplier_certifications_url_check', 'supplier_risks_url_check')
     and convalidated),
  2::bigint,
  'both evidence URL constraints remain validated'
);

select throws_ok(
  $$update public.suppliers set website = 'javascript:alert(1)' where id = '00000000-0000-4000-8000-000000000013'$$,
  '23514',
  'new row for relation "suppliers" violates check constraint "suppliers_website_url_check"',
  'a direct database write cannot store an executable supplier URL'
);

select throws_ok(
  $$update public.suppliers set website = 'https://example.com/' || repeat('a', 2000) where id = '00000000-0000-4000-8000-000000000013'$$,
  '23514',
  'new row for relation "suppliers" violates check constraint "suppliers_website_url_check"',
  'a direct database write cannot exceed the supplier URL length limit'
);

select lives_ok(
  $$update public.suppliers set website = 'https://example.com' where id = '00000000-0000-4000-8000-000000000013'$$,
  'a normal HTTPS supplier website remains valid'
);

select * from finish();
rollback;
