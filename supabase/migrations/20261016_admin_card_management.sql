alter table public.cards
  add column if not exists legend_pack_only boolean not null default false;

alter table public.cards
  add column if not exists copies_remaining integer
  check (copies_remaining is null or copies_remaining >= 0);

insert into public.cards (id, name, short_name, card_year, rating, rarity, card_type, image_url, legend_pack_only, copies_remaining)
values (
  'SENNA',
  'Ayrton Senna · Weltmeister 1991',
  'SENNA 1991',
  1991,
  99,
  'legend',
  'DRIVER',
  'https://upload.wikimedia.org/wikipedia/commons/b/be/Ayrton_Senna_Montreal_1988.jpg',
  true,
  4
)
on conflict (id) do update set
  name = excluded.name,
  short_name = excluded.short_name,
  card_year = excluded.card_year,
  rating = excluded.rating,
  rarity = excluded.rarity,
  card_type = excluded.card_type,
  image_url = excluded.image_url,
  legend_pack_only = true;

update public.cards
set legend_pack_only = true,
    copies_remaining = greatest(0, 4 - (select count(*) from public.user_cards where card_id = 'SENNA'))
where id = 'SENNA';

create or replace function public.admin_create_card(
  p_id text,
  p_name text,
  p_short_name text,
  p_year smallint,
  p_rating smallint,
  p_rarity text,
  p_card_type text,
  p_image_url text,
  p_legend_pack_only boolean default false,
  p_copies_remaining integer default null
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
  if p_rarity not in ('rare', 'epic', 'icon', 'legend') then raise exception 'Ungültige Seltenheit.'; end if;
  if p_card_type not in ('DRIVER', 'CAR', 'TEAM', 'TRACK') then raise exception 'Ungültiger Kartentyp.'; end if;
  if p_image_url !~* '^https?://' then raise exception 'Die Bildadresse muss mit http:// oder https:// beginnen.'; end if;
  if p_copies_remaining is not null and (p_copies_remaining < 1 or p_copies_remaining > 100000) then
    raise exception 'Das Kartenlimit muss zwischen 1 und 100.000 liegen.';
  end if;

  insert into public.cards (
    id, name, short_name, card_year, rating, rarity, card_type, image_url, legend_pack_only, copies_remaining
  ) values (
    v_id, trim(p_name), trim(p_short_name), p_year, p_rating, p_rarity, p_card_type,
    trim(p_image_url), coalesce(p_legend_pack_only, false), p_copies_remaining
  )
  on conflict (id) do update set
    name = excluded.name,
    short_name = excluded.short_name,
    card_year = excluded.card_year,
    rating = excluded.rating,
    rarity = excluded.rarity,
    card_type = excluded.card_type,
    image_url = excluded.image_url,
    legend_pack_only = excluded.legend_pack_only,
    copies_remaining = excluded.copies_remaining;

  return jsonb_build_object('id', v_id, 'name', trim(p_name));
end;
$$;

create or replace function public.admin_grant_card(p_email text, p_card_id text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid;
  v_display_name text;
  v_card_name text;
  v_copies_remaining integer;
begin
  if not public.is_admin() then raise exception 'Admin-Berechtigung erforderlich.'; end if;
  if nullif(trim(coalesce(p_email, '')), '') is null or nullif(trim(coalesce(p_card_id, '')), '') is null then
    raise exception 'Spieler-E-Mail und Karten-ID müssen angegeben werden.';
  end if;

  select p.id, p.display_name, c.name, c.copies_remaining
    into v_user_id, v_display_name, v_card_name, v_copies_remaining
    from public.profiles as p
    cross join public.cards as c
    where lower(p.email) = lower(trim(p_email))
      and c.id = upper(trim(p_card_id))
    for update of c;
  if not found then raise exception 'Spielerkonto oder Karte nicht gefunden.'; end if;
  if v_copies_remaining is not null then
    if v_copies_remaining < 1 then raise exception 'Von dieser limitierten Karte ist kein Exemplar mehr verfügbar.'; end if;
    update public.cards
      set copies_remaining = copies_remaining - 1
      where id = upper(trim(p_card_id));
  end if;

  insert into public.user_cards(user_id, card_id)
    values (v_user_id, upper(trim(p_card_id)));

  return jsonb_build_object(
    'card_name', v_card_name,
    'display_name', v_display_name,
    'email', lower(trim(p_email))
  );
end;
$$;

revoke all on function public.admin_create_card(text, text, text, smallint, smallint, text, text, text, boolean, integer) from public, anon;
revoke all on function public.admin_grant_card(text, text) from public, anon;

grant execute on function public.admin_create_card(text, text, text, smallint, smallint, text, text, text, boolean, integer) to authenticated;
grant execute on function public.admin_grant_card(text, text) to authenticated;

notify pgrst, 'reload schema';
