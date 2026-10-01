create extension if not exists pgcrypto;

create table if not exists public.user_roles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  role text not null check (role in ('admin')),
  created_at timestamptz not null default now()
);

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text not null unique,
  display_name text not null default 'F1 Driver',
  coins bigint not null default 0 check (coins >= 0),
  f1_points bigint not null default 0 check (f1_points >= 0),
  created_at timestamptz not null default now()
);

create table if not exists public.cards (
  id text primary key,
  name text not null,
  short_name text not null,
  card_year smallint not null,
  rating smallint not null check (rating between 1 and 100),
  rarity text not null check (rarity in ('rare', 'epic', 'icon', 'legend')),
  card_type text not null,
  image_url text not null,
  tier text generated always as (
    case
      when rating >= 96 then 'legend'
      when rating >= 90 then 'platinum'
      when rating >= 85 then 'gold'
      else 'bronze'
    end
  ) stored
);

create table if not exists public.pack_catalog (
  tier text primary key check (tier in ('bronze', 'platinum', 'gold', 'legend')),
  name text not null,
  price bigint not null check (price > 0),
  enabled boolean not null default true
);

create table if not exists public.user_cards (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  card_id text not null references public.cards(id),
  level smallint not null default 1 check (level between 1 and 10),
  obtained_at timestamptz not null default now()
);

create index if not exists user_cards_owner_idx on public.user_cards(user_id, obtained_at desc);

create table if not exists public.coin_ledger (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  coins_delta bigint not null,
  kind text not null check (kind in ('pack_purchase', 'card_sale', 'point_conversion', 'card_upgrade')),
  detail jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists coin_ledger_owner_day_idx on public.coin_ledger(user_id, kind, created_at desc);

create table if not exists public.point_ledger (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  points_delta bigint not null,
  event_name text not null,
  finish_position smallint not null check (finish_position between 1 and 10),
  admin_id uuid not null references auth.users(id),
  created_at timestamptz not null default now()
);

create index if not exists point_ledger_owner_idx on public.point_ledger(user_id, created_at desc);
create unique index if not exists point_ledger_user_event_unique on public.point_ledger(user_id, lower(event_name));

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.user_roles
    where user_id = auth.uid() and role = 'admin'
  );
$$;

revoke all on function public.is_admin() from public, anon;
grant execute on function public.is_admin() to authenticated;

create or replace function public.create_profile_for_new_user()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  insert into public.profiles (id, email, display_name)
  values (
    new.id,
    lower(trim(new.email)),
    coalesce(nullif(trim(new.raw_user_meta_data->>'full_name'), ''), split_part(lower(trim(new.email)), '@', 1), 'F1 Driver')
  )
  on conflict (id) do update set email = excluded.email;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created_profile on auth.users;
create trigger on_auth_user_created_profile
  after insert on auth.users
  for each row execute procedure public.create_profile_for_new_user();

alter table public.user_roles enable row level security;
alter table public.profiles enable row level security;
alter table public.cards enable row level security;
alter table public.pack_catalog enable row level security;
alter table public.user_cards enable row level security;
alter table public.coin_ledger enable row level security;
alter table public.point_ledger enable row level security;

drop policy if exists profiles_read_owner_or_admin on public.profiles;
create policy profiles_read_owner_or_admin on public.profiles
  for select to authenticated
  using (id = auth.uid() or public.is_admin());

drop policy if exists cards_read_catalog on public.cards;
create policy cards_read_catalog on public.cards
  for select to anon, authenticated using (true);

drop policy if exists packs_read_catalog on public.pack_catalog;
create policy packs_read_catalog on public.pack_catalog
  for select to anon, authenticated using (enabled);

drop policy if exists user_cards_read_owner_or_admin on public.user_cards;
create policy user_cards_read_owner_or_admin on public.user_cards
  for select to authenticated
  using (user_id = auth.uid() or public.is_admin());

drop policy if exists coin_ledger_read_owner_or_admin on public.coin_ledger;
create policy coin_ledger_read_owner_or_admin on public.coin_ledger
  for select to authenticated
  using (user_id = auth.uid() or public.is_admin());

drop policy if exists point_ledger_read_owner_or_admin on public.point_ledger;
create policy point_ledger_read_owner_or_admin on public.point_ledger
  for select to authenticated
  using (user_id = auth.uid() or public.is_admin());

revoke all on public.user_roles, public.profiles, public.user_cards, public.coin_ledger, public.point_ledger from anon, authenticated;
grant select on public.profiles, public.user_cards, public.coin_ledger, public.point_ledger to authenticated;
grant select on public.cards, public.pack_catalog to anon, authenticated;

insert into public.cards (id, name, short_name, card_year, rating, rarity, card_type, image_url) values
  ('FANGIO', 'Juan Manuel Fangio', 'FANGIO', 1954, 98, 'legend', 'LEGEND', 'https://thumb.wikimedia.org/wikipedia/commons/thumb/c/ca/Beaufort_at_1961_Dutch_Grand_Prix_%282%29.jpg/960px-Beaufort_at_1961_Dutch_Grand_Prix_%282%29.jpg'),
  ('SENNA', 'Ayrton Senna', 'SENNA', 1990, 94, 'icon', 'ICON', 'https://thumb.wikimedia.org/wikipedia/commons/thumb/0/06/ClarkJim-Lotus19620805.jpg/960px-ClarkJim-Lotus19620805.jpg'),
  ('SCHUMACHER', 'Michael Schumacher', 'SCHUMACHER', 2001, 91, 'epic', 'EPIC', 'https://thumb.wikimedia.org/wikipedia/commons/thumb/a/a3/2004_Williams_FW26.jpg/960px-2004_Williams_FW26.jpg'),
  ('HAMILTON', 'Lewis Hamilton', 'HAMILTON', 2020, 88, 'rare', 'RARE', 'https://thumb.wikimedia.org/wikipedia/commons/thumb/c/c0/2022_British_Grand_Prix_%2852382575808%29.jpg/960px-2022_British_Grand_Prix_%2852382575808%29.jpg'),
  ('VERSTAPPEN', 'Max Verstappen', 'VERSTAPPEN', 2023, 85, 'rare', 'RARE', 'https://thumb.wikimedia.org/wikipedia/commons/thumb/a/a2/2015_Malaysian_GP_opening_lap.jpg/960px-2015_Malaysian_GP_opening_lap.jpg'),
  ('PROST', 'Alain Prost', 'PROST', 1988, 90, 'epic', 'EPIC', 'https://thumb.wikimedia.org/wikipedia/commons/thumb/d/d6/1985_European_GP_Brundle_02.jpg/960px-1985_European_GP_Brundle_02.jpg'),
  ('RAIKKONEN', 'Kimi Räikkönen', 'RÄIKKÖNEN', 2007, 82, 'rare', 'RARE', 'https://thumb.wikimedia.org/wikipedia/commons/thumb/1/1c/2018_Chinese_Grand_Prix_FP3_Fernando_Alonso_%2840970600574%29.jpg/960px-2018_Chinese_Grand_Prix_FP3_Fernando_Alonso_%2840970600574%29.jpg'),
  ('ROSBERG', 'Nico Rosberg', 'ROSBERG', 2013, 83, 'rare', 'RARE', 'https://thumb.wikimedia.org/wikipedia/commons/thumb/2/25/Drivers_at_1969_Dutch_Grand_Prix.jpg/960px-Drivers_at_1969_Dutch_Grand_Prix.jpg'),
  ('MANSELL', 'Nigel Mansell', 'MANSELL', 1992, 87, 'rare', 'RARE', 'https://thumb.wikimedia.org/wikipedia/commons/thumb/d/d5/Grand_Prix_Zandvoort_1966_Taylor%2C_Bestanddeelnr_919-3828.jpg/960px-Grand_Prix_Zandvoort_1966_Taylor%2C_Bestanddeelnr_919-3828.jpg'),
  ('F2004', 'Ferrari F2004', 'F2004', 2004, 94, 'icon', 'CAR', 'https://thumb.wikimedia.org/wikipedia/commons/thumb/a/a3/2004_Williams_FW26.jpg/960px-2004_Williams_FW26.jpg'),
  ('MP4-4', 'McLaren MP4/4', 'MP4/4', 1988, 96, 'legend', 'CAR', 'https://thumb.wikimedia.org/wikipedia/commons/thumb/b/b6/Lotus_95T_Elio_De_Angelis_Detroit_Grand_Prix_1984a.jpeg/960px-Lotus_95T_Elio_De_Angelis_Detroit_Grand_Prix_1984a.jpeg'),
  ('RB19', 'Red Bull RB19', 'RB19', 2023, 92, 'icon', 'CAR', 'https://thumb.wikimedia.org/wikipedia/commons/thumb/c/c6/2018_Chinese_Grand_Prix_FP3_Charles_Leclerc_%2839897914770%29.jpg/960px-2018_Chinese_Grand_Prix_FP3_Charles_Leclerc_%2839897914770%29.jpg')
on conflict (id) do update set
  name = excluded.name,
  short_name = excluded.short_name,
  card_year = excluded.card_year,
  rating = excluded.rating,
  rarity = excluded.rarity,
  card_type = excluded.card_type,
  image_url = excluded.image_url;

insert into public.cards (id, name, short_name, card_year, rating, rarity, card_type, image_url) values
  ('DRV26-LANNOR', 'Lando Norris', 'NORRIS', 2026, 84, 'rare', 'DRIVER', 'https://media.formula1.com/image/upload/c_lfill,w_440/q_auto/d_common:f1:2026:fallback:driver:2026fallbackdriverright.webp/v1740000001/common/f1/2026/mclaren/lannor01/2026mclarenlannor01right.webp'),
  ('DRV26-OSPIA', 'Oscar Piastri', 'PIASTRI', 2026, 84, 'rare', 'DRIVER', 'https://media.formula1.com/image/upload/c_lfill,w_440/q_auto/d_common:f1:2026:fallback:driver:2026fallbackdriverright.webp/v1740000001/common/f1/2026/mclaren/oscpia01/2026mclarenoscpia01right.webp'),
  ('DRV26-GERUS', 'George Russell', 'RUSSELL', 2026, 84, 'rare', 'DRIVER', 'https://media.formula1.com/image/upload/c_lfill,w_440/q_auto/d_common:f1:2026:fallback:driver:2026fallbackdriverright.webp/v1740000001/common/f1/2026/mercedes/georus01/2026mercedesgeorus01right.webp'),
  ('DRV26-ANDANT', 'Andrea Kimi Antonelli', 'ANTONELLI', 2026, 81, 'rare', 'DRIVER', 'https://media.formula1.com/image/upload/c_lfill,w_440/q_auto/d_common:f1:2026:fallback:driver:2026fallbackdriverright.webp/v1740000001/common/f1/2026/mercedes/andant01/2026mercedesandant01right.webp'),
  ('DRV26-MAXVER', 'Max Verstappen', 'VERSTAPPEN', 2026, 84, 'rare', 'DRIVER', 'https://media.formula1.com/image/upload/c_lfill,w_440/q_auto/d_common:f1:2026:fallback:driver:2026fallbackdriverright.webp/v1740000001/common/f1/2026/redbullracing/maxver01/2026redbullracingmaxver01right.webp'),
  ('DRV26-ISAHAD', 'Isack Hadjar', 'HADJAR', 2026, 79, 'rare', 'DRIVER', 'https://media.formula1.com/image/upload/c_lfill,w_440/q_auto/d_common:f1:2026:fallback:driver:2026fallbackdriverright.webp/v1740000001/common/f1/2026/redbullracing/isahad01/2026redbullracingisahad01right.webp'),
  ('DRV26-CHALEC', 'Charles Leclerc', 'LECLERC', 2026, 84, 'rare', 'DRIVER', 'https://media.formula1.com/image/upload/c_lfill,w_440/q_auto/d_common:f1:2026:fallback:driver:2026fallbackdriverright.webp/v1740000001/common/f1/2026/ferrari/chalec01/2026ferrarichalec01right.webp'),
  ('DRV26-LEWHAM', 'Lewis Hamilton', 'HAMILTON', 2026, 84, 'rare', 'DRIVER', 'https://media.formula1.com/image/upload/c_lfill,w_440/q_auto/d_common:f1:2026:fallback:driver:2026fallbackdriverright.webp/v1740000001/common/f1/2026/ferrari/lewham01/2026ferrarilewham01right.webp'),
  ('DRV26-ALEALB', 'Alexander Albon', 'ALBON', 2026, 82, 'rare', 'DRIVER', 'https://media.formula1.com/image/upload/c_lfill,w_440/q_auto/d_common:f1:2026:fallback:driver:2026fallbackdriverright.webp/v1740000001/common/f1/2026/williams/alealb01/2026williamsalealb01right.webp'),
  ('DRV26-CARSAI', 'Carlos Sainz', 'SAINZ', 2026, 82, 'rare', 'DRIVER', 'https://media.formula1.com/image/upload/c_lfill,w_440/q_auto/d_common:f1:2026:fallback:driver:2026fallbackdriverright.webp/v1740000001/common/f1/2026/williams/carsai01/2026williamscarsai01right.webp'),
  ('DRV26-LIALAW', 'Liam Lawson', 'LAWSON', 2026, 79, 'rare', 'DRIVER', 'https://media.formula1.com/image/upload/c_lfill,w_440/q_auto/d_common:f1:2026:fallback:driver:2026fallbackdriverright.webp/v1740000001/common/f1/2026/racingbulls/lialaw01/2026racingbullslialaw01right.webp'),
  ('DRV26-ARVLIN', 'Arvid Lindblad', 'LINDBLAD', 2026, 77, 'rare', 'DRIVER', 'https://media.formula1.com/image/upload/c_lfill,w_440/q_auto/d_common:f1:2026:fallback:driver:2026fallbackdriverright.webp/v1740000001/common/f1/2026/racingbulls/arvlin01/2026racingbullsarvlin01right.webp'),
  ('DRV26-FERALO', 'Fernando Alonso', 'ALONSO', 2026, 83, 'rare', 'DRIVER', 'https://media.formula1.com/image/upload/c_lfill,w_440/q_auto/d_common:f1:2026:fallback:driver:2026fallbackdriverright.webp/v1740000001/common/f1/2026/astonmartin/feralo01/2026astonmartinferalo01right.webp'),
  ('DRV26-LANSTR', 'Lance Stroll', 'STROLL', 2026, 79, 'rare', 'DRIVER', 'https://media.formula1.com/image/upload/c_lfill,w_440/q_auto/d_common:f1:2026:fallback:driver:2026fallbackdriverright.webp/v1740000001/common/f1/2026/astonmartin/lanstr01/2026astonmartinlanstr01right.webp'),
  ('DRV26-ESTOCO', 'Esteban Ocon', 'OCON', 2026, 81, 'rare', 'DRIVER', 'https://media.formula1.com/image/upload/c_lfill,w_440/q_auto/d_common:f1:2026:fallback:driver:2026fallbackdriverright.webp/v1740000001/common/f1/2026/haasf1team/estoco01/2026haasf1teamestoco01right.webp'),
  ('DRV26-OLIBEA', 'Oliver Bearman', 'BEARMAN', 2026, 81, 'rare', 'DRIVER', 'https://media.formula1.com/image/upload/c_lfill,w_440/q_auto/d_common:f1:2026:fallback:driver:2026fallbackdriverright.webp/v1740000001/common/f1/2026/haasf1team/olibea01/2026haasf1teamolibea01right.webp'),
  ('DRV26-NICHUL', 'Nico Hülkenberg', 'HULKENBERG', 2026, 82, 'rare', 'DRIVER', 'https://media.formula1.com/image/upload/c_lfill,w_440/q_auto/d_common:f1:2026:fallback:driver:2026fallbackdriverright.webp/v1740000001/common/f1/2026/audi/nichul01/2026audinichul01right.webp'),
  ('DRV26-GABBOR', 'Gabriel Bortoleto', 'BORTOLETO', 2026, 79, 'rare', 'DRIVER', 'https://media.formula1.com/image/upload/c_lfill,w_440/q_auto/d_common:f1:2026:fallback:driver:2026fallbackdriverright.webp/v1740000001/common/f1/2026/audi/gabbor01/2026audigabbor01right.webp'),
  ('DRV26-PIEGAS', 'Pierre Gasly', 'GASLY', 2026, 81, 'rare', 'DRIVER', 'https://media.formula1.com/image/upload/c_lfill,w_440/q_auto/d_common:f1:2026:fallback:driver:2026fallbackdriverright.webp/v1740000001/common/f1/2026/alpine/piegas01/2026alpinepiegas01right.webp'),
  ('DRV26-FRACOL', 'Franco Colapinto', 'COLAPINTO', 2026, 79, 'rare', 'DRIVER', 'https://media.formula1.com/image/upload/c_lfill,w_440/q_auto/d_common:f1:2026:fallback:driver:2026fallbackdriverright.webp/v1740000001/common/f1/2026/alpine/fracol01/2026alpinefracol01right.webp'),
  ('DRV26-SERPER', 'Sergio Pérez', 'PEREZ', 2026, 81, 'rare', 'DRIVER', 'https://media.formula1.com/image/upload/c_lfill,w_440/q_auto/d_common:f1:2026:fallback:driver:2026fallbackdriverright.webp/v1740000001/common/f1/2026/cadillac/serper01/2026cadillacserper01right.webp'),
  ('DRV26-VALBOT', 'Valtteri Bottas', 'BOTTAS', 2026, 82, 'rare', 'DRIVER', 'https://media.formula1.com/image/upload/c_lfill,w_440/q_auto/d_common:f1:2026:fallback:driver:2026fallbackdriverright.webp/v1740000001/common/f1/2026/cadillac/valbot01/2026cadillacvalbot01right.webp'),
  ('TEAM26-MCLAREN', 'McLaren', 'MCLAREN', 2026, 84, 'rare', 'TEAM', 'https://media.formula1.com/image/upload/c_fit,w_500/q_auto/v1740000001/common/f1/2026/mclaren/2026mclarenlogowhite.webp'),
  ('TEAM26-MERCEDES', 'Mercedes', 'MERCEDES', 2026, 84, 'rare', 'TEAM', 'https://media.formula1.com/image/upload/c_fit,w_500/q_auto/v1740000001/common/f1/2026/mercedes/2026mercedeslogowhite.webp'),
  ('TEAM26-REDBULL', 'Red Bull Racing', 'RED BULL', 2026, 84, 'rare', 'TEAM', 'https://media.formula1.com/image/upload/c_fit,w_500/q_auto/v1740000001/common/f1/2026/redbullracing/2026redbullracinglogowhite.webp'),
  ('TEAM26-FERRARI', 'Scuderia Ferrari', 'FERRARI', 2026, 84, 'rare', 'TEAM', 'https://media.formula1.com/image/upload/c_fit,w_500/q_auto/v1740000001/common/f1/2026/ferrari/2026ferrarilogowhite.webp'),
  ('TEAM26-WILLIAMS', 'Williams', 'WILLIAMS', 2026, 82, 'rare', 'TEAM', 'https://media.formula1.com/image/upload/c_fit,w_500/q_auto/v1740000001/common/f1/2026/williams/2026williamslogowhite.webp'),
  ('TEAM26-RACINGBULLS', 'Racing Bulls', 'RACING BULLS', 2026, 79, 'rare', 'TEAM', 'https://media.formula1.com/image/upload/c_fit,w_500/q_auto/v1740000001/common/f1/2026/racingbulls/2026racingbullslogowhite.webp'),
  ('TEAM26-ASTONMARTIN', 'Aston Martin', 'ASTON MARTIN', 2026, 81, 'rare', 'TEAM', 'https://media.formula1.com/image/upload/c_fit,w_500/q_auto/v1740000001/common/f1/2026/astonmartin/2026astonmartinlogowhite.webp'),
  ('TEAM26-HAAS', 'Haas F1 Team', 'HAAS', 2026, 80, 'rare', 'TEAM', 'https://media.formula1.com/image/upload/c_fit,w_500/q_auto/v1740000001/common/f1/2026/haasf1team/2026haasf1teamlogowhite.webp'),
  ('TEAM26-AUDI', 'Audi', 'AUDI', 2026, 78, 'rare', 'TEAM', 'https://media.formula1.com/image/upload/c_fit,w_500/q_auto/v1740000001/common/f1/2026/audi/2026audilogowhite.webp'),
  ('TEAM26-ALPINE', 'Alpine', 'ALPINE', 2026, 80, 'rare', 'TEAM', 'https://media.formula1.com/image/upload/c_fit,w_500/q_auto/v1740000001/common/f1/2026/alpine/2026alpinelogowhite.webp'),
  ('TEAM26-CADILLAC', 'Cadillac', 'CADILLAC', 2026, 76, 'rare', 'TEAM', 'https://media.formula1.com/image/upload/c_fit,w_500/q_auto/v1740000001/common/f1/2026/cadillac/2026cadillaclogowhite.webp')
on conflict (id) do update set
  name = excluded.name,
  short_name = excluded.short_name,
  card_year = excluded.card_year,
  rating = excluded.rating,
  rarity = excluded.rarity,
  card_type = excluded.card_type,
  image_url = excluded.image_url;

insert into public.pack_catalog (tier, name, price) values
  ('bronze', 'BRONZE PACK', 1000),
  ('platinum', 'PLATINUM PACK', 5000),
  ('gold', 'GOLD PACK', 9500),
  ('legend', 'LEGEND PACK', 17000)
on conflict (tier) do update set name = excluded.name, price = excluded.price, enabled = true;

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
  v_index integer;
begin
  if v_user_id is null then raise exception 'Bitte zuerst anmelden.'; end if;
  select price into v_price from public.pack_catalog where pack_catalog.tier = p_tier and enabled;
  if v_price is null then raise exception 'Dieses Pack ist nicht verfügbar.'; end if;

  update public.profiles as p
    set coins = p.coins - v_price
    where p.id = v_user_id and p.coins >= v_price
    returning p.coins into v_new_balance;
  if not found then raise exception 'Nicht genügend Coins.'; end if;

  insert into public.coin_ledger(user_id, coins_delta, kind, detail)
    values (v_user_id, -v_price, 'pack_purchase', jsonb_build_object('tier', p_tier));

  for v_index in 1..5 loop
    select c.id into v_catalog_id from public.cards as c order by random() limit 1;
    if v_catalog_id is null then raise exception 'Der Kartenkatalog ist leer.'; end if;
    insert into public.user_cards(user_id, card_id)
      values (v_user_id, v_catalog_id) returning id into v_instance_id;
    v_instances := array_append(v_instances, v_instance_id);
  end loop;

  return query
    select uc.id, c.id, c.name, c.short_name, c.card_year, c.rating, c.rarity, c.card_type, c.image_url, uc.level, c.tier
    from public.user_cards as uc
    join public.cards as c on c.id = uc.card_id
    where uc.id = any(v_instances)
    order by array_position(v_instances, uc.id);
end;
$$;

create or replace function public.sell_user_card(p_instance_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_card record;
  v_value bigint;
  v_balance bigint;
begin
  if v_user_id is null then raise exception 'Bitte zuerst anmelden.'; end if;
  select uc.id, uc.level, c.rating, c.tier, c.short_name
    into v_card
    from public.user_cards as uc
    join public.cards as c on c.id = uc.card_id
    where uc.id = p_instance_id and uc.user_id = v_user_id
    for update of uc;
  if not found then raise exception 'Karte nicht im eigenen Bestand gefunden.'; end if;

  v_value := (case v_card.tier when 'bronze' then 100 when 'gold' then 250 when 'platinum' then 500 else 1000 end)
    + (v_card.rating * 5)
    + ((v_card.level - 1) * 75);

  delete from public.user_cards where id = p_instance_id and user_id = v_user_id;
  update public.profiles as p set coins = p.coins + v_value where p.id = v_user_id returning p.coins into v_balance;
  insert into public.coin_ledger(user_id, coins_delta, kind, detail)
    values (v_user_id, v_value, 'card_sale', jsonb_build_object('card', v_card.short_name, 'level', v_card.level, 'tier', v_card.tier));

  return jsonb_build_object('coins_awarded', v_value, 'balance', v_balance, 'card', v_card.short_name, 'level', v_card.level, 'tier', v_card.tier);
end;
$$;

create or replace function public.upgrade_user_card(p_instance_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_level smallint;
  v_cost bigint;
  v_balance bigint;
  v_new_level smallint;
begin
  if v_user_id is null then raise exception 'Bitte zuerst anmelden.'; end if;
  select level into v_level
    from public.user_cards
    where id = p_instance_id and user_id = v_user_id
    for update;
  if not found then raise exception 'Karte nicht im eigenen Bestand gefunden.'; end if;
  if v_level >= 10 then raise exception 'Diese Karte hat bereits Level 10.'; end if;

  v_cost := v_level * 300;
  update public.profiles as p set coins = p.coins - v_cost
    where p.id = v_user_id and p.coins >= v_cost
    returning p.coins into v_balance;
  if not found then raise exception 'Nicht genügend Coins für das nächste Level.'; end if;

  update public.user_cards set level = level + 1
    where id = p_instance_id and user_id = v_user_id
    returning level into v_new_level;
  insert into public.coin_ledger(user_id, coins_delta, kind, detail)
    values (v_user_id, -v_cost, 'card_upgrade', jsonb_build_object('card_instance_id', p_instance_id, 'new_level', v_new_level));

  return jsonb_build_object('level', v_new_level, 'coins_spent', v_cost, 'balance', v_balance);
end;
$$;

create or replace function public.convert_f1_points(p_points bigint)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_balance_points bigint;
  v_today_coins bigint;
  v_coin_limit constant bigint := 500;
  v_coins bigint;
  v_points_spent bigint;
  v_new_coins bigint;
begin
  if v_user_id is null then raise exception 'Bitte zuerst anmelden.'; end if;
  if p_points is null or p_points < 10 then raise exception 'Mindestens 10 F1-Punkte umtauschen.'; end if;

  select f1_points into v_balance_points from public.profiles where id = v_user_id for update;
  select coalesce(sum(coins_delta), 0) into v_today_coins
    from public.coin_ledger
    where user_id = v_user_id
      and kind = 'point_conversion'
      and created_at >= (date_trunc('day', now() at time zone 'UTC') at time zone 'UTC');

  v_coins := least(p_points / 10, v_balance_points / 10, greatest(0, v_coin_limit - v_today_coins));
  if v_coins < 1 then raise exception 'Tageslimit erreicht oder nicht genügend F1-Punkte.'; end if;
  v_points_spent := v_coins * 10;

  update public.profiles as p
    set f1_points = p.f1_points - v_points_spent,
        coins = p.coins + v_coins
    where p.id = v_user_id
    returning p.coins into v_new_coins;
  insert into public.coin_ledger(user_id, coins_delta, kind, detail)
    values (v_user_id, v_coins, 'point_conversion', jsonb_build_object('points_spent', v_points_spent));

  return jsonb_build_object('points_spent', v_points_spent, 'coins_awarded', v_coins, 'balance', v_new_coins, 'daily_limit', v_coin_limit);
end;
$$;

create or replace function public.admin_award_race_points(p_email text, p_position smallint, p_event_name text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_admin_id uuid := auth.uid();
  v_user_id uuid;
  v_base_points integer;
  v_awarded bigint;
  v_total bigint;
begin
  if v_admin_id is null or not public.is_admin() then raise exception 'Admin-Berechtigung erforderlich.'; end if;
  if p_position is null or p_position not between 1 and 10 then raise exception 'Platz muss zwischen 1 und 10 liegen.'; end if;
  if p_event_name is null or length(trim(p_event_name)) = 0 then raise exception 'Rennen oder Event angeben.'; end if;
  v_base_points := case p_position when 1 then 25 when 2 then 18 when 3 then 15 when 4 then 12 when 5 then 10 when 6 then 8 when 7 then 6 when 8 then 4 when 9 then 2 when 10 then 1 end;
  v_awarded := v_base_points * 100;

  select id into v_user_id from public.profiles where lower(email) = lower(trim(p_email));
  if v_user_id is null then raise exception 'Kein Konto mit dieser E-Mail gefunden.'; end if;
  update public.profiles as p set f1_points = p.f1_points + v_awarded where p.id = v_user_id returning p.f1_points into v_total;
  insert into public.point_ledger(user_id, points_delta, event_name, finish_position, admin_id)
    values (v_user_id, v_awarded, trim(p_event_name), p_position, v_admin_id);

  return jsonb_build_object('email', lower(trim(p_email)), 'position', p_position, 'f1_points_awarded', v_awarded, 'new_balance', v_total);
end;
$$;

revoke all on function public.purchase_pack(text) from public, anon;
revoke all on function public.sell_user_card(uuid) from public, anon;
revoke all on function public.upgrade_user_card(uuid) from public, anon;
revoke all on function public.convert_f1_points(bigint) from public, anon;
revoke all on function public.admin_award_race_points(text, smallint, text) from public, anon;
grant execute on function public.purchase_pack(text) to authenticated;
grant execute on function public.sell_user_card(uuid) to authenticated;
grant execute on function public.upgrade_user_card(uuid) to authenticated;
grant execute on function public.convert_f1_points(bigint) to authenticated;
grant execute on function public.admin_award_race_points(text, smallint, text) to authenticated;