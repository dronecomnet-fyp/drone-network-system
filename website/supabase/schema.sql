-- DroneComNet product site schema (M7c).
--
-- Run this once in your Supabase project (SQL editor), or apply it with the
-- Supabase MCP / CLI. It creates the products, units, and quotes tables,
-- locks them down with row-level security so the PUBLIC anon key can only:
--   - read products and units
--   - insert a quote (never read others' quotes)
-- and seeds the real prototype catalogue.
--
-- The anon key is safe to embed in the website and the ground control app;
-- RLS is the actual access control. NEVER expose the service_role key.

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------

create table if not exists public.products (
  id           uuid primary key default gen_random_uuid(),
  model_no     text unique not null,
  name         text not null,
  description  text,
  specs        jsonb not null default '{}'::jsonb,
  model_3d_url text,
  price_usd    numeric,
  created_at   timestamptz not null default now()
);

create table if not exists public.units (
  unit_id         text primary key,
  product_id      uuid not null references public.products(id) on delete cascade,
  status          text not null default 'in_stock',
  manufactured_at date,
  created_at      timestamptz not null default now()
);

create index if not exists units_product_idx on public.units(product_id);

create table if not exists public.quotes (
  id         uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  contact    jsonb not null,
  items      jsonb not null,
  status     text not null default 'new'
);

-- ---------------------------------------------------------------------------
-- Row-level security
-- ---------------------------------------------------------------------------

alter table public.products enable row level security;
alter table public.units    enable row level security;
alter table public.quotes   enable row level security;

-- Public read on the catalogue.
drop policy if exists "anon read products" on public.products;
create policy "anon read products" on public.products
  for select using (true);

drop policy if exists "anon read units" on public.units;
create policy "anon read units" on public.units
  for select using (true);

-- Public may submit a quote, but may not read, update, or delete any quote.
drop policy if exists "anon insert quotes" on public.quotes;
create policy "anon insert quotes" on public.quotes
  for insert with check (true);

-- (No select/update/delete policy on quotes => anon cannot read them. Only
--  the service_role key, used from a trusted backend, can.)

-- ---------------------------------------------------------------------------
-- Seed: the real prototype catalogue
-- ---------------------------------------------------------------------------

insert into public.products (model_no, name, description, specs, price_usd)
values
  (
    'DCM-STD',
    'DroneComNet Module (standard)',
    'The core disaster-mesh comm module: Raspberry Pi with a 5 GHz user access point and a 2.4 GHz ad-hoc mesh radio. Attaches to any drone.',
    jsonb_build_object(
      'wifi_tech', '802.11a/n dual radio',
      'ap_range_m', 300,
      'mesh_range_m', 900,
      'battery_wh', 40,
      'lora', true,
      'gps', true,
      'weight_g', 220
    ),
    480
  ),
  (
    'DCM-AUX',
    'DroneComNet Aux Module',
    'Sensor and fallback module: INA3221 battery monitoring, GPS, and a LoRa fallback beacon that keeps the drone locatable if the Pi fails.',
    jsonb_build_object(
      'wifi_tech', 'none (aux only)',
      'ap_range_m', 0,
      'mesh_range_m', 0,
      'battery_wh', 0,
      'lora', true,
      'lora_range_m', 3000,
      'gps', true,
      'weight_g', 60
    ),
    140
  ),
  (
    'AS5',
    'AeroSync 5 System Drone',
    'A comm module plus a CC3D flight controller the ground control centre commands over MAVLink: the one drone in the fleet that can be flown and repositioned from the ground.',
    jsonb_build_object(
      'wifi_tech', '802.11a/n dual radio',
      'ap_range_m', 300,
      'mesh_range_m', 900,
      'battery_wh', 90,
      'lora', false,
      'gps', true,
      'weight_g', 750,
      'flight_controller', 'CC3D Open Revolution Mini',
      'motors_kv', 2200
    ),
    1650
  )
on conflict (model_no) do nothing;

-- Units matching the physical hardware (letters A/B/S mirror the mesh nodes).
insert into public.units (unit_id, product_id, status, manufactured_at)
select v.unit_id, p.id, v.status, v.mfg::date
from (values
  ('DCM-A-0042', 'DCM-STD', 'in_stock', '2026-05-01'),
  ('DCM-B-0043', 'DCM-STD', 'in_stock', '2026-05-01'),
  ('DCM-AUX-0011', 'DCM-AUX', 'in_stock', '2026-05-02'),
  ('DCM-AUX-0012', 'DCM-AUX', 'spare',    '2026-05-02'),
  ('DRN-S-0007',  'AS5',     'in_stock', '2026-05-10')
) as v(unit_id, model_no, status, mfg)
join public.products p on p.model_no = v.model_no
on conflict (unit_id) do nothing;
