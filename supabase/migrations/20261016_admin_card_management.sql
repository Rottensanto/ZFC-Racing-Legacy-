alter table public.cards
  add column if not exists legend_pack_only boolean not null default false;

alter table public.cards
  add column if not exists copies_remaining integer
  check (copies_remaining is null or copies_remaining >= 0);

alter table public.cards
  add column if not exists is_published boolean not null default true;

drop policy if exists cards_read_catalog on public.cards;
create policy cards_read_catalog on public.cards
  for select to anon, authenticated using (is_published or public.is_admin());

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
    copies_remaining = least(
      coalesce(copies_remaining, 4),
      greatest(0, 4 - (select count(*) from public.user_cards where card_id = 'SENNA'))
    ),
    is_published = true
where id = 'SENNA';

drop function if exists public.admin_create_card(text, text, text, smallint, smallint, text, text, text, boolean, integer);

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
  if p_rarity not in ('rare', 'epic', 'icon', 'legend') then raise exception 'Ungültige Seltenheit.'; end if;
  if p_card_type not in ('DRIVER', 'CAR', 'TEAM', 'TRACK') then raise exception 'Ungültiger Kartentyp.'; end if;
  if p_image_url !~* '^https?://' then raise exception 'Die Bildadresse muss mit http:// oder https:// beginnen.'; end if;
  if p_copies_remaining is not null and (p_copies_remaining < 1 or p_copies_remaining > 100000) then
    raise exception 'Das Kartenlimit muss zwischen 1 und 100.000 liegen.';
  end if;

  insert into public.cards (
    id, name, short_name, card_year, rating, rarity, card_type, image_url, legend_pack_only, copies_remaining, is_published
  ) values (
    v_id, trim(p_name), trim(p_short_name), p_year, p_rating, p_rarity, p_card_type,
    trim(p_image_url), coalesce(p_legend_pack_only, false), p_copies_remaining, coalesce(p_is_published, true)
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
    copies_remaining = excluded.copies_remaining,
    is_published = excluded.is_published;

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

create or replace function public.purchase_pack(p_tier text)
returns table(instance_id uuid, catalog_id text, card_name text, short_name text, card_year smallint, rating smallint, rarity text, card_type text, image_url text, level smallint, tier text)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_price bigint;
  v_new_balance bigint;
  v_catalog_id text;
  v_instance_id uuid;
  v_instances uuid[] := array[]::uuid[];
  v_drawn_card_ids text[] := array[]::text[];
  v_index integer;
  v_card_count integer;
  v_roll double precision;
  v_target_tier text;
  v_candidate_id text;
  v_copies_remaining integer;
  v_special_draw boolean;
  v_special_slot integer;
begin
  if v_user_id is null then raise exception 'Bitte zuerst anmelden.'; end if;
  select price into v_price from public.pack_catalog where pack_catalog.tier = p_tier and enabled;
  if v_price is null then raise exception 'Dieses Pack ist nicht verfügbar.'; end if;
  v_card_count := case when p_tier = 'gold_double' then 10 else 5 end;
  v_special_draw := p_tier = 'legend' and random() < 0.01;
  if v_special_draw then
    v_special_slot := floor(random() * v_card_count)::integer + 1;
  end if;

  update public.profiles as p
    set coins = p.coins - v_price,
        progress_xp = p.progress_xp + v_price
    where p.id = v_user_id and p.coins >= v_price
    returning p.coins into v_new_balance;
  if not found then raise exception 'Nicht genügend Coins.'; end if;

  insert into public.coin_ledger(user_id, coins_delta, kind, detail)
    values (v_user_id, -v_price, 'pack_purchase', jsonb_build_object('tier', p_tier));

  for v_index in 1..v_card_count loop
    v_catalog_id := null;
    if v_special_draw and v_index = v_special_slot then
      update public.cards
        set copies_remaining = copies_remaining - 1
        where id = 'SENNA'
          and is_published
          and legend_pack_only
          and copies_remaining > 0
        returning id into v_catalog_id;
    end if;

    if v_catalog_id is null then
      v_roll := random() * 100;
      case p_tier
        when 'bronze' then
          v_target_tier := case when v_roll < 92 then 'bronze' else 'gold' end;
        when 'gold' then
          v_target_tier := case when v_roll < 92 then 'gold' when v_roll < 99 then 'platinum' else 'legend' end;
        when 'gold_double' then
          v_target_tier := case when v_roll < 96.5 then 'gold' when v_roll < 99.7 then 'platinum' else 'legend' end;
        when 'platinum' then
          v_target_tier := case when v_roll < 15 then 'gold' when v_roll < 95 then 'platinum' else 'legend' end;
        when 'legend' then
          v_target_tier := case when v_roll < 5 then 'gold' when v_roll < 35 then 'platinum' else 'legend' end;
      end case;

      loop
        v_catalog_id := null;
        select c.id, c.copies_remaining
          into v_candidate_id, v_copies_remaining
          from public.cards as c
          where case v_target_tier
              when 'legend' then c.tier in ('legend', 'platinum', 'gold', 'bronze')
              when 'platinum' then c.tier in ('platinum', 'gold', 'bronze')
              when 'gold' then c.tier in ('gold', 'bronze')
              else c.tier = 'bronze'
            end
            and c.id <> 'SENNA'
            and c.is_published
            and (not c.legend_pack_only or p_tier = 'legend')
            and (c.copies_remaining is null or c.copies_remaining > 0)
            and not (c.id = any(v_drawn_card_ids))
          order by case c.tier
            when v_target_tier then 0
            when 'platinum' then 1
            when 'gold' then 2
            else 3
          end, random()
          limit 1;
        if not found then
          raise exception 'Für dieses Pack sind nicht genügend unterschiedliche veröffentlichte Karten verfügbar.';
        end if;

        if v_copies_remaining is null then
          v_catalog_id := v_candidate_id;
        else
          update public.cards
            set copies_remaining = copies_remaining - 1
            where id = v_candidate_id and copies_remaining > 0
            returning id into v_catalog_id;
        end if;
        exit when v_catalog_id is not null;
      end loop;
    end if;

    insert into public.user_cards(user_id, card_id)
      values (v_user_id, v_catalog_id) returning id into v_instance_id;
    v_instances := array_append(v_instances, v_instance_id);
    v_drawn_card_ids := array_append(v_drawn_card_ids, v_catalog_id);
  end loop;

  return query
    select uc.id, c.id, c.name, c.short_name, c.card_year, c.rating, c.rarity, c.card_type, c.image_url, uc.level, c.tier
    from public.user_cards as uc
    join public.cards as c on c.id = uc.card_id
    where uc.id = any(v_instances)
    order by array_position(v_instances, uc.id);
end;
$$;

revoke all on function public.admin_create_card(text, text, text, smallint, smallint, text, text, text, boolean, integer, boolean) from public, anon;
revoke all on function public.admin_grant_card(text, text) from public, anon;
revoke all on function public.purchase_pack(text) from public, anon;

grant execute on function public.admin_create_card(text, text, text, smallint, smallint, text, text, text, boolean, integer, boolean) to authenticated;
grant execute on function public.admin_grant_card(text, text) to authenticated;
grant execute on function public.purchase_pack(text) to authenticated;

notify pgrst, 'reload schema';
