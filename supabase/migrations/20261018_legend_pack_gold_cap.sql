update public.cards
set tier = 'gold'
where id = 'SENNA';

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
          v_target_tier := 'gold';
      end case;

      loop
        v_catalog_id := null;
        select c.id, c.copies_remaining
          into v_candidate_id, v_copies_remaining
          from public.cards as c
          where c.tier = v_target_tier
            and c.id <> 'SENNA'
            and c.is_published
            and (not c.legend_pack_only or p_tier = 'legend')
            and (c.copies_remaining is null or c.copies_remaining > 0)
            and not (c.id = any(v_drawn_card_ids))
          order by random()
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

notify pgrst, 'reload schema';