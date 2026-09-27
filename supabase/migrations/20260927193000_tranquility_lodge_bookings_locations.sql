create extension if not exists btree_gist;

create table if not exists public.facilities (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  facility_type text not null default 'EVENT',
  default_price numeric(12,2) not null check (default_price >= 0),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.bookings (
  id uuid primary key default gen_random_uuid(),
  guest_id uuid not null references public.guests(id),
  room_id uuid references public.rooms(id),
  facility_id uuid references public.facilities(id),
  check_in_date date not null,
  check_out_date date not null,
  start_at timestamptz,
  end_at timestamptz,
  nights integer not null default 1 check (nights > 0),
  charged_rate numeric(12,2) not null check (charged_rate >= 0),
  total_amount numeric(12,2) not null check (total_amount >= 0),
  notes text,
  status text not null default 'RESERVED' check (status in ('RESERVED','CHECKED_IN','CHECKED_OUT','CANCELLED')),
  created_by uuid not null references public.profiles(id),
  checked_in_by uuid references public.profiles(id),
  checked_out_by uuid references public.profiles(id),
  checked_in_at timestamptz,
  checked_out_at timestamptz,
  created_at timestamptz not null default now(),
  check (room_id is not null or facility_id is not null),
  check (not (room_id is not null and facility_id is not null)),
  check (check_out_date > check_in_date),
  check ((facility_id is null) or (start_at is not null and end_at is not null and end_at > start_at))
);

create index if not exists bookings_dates_idx on public.bookings(check_in_date, check_out_date);
create index if not exists bookings_room_idx on public.bookings(room_id) where room_id is not null;
create index if not exists bookings_facility_idx on public.bookings(facility_id) where facility_id is not null;

alter table public.bookings add constraint bookings_room_no_overlap exclude using gist
  (room_id with =, daterange(check_in_date, check_out_date, '[)') with &&)
  where (room_id is not null and status in ('RESERVED','CHECKED_IN'));

alter table public.bookings add constraint bookings_facility_no_overlap exclude using gist
  (facility_id with =, tstzrange(start_at, end_at, '[)') with &&)
  where (facility_id is not null and status in ('RESERVED','CHECKED_IN'));

create table if not exists public.booking_payments (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null references public.bookings(id) on delete restrict,
  amount numeric(12,2) not null check (amount > 0),
  payment_method public.payment_method,
  received_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now()
);

create table if not exists public.inventory_locations (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.product_location_stock (
  product_id uuid not null references public.products(id) on delete cascade,
  location_id uuid not null references public.inventory_locations(id) on delete restrict,
  quantity integer not null default 0 check (quantity >= 0),
  updated_at timestamptz not null default now(),
  primary key (product_id, location_id)
);

alter table public.facilities enable row level security;
alter table public.bookings enable row level security;
alter table public.booking_payments enable row level security;
alter table public.inventory_locations enable row level security;
alter table public.product_location_stock enable row level security;

create policy "signed in can read facilities" on public.facilities for select to authenticated using (true);
create policy "admins manage facilities" on public.facilities for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "signed in can read bookings" on public.bookings for select to authenticated using (true);
create policy "staff create bookings" on public.bookings for insert to authenticated with check (created_by = auth.uid());
create policy "staff update bookings" on public.bookings for update to authenticated using (created_by = auth.uid() or public.is_admin()) with check (created_by = auth.uid() or public.is_admin());
create policy "staff read booking payments" on public.booking_payments for select to authenticated using (received_by = auth.uid() or public.is_admin());
create policy "staff create booking payments" on public.booking_payments for insert to authenticated with check (received_by = auth.uid());
create policy "signed in can read locations" on public.inventory_locations for select to authenticated using (true);
create policy "admins manage locations" on public.inventory_locations for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "signed in can read location stock" on public.product_location_stock for select to authenticated using (true);
create policy "admins manage location stock" on public.product_location_stock for all to authenticated using (public.is_admin()) with check (public.is_admin());

insert into public.facilities(name, facility_type, default_price)
values ('Event Compound', 'EVENT_COMPOUND', 1500), ('Conference/Event Room', 'CONFERENCE_ROOM', 800)
on conflict (name) do nothing;

insert into public.inventory_locations(name)
values ('FRIDGE'), ('HOT / OTHER STORAGE')
on conflict (name) do nothing;

create or replace view public.booking_payment_status with (security_invoker = true) as
select b.id as booking_id,
  b.total_amount,
  coalesce(sum(p.amount), 0)::numeric(12,2) as amount_paid,
  greatest(b.total_amount - coalesce(sum(p.amount), 0), 0)::numeric(12,2) as balance,
  case when coalesce(sum(p.amount), 0) <= 0 then 'UNPAID'
       when coalesce(sum(p.amount), 0) < b.total_amount then 'PART PAYMENT'
       else 'PAID IN FULL' end as payment_status
from public.bookings b left join public.booking_payments p on p.booking_id = b.id
group by b.id;

grant select on public.booking_payment_status to authenticated;


