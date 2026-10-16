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
  progress_xp bigint not null default 0 check (progress_xp >= 0),
  level bigint generated always as ((progress_xp / 25000) + 1) stored,
  welcome_bonus_claimed_at timestamptz default now(),
  created_at timestamptz not null default now()
);

alter table public.profiles
  add column if not exists welcome_bonus_claimed_at timestamptz default now();
alter table public.profiles
  add column if not exists progress_xp bigint not null default 0 check (progress_xp >= 0);
alter table public.profiles
  add column if not exists level bigint generated always as ((progress_xp / 25000) + 1) stored;

create table if not exists public.cards (
  id text primary key,
  name text not null,
  short_name text not null,
  card_year smallint not null,
  rating smallint not null check (rating between 1 and 100),
  rarity text not null check (rarity in ('rare', 'epic', 'icon', 'legend')),
  card_type text not null,
  image_url text not null,
  legend_pack_only boolean not null default false,
  copies_remaining integer check (copies_remaining is null or copies_remaining >= 0),
  tier text generated always as (
    case
      when rating >= 96 then 'legend'
      when rating >= 90 then 'platinum'
      when rating >= 85 then 'gold'
      else 'bronze'
    end
  ) stored
);

alter table public.cards
  add column if not exists legend_pack_only boolean not null default false;
alter table public.cards
  add column if not exists copies_remaining integer check (copies_remaining is null or copies_remaining >= 0);

create table if not exists public.pack_catalog (
  tier text primary key check (tier in ('bronze', 'platinum', 'gold', 'legend')),
  name text not null,
  price bigint not null check (price > 0),
  enabled boolean not null default true
);

alter table public.pack_catalog drop constraint if exists pack_catalog_tier_check;
alter table public.pack_catalog
  add constraint pack_catalog_tier_check
  check (tier in ('bronze', 'platinum', 'gold', 'gold_double', 'legend'));

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
  kind text not null check (kind in ('pack_purchase', 'card_sale', 'point_conversion', 'card_upgrade', 'welcome_bonus')),
  detail jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

alter table public.coin_ledger drop constraint if exists coin_ledger_kind_check;
alter table public.coin_ledger
  add constraint coin_ledger_kind_check
  check (kind in ('pack_purchase', 'card_sale', 'point_conversion', 'card_upgrade', 'welcome_bonus'));

create index if not exists coin_ledger_owner_day_idx on public.coin_ledger(user_id, kind, created_at desc);

create table if not exists public.point_ledger (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  points_delta bigint not null,
  event_name text not null,
  finish_position smallint check (finish_position between 1 and 10),
  admin_id uuid not null references auth.users(id),
  created_at timestamptz not null default now()
);

alter table public.point_ledger alter column finish_position drop not null;
do $$
begin
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'point_ledger'
      and column_name = 'notification_seen_at'
  ) then
    alter table public.point_ledger add column notification_seen_at timestamptz default now();
    alter table public.point_ledger alter column notification_seen_at drop default;
  end if;
end;
$$;

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
    where user_id = auth.uid()
      and role = 'admin'
      and lower(auth.jwt()->>'email') = lower('s.barbosa.galaxy@gmail.com')
  );
$$;

create or replace function public.claim_welcome_bonus()
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_balance bigint;
  v_bonus constant bigint := 3000;
begin
  if v_user_id is null then raise exception 'Bitte zuerst anmelden.'; end if;

  update public.profiles
    set coins = coins + v_bonus,
        progress_xp = progress_xp + v_bonus,
        welcome_bonus_claimed_at = now()
    where id = v_user_id and welcome_bonus_claimed_at is null
    returning coins into v_balance;
  if not found then raise exception 'Das Willkommensgeschenk wurde bereits beansprucht.'; end if;

  insert into public.coin_ledger(user_id, coins_delta, kind, detail)
    values (v_user_id, v_bonus, 'welcome_bonus', jsonb_build_object('source', 'new_account'));

  return jsonb_build_object('coins_awarded', v_bonus, 'balance', v_balance);
end;
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
  insert into public.profiles (id, email, display_name, welcome_bonus_claimed_at)
  values (
    new.id,
    lower(trim(new.email)),
    coalesce(nullif(trim(new.raw_user_meta_data->>'full_name'), ''), nullif(trim(new.raw_user_meta_data->>'name'), ''), split_part(lower(trim(new.email)), '@', 1), 'F1 Driver'),
    null
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
  ('FANGIO', 'Juan Manuel Fangio', 'FANGIO', 1954, 98, 'legend', 'DRIVER', 'https://thumb.wikimedia.org/wikipedia/commons/thumb/6/63/Juan_Manuel_Fangio_%28circa_1952%29.jpg/960px-Juan_Manuel_Fangio_%28circa_1952%29.jpg'),
  ('SENNA', 'Ayrton Senna · Weltmeister 1991', 'SENNA 1991', 1991, 99, 'legend', 'DRIVER', 'https://upload.wikimedia.org/wikipedia/commons/b/be/Ayrton_Senna_Montreal_1988.jpg'),
  ('SCHUMACHER', 'Michael Schumacher', 'SCHUMACHER', 2001, 91, 'epic', 'DRIVER', 'https://thumb.wikimedia.org/wikipedia/commons/thumb/d/d3/Michael_Schumacher_Ferrari_2004.jpg/960px-Michael_Schumacher_Ferrari_2004.jpg'),
  ('HAMILTON', 'Lewis Hamilton', 'HAMILTON', 2020, 88, 'rare', 'RARE', 'https://thumb.wikimedia.org/wikipedia/commons/thumb/c/c0/2022_British_Grand_Prix_%2852382575808%29.jpg/960px-2022_British_Grand_Prix_%2852382575808%29.jpg'),
  ('VERSTAPPEN', 'Max Verstappen', 'VERSTAPPEN', 2023, 85, 'rare', 'RARE', 'https://thumb.wikimedia.org/wikipedia/commons/thumb/a/a2/2015_Malaysian_GP_opening_lap.jpg/960px-2015_Malaysian_GP_opening_lap.jpg'),
  ('PROST', 'Alain Prost', 'PROST', 1988, 90, 'epic', 'DRIVER', 'https://thumb.wikimedia.org/wikipedia/commons/thumb/f/f2/Alain_Prost_Integralhelm_1985.jpg/960px-Alain_Prost_Integralhelm_1985.jpg'),
  ('RAIKKONEN', 'Kimi Räikkönen', 'RÄIKKÖNEN', 2007, 82, 'rare', 'RARE', 'https://thumb.wikimedia.org/wikipedia/commons/thumb/1/1c/2018_Chinese_Grand_Prix_FP3_Fernando_Alonso_%2840970600574%29.jpg/960px-2018_Chinese_Grand_Prix_FP3_Fernando_Alonso_%2840970600574%29.jpg'),
  ('ROSBERG', 'Nico Rosberg', 'ROSBERG', 2013, 83, 'rare', 'RARE', 'https://thumb.wikimedia.org/wikipedia/commons/thumb/2/25/Drivers_at_1969_Dutch_Grand_Prix.jpg/960px-Drivers_at_1969_Dutch_Grand_Prix.jpg'),
  ('MANSELL', 'Nigel Mansell', 'MANSELL', 1992, 87, 'rare', 'DRIVER', 'https://thumb.wikimedia.org/wikipedia/commons/thumb/c/ce/Car_Show_Nigel_Mansell_with_His_1992_Williams-Renault_FW14B_Formula_1_Car.jpg/960px-Car_Show_Nigel_Mansell_with_His_1992_Williams-Renault_FW14B_Formula_1_Car.jpg'),
  ('F2004', 'Ferrari F2004', 'F2004', 2004, 94, 'icon', 'CAR', 'https://thumb.wikimedia.org/wikipedia/commons/thumb/d/d3/Michael_Schumacher_Ferrari_2004.jpg/960px-Michael_Schumacher_Ferrari_2004.jpg'),
  ('MP4-4', 'McLaren MP4/4', 'MP4/4', 1988, 96, 'legend', 'CAR', 'https://thumb.wikimedia.org/wikipedia/commons/thumb/1/1f/1988_McLaren-Honda_MP4_4_Goodwood%2C_2009_%2801%29.jpg/960px-1988_McLaren-Honda_MP4_4_Goodwood%2C_2009_%2801%29.jpg'),
  ('RB19', 'Red Bull RB19', 'RB19', 2023, 92, 'icon', 'CAR', 'https://thumb.wikimedia.org/wikipedia/commons/thumb/c/c6/2018_Chinese_Grand_Prix_FP3_Charles_Leclerc_%2839897914770%29.jpg/960px-2018_Chinese_Grand_Prix_FP3_Charles_Leclerc_%2839897914770%29.jpg')
on conflict (id) do update set
  name = excluded.name,
  short_name = excluded.short_name,
  card_year = excluded.card_year,
  rating = excluded.rating,
  rarity = excluded.rarity,
  card_type = excluded.card_type,
  image_url = excluded.image_url;

update public.cards
set legend_pack_only = true,
    copies_remaining = greatest(0, 4 - (select count(*) from public.user_cards where card_id = 'SENNA'))
where id = 'SENNA';

insert into public.cards (id, name, short_name, card_year, rating, rarity, card_type, image_url) values
  ('FANGIO-51', 'Juan Manuel Fangio · Weltmeister 1951', 'FANGIO 1951', 1951, 97, 'legend', 'DRIVER', 'https://thumb.wikimedia.org/wikipedia/commons/thumb/6/63/Juan_Manuel_Fangio_%28circa_1952%29.jpg/960px-Juan_Manuel_Fangio_%28circa_1952%29.jpg'),
  ('SCHUMACHER-04', 'Michael Schumacher · Weltmeister 2004', 'SCHUMI 2004', 2004, 99, 'legend', 'DRIVER', 'https://thumb.wikimedia.org/wikipedia/commons/thumb/d/d3/Michael_Schumacher_Ferrari_2004.jpg/960px-Michael_Schumacher_Ferrari_2004.jpg'),
  ('PROST-85', 'Alain Prost · Weltmeister 1985', 'PROST 1985', 1985, 95, 'icon', 'DRIVER', 'https://thumb.wikimedia.org/wikipedia/commons/thumb/f/f2/Alain_Prost_Integralhelm_1985.jpg/960px-Alain_Prost_Integralhelm_1985.jpg'),
  ('VETTEL-13', 'Sebastian Vettel · Weltmeister 2013', 'VETTEL 2013', 2013, 96, 'legend', 'DRIVER', 'https://thumb.wikimedia.org/wikipedia/commons/thumb/b/b8/Formula_One_Grand_Prix_Singapore_2013_-_Sebastian_Vettel_in_Red_Bull_Renault_1.jpg/960px-Formula_One_Grand_Prix_Singapore_2013_-_Sebastian_Vettel_in_Red_Bull_Renault_1.jpg'),
  ('HAMILTON-20', 'Lewis Hamilton · Weltmeister 2020', 'HAM 2020', 2020, 97, 'legend', 'DRIVER', 'https://thumb.wikimedia.org/wikipedia/commons/thumb/6/64/Lewis_Hamilton-Mercedes_W11_%283%29.jpg/960px-Lewis_Hamilton-Mercedes_W11_%283%29.jpg'),
  ('CAR-MP4-4', 'McLaren MP4/4 · Senna / Prost', 'MP4/4', 1988, 97, 'legend', 'CAR', 'https://thumb.wikimedia.org/wikipedia/commons/thumb/1/1f/1988_McLaren-Honda_MP4_4_Goodwood%2C_2009_%2801%29.jpg/960px-1988_McLaren-Honda_MP4_4_Goodwood%2C_2009_%2801%29.jpg'),
  ('CAR-FW14B', 'Williams FW14B · Nigel Mansell', 'FW14B', 1992, 94, 'icon', 'CAR', 'https://thumb.wikimedia.org/wikipedia/commons/thumb/c/ce/Car_Show_Nigel_Mansell_with_His_1992_Williams-Renault_FW14B_Formula_1_Car.jpg/960px-Car_Show_Nigel_Mansell_with_His_1992_Williams-Renault_FW14B_Formula_1_Car.jpg'),
  ('TRACK-MONACO', 'Circuit de Monaco', 'MONACO', 2024, 72, 'rare', 'TRACK', 'https://thumb.wikimedia.org/wikipedia/commons/thumb/4/45/Circuit_de_Monaco%2C_April_1%2C_2018_SkySat.jpg/960px-Circuit_de_Monaco%2C_April_1%2C_2018_SkySat.jpg'),
  ('TRACK-SPA', 'Circuit de Spa-Francorchamps', 'SPA', 2024, 76, 'rare', 'TRACK', 'https://thumb.wikimedia.org/wikipedia/commons/thumb/c/c0/Circuit_de_Spa-Francorchamps%2C_April_22%2C_2018_SkySat.jpg/960px-Circuit_de_Spa-Francorchamps%2C_April_22%2C_2018_SkySat.jpg'),
  ('TRACK-MONZA', 'Autodromo Nazionale Monza', 'MONZA', 2024, 78, 'rare', 'TRACK', 'https://thumb.wikimedia.org/wikipedia/commons/thumb/d/da/Autodromo_Nazionale_Monza%2C_April_22%2C_2018_SkySat.jpg/960px-Autodromo_Nazionale_Monza%2C_April_22%2C_2018_SkySat.jpg')
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

insert into public.cards (id, name, short_name, card_year, rating, rarity, card_type, image_url) values
  ('CAR26-MCLAREN', 'McLaren 2026 F1 Livery', 'MCLAREN F1', 2026, 84, 'rare', 'CAR', 'https://media.formula1.com/image/upload/c_lfill,h_224/q_auto/d_common:f1:2026:fallback:car:2026fallbackcarright.webp/v1740000001/common/f1/2026/mclaren/2026mclarencarright.webp'),
  ('CAR26-MERCEDES', 'Mercedes 2026 F1 Livery', 'MERCEDES F1', 2026, 84, 'rare', 'CAR', 'https://media.formula1.com/image/upload/c_lfill,h_224/q_auto/d_common:f1:2026:fallback:car:2026fallbackcarright.webp/v1740000001/common/f1/2026/mercedes/2026mercedescarright.webp'),
  ('CAR26-REDBULL', 'Red Bull Racing 2026 F1 Livery', 'RED BULL F1', 2026, 84, 'rare', 'CAR', 'https://media.formula1.com/image/upload/c_lfill,h_224/q_auto/d_common:f1:2026:fallback:car:2026fallbackcarright.webp/v1740000001/common/f1/2026/redbullracing/2026redbullracingcarright.webp'),
  ('CAR26-RACINGBULLS', 'Racing Bulls 2026 F1 Livery', 'RACING BULLS', 2026, 79, 'rare', 'CAR', 'https://media.formula1.com/image/upload/c_lfill,h_224/q_auto/d_common:f1:2026:fallback:car:2026fallbackcarright.webp/v1740000001/common/f1/2026/racingbulls/2026racingbullscarright.webp'),
  ('CAR26-FERRARI', 'Ferrari 2026 F1 Livery', 'FERRARI F1', 2026, 84, 'rare', 'CAR', 'https://media.formula1.com/image/upload/c_lfill,h_224/q_auto/d_common:f1:2026:fallback:car:2026fallbackcarright.webp/v1740000001/common/f1/2026/ferrari/2026ferraricarright.webp'),
  ('CAR26-WILLIAMS', 'Williams 2026 F1 Livery', 'WILLIAMS F1', 2026, 82, 'rare', 'CAR', 'https://media.formula1.com/image/upload/c_lfill,h_224/q_auto/d_common:f1:2026:fallback:car:2026fallbackcarright.webp/v1740000001/common/f1/2026/williams/2026williamscarright.webp'),
  ('CAR26-ASTONMARTIN', 'Aston Martin 2026 F1 Livery', 'ASTON MARTIN F1', 2026, 81, 'rare', 'CAR', 'https://media.formula1.com/image/upload/c_lfill,h_224/q_auto/d_common:f1:2026:fallback:car:2026fallbackcarright.webp/v1740000001/common/f1/2026/astonmartin/2026astonmartincarright.webp'),
  ('CAR26-HAAS', 'Haas 2026 F1 Livery', 'HAAS F1', 2026, 80, 'rare', 'CAR', 'https://media.formula1.com/image/upload/c_lfill,h_224/q_auto/d_common:f1:2026:fallback:car:2026fallbackcarright.webp/v1740000001/common/f1/2026/haasf1team/2026haasf1teamcarright.webp'),
  ('CAR26-AUDI', 'Audi 2026 F1 Livery', 'AUDI F1', 2026, 78, 'rare', 'CAR', 'https://media.formula1.com/image/upload/c_lfill,h_224/q_auto/d_common:f1:2026:fallback:car:2026fallbackcarright.webp/v1740000001/common/f1/2026/audi/2026audicarright.webp'),
  ('CAR26-ALPINE', 'Alpine 2026 F1 Livery', 'ALPINE F1', 2026, 80, 'rare', 'CAR', 'https://media.formula1.com/image/upload/c_lfill,h_224/q_auto/d_common:f1:2026:fallback:car:2026fallbackcarright.webp/v1740000001/common/f1/2026/alpine/2026alpinecarright.webp'),
  ('CAR26-CADILLAC', 'Cadillac 2026 F1 Livery', 'CADILLAC F1', 2026, 76, 'rare', 'CAR', 'https://media.formula1.com/image/upload/c_lfill,h_224/q_auto/d_common:f1:2026:fallback:car:2026fallbackcarright.webp/v1740000001/common/f1/2026/cadillac/2026cadillaccarright.webp')
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
  ('gold_double', 'GOLD DOUBLE PACK', 18000),
  ('legend', 'LEGEND PACK', 17000)
on conflict (tier) do update set name = excluded.name, price = excluded.price, enabled = true;

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
  v_card_count integer;
  v_roll double precision;
  v_target_tier text;
  v_candidate_id text;
  v_copies_remaining integer;
begin
  if v_user_id is null then raise exception 'Bitte zuerst anmelden.'; end if;
  select price into v_price from public.pack_catalog where pack_catalog.tier = p_tier and enabled;
  if v_price is null then raise exception 'Dieses Pack ist nicht verfügbar.'; end if;
  v_card_count := case when p_tier = 'gold_double' then 10 else 5 end;

  update public.profiles as p
    set coins = p.coins - v_price,
        progress_xp = p.progress_xp + v_price
    where p.id = v_user_id and p.coins >= v_price
    returning p.coins into v_new_balance;
  if not found then raise exception 'Nicht genügend Coins.'; end if;

  insert into public.coin_ledger(user_id, coins_delta, kind, detail)
    values (v_user_id, -v_price, 'pack_purchase', jsonb_build_object('tier', p_tier));

  for v_index in 1..v_card_count loop
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
        where c.tier = v_target_tier
          and (not c.legend_pack_only or p_tier = 'legend')
          and (c.copies_remaining is null or c.copies_remaining > 0)
        order by random()
        limit 1;
      if not found then raise exception 'Für diese Pack-Stufe sind keine Karten verfügbar.'; end if;

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
  update public.profiles as p
    set coins = p.coins + v_value,
        progress_xp = p.progress_xp + v_value
    where p.id = v_user_id returning p.coins into v_balance;
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
  v_coins bigint;
  v_points_spent bigint;
  v_new_coins bigint;
begin
  if v_user_id is null then raise exception 'Bitte zuerst anmelden.'; end if;
  if p_points is null or p_points < 10 then raise exception 'Mindestens 10 F1-Punkte umtauschen.'; end if;

  select f1_points into v_balance_points from public.profiles where id = v_user_id for update;
  v_coins := least(p_points / 10, v_balance_points / 10) * 90;
  if v_coins < 90 then raise exception 'Nicht genügend F1-Punkte zum Umtauschen.'; end if;
  v_points_spent := (v_coins / 90) * 10;

  update public.profiles as p
    set f1_points = p.f1_points - v_points_spent,
        coins = p.coins + v_coins,
        progress_xp = p.progress_xp + v_coins
    where p.id = v_user_id
    returning p.coins into v_new_coins;
  insert into public.coin_ledger(user_id, coins_delta, kind, detail)
    values (v_user_id, v_coins, 'point_conversion', jsonb_build_object('points_spent', v_points_spent));

  return jsonb_build_object('points_spent', v_points_spent, 'coins_awarded', v_coins, 'balance', v_new_coins);
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
  v_ledger_id uuid;
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
  insert into public.point_ledger(user_id, points_delta, event_name, finish_position, admin_id)
    values (v_user_id, v_awarded, trim(p_event_name), p_position, v_admin_id)
    on conflict do nothing
    returning id into v_ledger_id;
  if v_ledger_id is null then
    select f1_points into v_total from public.profiles where id = v_user_id;
    return jsonb_build_object('email', lower(trim(p_email)), 'position', p_position, 'f1_points_awarded', 0, 'new_balance', v_total, 'already_awarded', true);
  end if;
  update public.profiles as p set f1_points = p.f1_points + v_awarded where p.id = v_user_id returning p.f1_points into v_total;

  return jsonb_build_object('email', lower(trim(p_email)), 'position', p_position, 'f1_points_awarded', v_awarded, 'new_balance', v_total, 'already_awarded', false);
end;
$$;

create or replace function public.admin_award_custom_points(p_email text, p_points bigint, p_event_name text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_admin_id uuid := auth.uid();
  v_user_id uuid;
  v_ledger_id uuid;
  v_total bigint;
begin
  if v_admin_id is null or not public.is_admin() then raise exception 'Admin-Berechtigung erforderlich.'; end if;
  if p_points is null or p_points < 1 then raise exception 'Mindestens einen F1-Punkt eingeben.'; end if;
  if p_points > 100000 then raise exception 'Pro Vergabe sind maximal 100.000 F1-Punkte erlaubt.'; end if;
  if p_event_name is null or length(trim(p_event_name)) = 0 then raise exception 'Rennen oder Event angeben.'; end if;

  select id into v_user_id from public.profiles where lower(email) = lower(trim(p_email));
  if v_user_id is null then raise exception 'Kein Konto mit dieser E-Mail gefunden.'; end if;
  insert into public.point_ledger(user_id, points_delta, event_name, finish_position, admin_id)
    values (v_user_id, p_points, trim(p_event_name), null, v_admin_id)
    on conflict do nothing
    returning id into v_ledger_id;
  if v_ledger_id is null then
    select f1_points into v_total from public.profiles where id = v_user_id;
    return jsonb_build_object('email', lower(trim(p_email)), 'points_awarded', 0, 'new_balance', v_total, 'already_awarded', true);
  end if;

  update public.profiles as p
    set f1_points = p.f1_points + p_points
    where p.id = v_user_id
    returning p.f1_points into v_total;

  return jsonb_build_object('email', lower(trim(p_email)), 'points_awarded', p_points, 'new_balance', v_total, 'already_awarded', false);
end;
$$;

create or replace function public.claim_point_award_notifications()
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_notifications jsonb;
begin
  if v_user_id is null then raise exception 'Bitte zuerst anmelden.'; end if;

  with pending as (
    select id
    from public.point_ledger
    where user_id = v_user_id and notification_seen_at is null
    order by created_at
    for update skip locked
  ), claimed as (
    update public.point_ledger as ledger
      set notification_seen_at = now()
      from pending
      where ledger.id = pending.id
      returning ledger.points_delta, ledger.event_name, ledger.created_at
  )
  select coalesce(
    jsonb_agg(jsonb_build_object('points_delta', points_delta, 'event_name', event_name) order by created_at),
    '[]'::jsonb
  )
  into v_notifications
  from claimed;

  return v_notifications;

end;
$$;

revoke all on function public.purchase_pack(text) from public, anon;
revoke all on function public.admin_create_card(text, text, text, smallint, smallint, text, text, text, boolean, integer) from public, anon;
revoke all on function public.admin_grant_card(text, text) from public, anon;
revoke all on function public.sell_user_card(uuid) from public, anon;
revoke all on function public.upgrade_user_card(uuid) from public, anon;
revoke all on function public.convert_f1_points(bigint) from public, anon;
revoke all on function public.admin_award_race_points(text, smallint, text) from public, anon;
revoke all on function public.admin_award_custom_points(text, bigint, text) from public, anon;
revoke all on function public.claim_point_award_notifications() from public, anon;
revoke all on function public.claim_welcome_bonus() from public, anon;
grant execute on function public.purchase_pack(text) to authenticated;
grant execute on function public.admin_create_card(text, text, text, smallint, smallint, text, text, text, boolean, integer) to authenticated;
grant execute on function public.admin_grant_card(text, text) to authenticated;
grant execute on function public.sell_user_card(uuid) to authenticated;
grant execute on function public.upgrade_user_card(uuid) to authenticated;
grant execute on function public.convert_f1_points(bigint) to authenticated;
grant execute on function public.admin_award_race_points(text, smallint, text) to authenticated;
grant execute on function public.admin_award_custom_points(text, bigint, text) to authenticated;
grant execute on function public.claim_point_award_notifications() to authenticated;
grant execute on function public.claim_welcome_bonus() to authenticated;

notify pgrst, 'reload schema';