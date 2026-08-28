begin;

alter table public.suppliers
  add constraint suppliers_website_url_check
  check (
    website is null
    or (
      char_length(website) <= 2000
      and website ~* '^https?://'
    )
  ) not valid;

alter table public.suppliers
  validate constraint suppliers_website_url_check;

commit;
