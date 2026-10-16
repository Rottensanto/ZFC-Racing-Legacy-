alter table public.cards
  add column if not exists tier text;

do $$
begin
  if exists (
    select 1
    from pg_attribute
    where attrelid = 'public.cards'::regclass
      and attname = 'tier'
      and attgenerated <> ''
  ) then
    alter table public.cards alter column tier drop expression;
  end if;
end;
$$;

update public.cards
set tier = case
  when rating >= 96 then 'legend'
  when rating >= 90 then 'platinum'
  when rating >= 85 then 'gold'
  else 'bronze'
end
where tier is null;

alter table public.cards alter column tier set not null;
alter table public.cards drop constraint if exists cards_tier_check;
alter table public.cards
  add constraint cards_tier_check
  check (tier in ('bronze', 'gold', 'platinum', 'legend'));

create or replace function public.set_default_card_tier()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if new.tier is null then
    new.tier := case
      when new.rating >= 96 then 'legend'
      when new.rating >= 90 then 'platinum'
      when new.rating >= 85 then 'gold'
      else 'bronze'
    end;
  end if;
  return new;
end;
$$;

drop trigger if exists cards_set_default_tier on public.cards;
create trigger cards_set_default_tier
before insert on public.cards
for each row execute function public.set_default_card_tier();

drop function if exists public.admin_create_card(text, text, text, smallint, smallint, text, text, text, boolean, integer);
drop function if exists public.admin_create_card(text, text, text, smallint, smallint, text, text, text, boolean, integer, boolean);

create or replace function public.admin_create_card(
  p_id text,
  p_name text,
  p_short_name text,
  p_year smallint,
  p_rating smallint,
  p_tier text,
  p_rarity text,
  p_card_type text,
  p_image_url text,
  p_legend_pack_only boolean default false,
  p_copies_remaining integer default null,
  p_is_published boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_id text := upper(trim(coalesce(p_id, '')));
begin
  if not public.is_admin() then raise exception 'Admin-Berechtigung erforderlich.'; end if;
  if v_id !~ '^[A-Z0-9_-]{2,64}$' then raise exception 'Ungültige Karten-ID.'; end if;
  if v_id = 'SENNA' then raise exception 'Die limitierte Senna-Karte kann nicht über dieses Formular geändert werden.'; end if;
  if nullif(trim(coalesce(p_name, '')), '') is null
     or nullif(trim(coalesce(p_short_name, '')), '') is null then
    raise exception 'Kartenname und Kurzname dürfen nicht leer sein.';
  end if;
  if p_year is null or p_year < 1900 or p_year > 2100 then raise exception 'Ungültige Saison.'; end if;
  if p_rating is null or p_rating < 1 or p_rating > 100 then raise exception 'Das Rating muss zwischen 1 und 100 liegen.'; end if;
  if p_tier is null or p_tier not in ('bronze', 'gold', 'platinum', 'legend') then raise exception 'Ungültige Kartenstufe.'; end if;
  if p_rarity not in ('rare', 'epic', 'icon', 'legend') then raise exception 'Ungültige Seltenheit.'; end if;
  if p_card_type not in ('DRIVER', 'CAR', 'TEAM', 'TRACK') then raise exception 'Ungültiger Kartentyp.'; end if;
  if p_image_url is null or p_image_url !~* '^https?://' then raise exception 'Die Bildadresse muss mit http:// oder https:// beginnen.'; end if;
  if p_copies_remaining is not null and (p_copies_remaining < 1 or p_copies_remaining > 100000) then
    raise exception 'Das Kartenlimit muss zwischen 1 und 100.000 liegen.';
  end if;

  insert into public.cards (
    id, name, short_name, card_year, rating, tier, rarity, card_type, image_url, legend_pack_only, copies_remaining, is_published
  ) values (
    v_id, trim(p_name), trim(p_short_name), p_year, p_rating, p_tier, p_rarity, p_card_type,
    trim(p_image_url), coalesce(p_legend_pack_only, false), p_copies_remaining, coalesce(p_is_published, true)
  )
  on conflict (id) do update set
    name = excluded.name,
    short_name = excluded.short_name,
    card_year = excluded.card_year,
    rating = excluded.rating,
    tier = excluded.tier,
    rarity = excluded.rarity,
    card_type = excluded.card_type,
    image_url = excluded.image_url,
    legend_pack_only = excluded.legend_pack_only,
    copies_remaining = excluded.copies_remaining,
    is_published = excluded.is_published;

  return jsonb_build_object('id', v_id, 'name', trim(p_name));
end;
$$;

revoke all on function public.admin_create_card(text, text, text, smallint, smallint, text, text, text, text, boolean, integer, boolean) from public, anon;
grant execute on function public.admin_create_card(text, text, text, smallint, smallint, text, text, text, text, boolean, integer, boolean) to authenticated;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('card-images', 'card-images', true, 8388608, array['image/jpeg', 'image/png', 'image/webp', 'image/gif'])
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "Public card image read" on storage.objects;
create policy "Public card image read" on storage.objects
  for select to public
  using (bucket_id = 'card-images');

drop policy if exists "Admin card image upload" on storage.objects;
create policy "Admin card image upload" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'card-images' and public.is_admin());

drop policy if exists "Admin card image update" on storage.objects;
create policy "Admin card image update" on storage.objects
  for update to authenticated
  using (bucket_id = 'card-images' and public.is_admin())
  with check (bucket_id = 'card-images' and public.is_admin());

drop policy if exists "Admin card image delete" on storage.objects;
create policy "Admin card image delete" on storage.objects
  for delete to authenticated
  using (bucket_id = 'card-images' and public.is_admin());

notify pgrst, 'reload schema';
