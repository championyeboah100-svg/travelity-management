create extension if not exists pgcrypto;
create type public.user_role as enum ('ADMIN','WORKER');
create type public.room_status as enum ('AVAILABLE','OCCUPIED','MAINTENANCE');
create type public.payment_method as enum ('CASH','MOMO');
create type public.transaction_type as enum ('PRODUCT_SALE','ROOM_PAYMENT','CHECK_IN','CHECK_OUT','VOID');
create type public.inventory_movement_type as enum ('OPENING','PURCHASE','SALE','ADJUSTMENT','VOID_RESTORE');

create table public.business_settings (id uuid primary key default gen_random_uuid(), business_name text not null default 'My Guest House', currency text not null default 'GHS', low_stock_default integer not null default 5, created_at timestamptz not null default now());
create table public.profiles (id uuid primary key references auth.users(id) on delete cascade, full_name text not null, role public.user_role not null default 'WORKER', active boolean not null default true, created_at timestamptz not null default now());
create table public.product_categories (id uuid primary key default gen_random_uuid(), name text not null unique, active boolean not null default true, created_at timestamptz not null default now());
create table public.products (id uuid primary key default gen_random_uuid(), name text not null, category_id uuid references public.product_categories(id), selling_price numeric(12,2) not null check (selling_price >= 0), current_stock integer not null default 0 check (current_stock >= 0), low_stock_threshold integer not null default 5 check (low_stock_threshold >= 0), active boolean not null default true, created_at timestamptz not null default now(), updated_at timestamptz not null default now());
create table public.rooms (id uuid primary key default gen_random_uuid(), room_number text not null unique, room_type text not null, default_price numeric(12,2) not null check (default_price >= 0), status public.room_status not null default 'AVAILABLE', created_at timestamptz not null default now());
create table public.guests (id uuid primary key default gen_random_uuid(), full_name text not null, phone text, created_at timestamptz not null default now());
create table public.stays (id uuid primary key default gen_random_uuid(), guest_id uuid not null references public.guests(id), room_id uuid not null references public.rooms(id), check_in_at timestamptz not null default now(), expected_checkout_at timestamptz not null, checked_out_at timestamptz, nights integer not null check (nights > 0), room_rate numeric(12,2) not null check (room_rate >= 0), total_amount numeric(12,2) not null check (total_amount >= 0), notes text, created_by uuid not null references public.profiles(id), created_at timestamptz not null default now());
create unique index one_active_stay_per_room on public.stays(room_id) where checked_out_at is null;
create table public.sales (id uuid primary key default gen_random_uuid(), worker_id uuid not null references public.profiles(id), stay_id uuid references public.stays(id), customer_name text, total_amount numeric(12,2) not null check (total_amount >= 0), payment_method public.payment_method not null, transaction_type public.transaction_type not null default 'PRODUCT_SALE', voided_at timestamptz, voided_by uuid references public.profiles(id), void_reason text, created_at timestamptz not null default now());
create table public.sale_items (id uuid primary key default gen_random_uuid(), sale_id uuid not null references public.sales(id) on delete cascade, product_id uuid not null references public.products(id), quantity integer not null check (quantity > 0), unit_price numeric(12,2) not null check (unit_price >= 0), subtotal numeric(12,2) generated always as (quantity * unit_price) stored);
create table public.payments (id uuid primary key default gen_random_uuid(), stay_id uuid references public.stays(id), sale_id uuid references public.sales(id), amount numeric(12,2) not null check (amount > 0), payment_method public.payment_method not null, received_by uuid not null references public.profiles(id), created_at timestamptz not null default now(), check ((stay_id is not null) or (sale_id is not null)));
create table public.inventory_movements (id uuid primary key default gen_random_uuid(), product_id uuid not null references public.products(id), movement_type public.inventory_movement_type not null, quantity_delta integer not null, previous_quantity integer not null, new_quantity integer not null, cost numeric(12,2), supplier text, reason text, created_by uuid not null references public.profiles(id), created_at timestamptz not null default now());
create table public.audit_logs (id uuid primary key default gen_random_uuid(), actor_id uuid not null references public.profiles(id), action text not null, entity_type text not null, entity_id uuid, previous_value jsonb, new_value jsonb, created_at timestamptz not null default now());

create schema if not exists private;
create or replace function private.is_admin() returns boolean language sql stable security definer set search_path = public as $$ select exists(select 1 from public.profiles where id = auth.uid() and role = 'ADMIN' and active) $$;
revoke all on function private.is_admin() from public;
grant execute on function private.is_admin() to authenticated;
create or replace function public.is_admin() returns boolean language sql stable security invoker set search_path = public, private as $$ select private.is_admin() $$;
revoke all on function public.is_admin() from public;
grant execute on function public.is_admin() to authenticated;
alter table public.profiles enable row level security; alter table public.rooms enable row level security; alter table public.guests enable row level security; alter table public.stays enable row level security; alter table public.products enable row level security; alter table public.product_categories enable row level security; alter table public.sales enable row level security; alter table public.sale_items enable row level security; alter table public.payments enable row level security; alter table public.inventory_movements enable row level security; alter table public.audit_logs enable row level security; alter table public.business_settings enable row level security;
create policy "signed in can read profiles" on public.profiles for select to authenticated using (id = auth.uid() or public.is_admin());
create policy "signed in can read operational data" on public.rooms for select to authenticated using (true);
create policy "signed in can read guests" on public.guests for select to authenticated using (true);
create policy "signed in can read stays" on public.stays for select to authenticated using (true);
create policy "signed in can read products" on public.products for select to authenticated using (true);
create policy "signed in can read categories" on public.product_categories for select to authenticated using (true);
create policy "signed in can read sales" on public.sales for select to authenticated using (worker_id = auth.uid() or public.is_admin());
create policy "signed in can read sale items" on public.sale_items for select to authenticated using (exists(select 1 from public.sales s where s.id = sale_id and (s.worker_id = auth.uid() or public.is_admin())));
create policy "signed in can read payments" on public.payments for select to authenticated using (received_by = auth.uid() or public.is_admin());
create policy "admins manage inventory" on public.inventory_movements for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "admins read audit" on public.audit_logs for select to authenticated using (public.is_admin());
create policy "signed in read settings" on public.business_settings for select to authenticated using (true);
create policy "workers create guests" on public.guests for insert to authenticated with check (true);
create policy "workers create stays" on public.stays for insert to authenticated with check (created_by = auth.uid());
create policy "workers update own active stays" on public.stays for update to authenticated using (created_by = auth.uid() or public.is_admin()) with check (created_by = auth.uid() or public.is_admin());
create policy "workers create payments" on public.payments for insert to authenticated with check (received_by = auth.uid());
create policy "admins manage rooms" on public.rooms for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "admins manage products" on public.products for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "admins manage categories" on public.product_categories for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "admins manage settings" on public.business_settings for all to authenticated using (public.is_admin()) with check (public.is_admin());

create or replace function public.complete_product_sale(p_items jsonb, p_payment_method public.payment_method, p_customer_name text default null, p_stay_id uuid default null) returns uuid language plpgsql security invoker set search_path = public as $$
declare v_sale uuid; v_item jsonb; v_product products%rowtype; v_qty integer; v_total numeric(12,2) := 0; v_previous integer;
begin
 if auth.uid() is null then raise exception 'Not authenticated'; end if;
 insert into sales(worker_id, customer_name, payment_method, total_amount, stay_id) values(auth.uid(), p_customer_name, p_payment_method, 0, p_stay_id) returning id into v_sale;
 for v_item in select * from jsonb_array_elements(p_items) loop
  v_qty := (v_item->>'quantity')::integer; select * into v_product from products where id=(v_item->>'product_id')::uuid and active for update;
  if not found or v_qty <= 0 then raise exception 'Invalid product'; end if; if v_product.current_stock < v_qty then raise exception 'Insufficient stock for %', v_product.name; end if;
  v_previous := v_product.current_stock; update products set current_stock=current_stock-v_qty, updated_at=now() where id=v_product.id;
  insert into sale_items(sale_id, product_id, quantity, unit_price) values(v_sale, v_product.id, v_qty, v_product.selling_price); v_total := v_total + (v_qty * v_product.selling_price);
  insert into inventory_movements(product_id,movement_type,quantity_delta,previous_quantity,new_quantity,created_by) values(v_product.id,'SALE',-v_qty,v_previous,v_previous-v_qty,auth.uid());
 end loop;
 if v_total <= 0 then raise exception 'Sale must contain items'; end if; update sales set total_amount=v_total where id=v_sale; insert into payments(sale_id,amount,payment_method,received_by) values(v_sale,v_total,p_payment_method,auth.uid());
 insert into audit_logs(actor_id,action,entity_type,entity_id,new_value) values(auth.uid(),'PRODUCT_SALE','sales',v_sale,jsonb_build_object('total',v_total)); return v_sale;
end; $$;
grant execute on function public.complete_product_sale(jsonb, public.payment_method, text, uuid) to authenticated;

create or replace function public.check_in_guest(p_guest_name text, p_phone text, p_room_id uuid, p_expected_checkout_at timestamptz, p_nights integer, p_room_rate numeric, p_amount_paid numeric, p_payment_method public.payment_method, p_notes text default null) returns uuid language plpgsql security invoker set search_path = public as $$
declare v_guest uuid; v_stay uuid; v_room rooms%rowtype; v_total numeric(12,2);
begin
 if auth.uid() is null then raise exception 'Not authenticated'; end if; if p_amount_paid < 0 or p_amount_paid > p_nights*p_room_rate then raise exception 'Invalid payment amount'; end if;
 select * into v_room from rooms where id=p_room_id for update; if not found or v_room.status <> 'AVAILABLE' then raise exception 'Room is not available'; end if;
 insert into guests(full_name,phone) values(trim(p_guest_name),nullif(trim(p_phone),'')) returning id into v_guest; v_total := p_nights*p_room_rate;
 insert into stays(guest_id,room_id,expected_checkout_at,nights,room_rate,total_amount,notes,created_by) values(v_guest,p_room_id,p_expected_checkout_at,p_nights,p_room_rate,v_total,p_notes,auth.uid()) returning id into v_stay;
 update rooms set status='OCCUPIED' where id=p_room_id;
 if p_amount_paid > 0 then insert into payments(stay_id,amount,payment_method,received_by) values(v_stay,p_amount_paid,p_payment_method,auth.uid()); end if;
 insert into audit_logs(actor_id,action,entity_type,entity_id,new_value) values(auth.uid(),'CHECK_IN','stays',v_stay,jsonb_build_object('room_id',p_room_id,'amount_paid',p_amount_paid)); return v_stay;
end; $$;
grant execute on function public.check_in_guest(text,text,uuid,timestamptz,integer,numeric,numeric,public.payment_method,text) to authenticated;

create or replace function public.check_out_guest(p_stay_id uuid, p_amount_paid numeric default 0, p_payment_method public.payment_method default null) returns void language plpgsql security invoker set search_path = public as $$
declare v_stay stays%rowtype; v_balance numeric(12,2); v_room rooms%rowtype;
begin
 select * into v_stay from stays where id=p_stay_id and checked_out_at is null for update; if not found then raise exception 'Active stay not found'; end if;
 select coalesce(sum(amount),0) into v_balance from payments where stay_id=p_stay_id;
 v_balance := v_stay.total_amount-v_balance; if p_amount_paid < 0 or p_amount_paid > v_balance then raise exception 'Invalid balance payment'; end if;
 if p_amount_paid > 0 and p_payment_method is null then raise exception 'Payment method required'; end if;
 if p_amount_paid > 0 then insert into payments(stay_id,amount,payment_method,received_by) values(p_stay_id,p_amount_paid,p_payment_method,auth.uid()); end if;
 update stays set checked_out_at=now() where id=p_stay_id; update rooms set status='AVAILABLE' where id=v_stay.room_id;
 insert into audit_logs(actor_id,action,entity_type,entity_id,new_value) values(auth.uid(),'CHECK_OUT','stays',p_stay_id,jsonb_build_object('balance_paid',p_amount_paid));
end; $$;
grant execute on function public.check_out_guest(uuid,numeric,public.payment_method) to authenticated;

create or replace function public.add_stock(p_product_id uuid, p_quantity integer, p_cost numeric default null, p_supplier text default null, p_notes text default null) returns void language plpgsql security invoker set search_path = public as $$
declare v_product products%rowtype; v_previous integer;
begin
 if not public.is_admin() then raise exception 'Admin access required'; end if; if p_quantity <= 0 then raise exception 'Quantity must be positive'; end if;
 select * into v_product from products where id=p_product_id for update; if not found then raise exception 'Product not found'; end if; v_previous := v_product.current_stock;
 update products set current_stock=current_stock+p_quantity, updated_at=now() where id=p_product_id;
 insert into inventory_movements(product_id,movement_type,quantity_delta,previous_quantity,new_quantity,cost,supplier,reason,created_by) values(p_product_id,'PURCHASE',p_quantity,v_previous,v_previous+p_quantity,p_cost,p_supplier,p_notes,auth.uid());
 insert into audit_logs(actor_id,action,entity_type,entity_id,new_value) values(auth.uid(),'ADD_STOCK','products',p_product_id,jsonb_build_object('quantity',p_quantity,'new_stock',v_previous+p_quantity));
end; $$;
grant execute on function public.add_stock(uuid,integer,numeric,text,text) to authenticated;

create or replace function public.create_product(p_name text, p_price numeric, p_opening_stock integer default 0, p_low_stock_threshold integer default 5) returns uuid language plpgsql security invoker set search_path = public as $$
declare v_id uuid;
begin
 if not public.is_admin() then raise exception 'Admin access required'; end if; if trim(p_name) = '' or p_price < 0 or p_opening_stock < 0 then raise exception 'Invalid product details'; end if;
 insert into products(name,selling_price,current_stock,low_stock_threshold) values(trim(p_name),p_price,p_opening_stock,p_low_stock_threshold) returning id into v_id;
 if p_opening_stock > 0 then insert into inventory_movements(product_id,movement_type,quantity_delta,previous_quantity,new_quantity,reason,created_by) values(v_id,'OPENING',p_opening_stock,0,p_opening_stock,'Opening stock',auth.uid()); end if;
 insert into audit_logs(actor_id,action,entity_type,entity_id,new_value) values(auth.uid(),'CREATE_PRODUCT','products',v_id,jsonb_build_object('name',p_name,'opening_stock',p_opening_stock)); return v_id;
end; $$;
grant execute on function public.create_product(text,numeric,integer,integer) to authenticated;

create or replace function public.adjust_stock(p_product_id uuid, p_quantity_delta integer, p_reason text) returns void language plpgsql security invoker set search_path = public as $$
declare v_product products%rowtype; v_previous integer;
begin
 if not public.is_admin() then raise exception 'Admin access required'; end if; if p_quantity_delta = 0 or trim(p_reason) = '' then raise exception 'Adjustment quantity and reason are required'; end if;
 select * into v_product from products where id=p_product_id for update; if not found then raise exception 'Product not found'; end if; v_previous := v_product.current_stock;
 if v_previous + p_quantity_delta < 0 then raise exception 'Adjustment would create negative stock'; end if;
 update products set current_stock=current_stock+p_quantity_delta, updated_at=now() where id=p_product_id;
 insert into inventory_movements(product_id,movement_type,quantity_delta,previous_quantity,new_quantity,reason,created_by) values(p_product_id,'ADJUSTMENT',p_quantity_delta,v_previous,v_previous+p_quantity_delta,p_reason,auth.uid());
 insert into audit_logs(actor_id,action,entity_type,entity_id,previous_value,new_value) values(auth.uid(),'ADJUST_STOCK','products',p_product_id,jsonb_build_object('stock',v_previous),jsonb_build_object('stock',v_previous+p_quantity_delta,'reason',p_reason));
end; $$;
grant execute on function public.adjust_stock(uuid,integer,text) to authenticated;

create or replace function public.void_product_sale(p_sale_id uuid, p_reason text) returns void language plpgsql security invoker set search_path = public as $$
declare v_sale sales%rowtype; v_item record; v_product products%rowtype; v_previous integer;
begin
 if not public.is_admin() then raise exception 'Admin access required'; end if; if trim(p_reason) = '' then raise exception 'Void reason is required'; end if;
 select * into v_sale from sales where id=p_sale_id for update; if not found then raise exception 'Sale not found'; end if; if v_sale.voided_at is not null then raise exception 'Sale already voided'; end if;
 for v_item in select product_id, quantity from sale_items where sale_id=p_sale_id loop
  select * into v_product from products where id=v_item.product_id for update; v_previous := v_product.current_stock;
  update products set current_stock=current_stock+v_item.quantity, updated_at=now() where id=v_item.product_id;
  insert into inventory_movements(product_id,movement_type,quantity_delta,previous_quantity,new_quantity,reason,created_by) values(v_item.product_id,'VOID_RESTORE',v_item.quantity,v_previous,v_previous+v_item.quantity,'Voided sale '||p_sale_id,auth.uid());
 end loop;
 update sales set voided_at=now(), voided_by=auth.uid(), void_reason=p_reason, transaction_type='VOID' where id=p_sale_id;
 insert into audit_logs(actor_id,action,entity_type,entity_id,previous_value,new_value) values(auth.uid(),'VOID_TRANSACTION','sales',p_sale_id,jsonb_build_object('total',v_sale.total_amount),jsonb_build_object('reason',p_reason));
end; $$;
grant execute on function public.void_product_sale(uuid,text) to authenticated;

create or replace function public.create_room(p_room_number text, p_room_type text, p_default_price numeric) returns uuid language plpgsql security invoker set search_path = public as $$
declare v_id uuid;
begin
 if not public.is_admin() then raise exception 'Admin access required'; end if; if trim(p_room_number) = '' or trim(p_room_type) = '' or p_default_price < 0 then raise exception 'Invalid room details'; end if;
 insert into rooms(room_number,room_type,default_price) values(trim(p_room_number),trim(p_room_type),p_default_price) returning id into v_id;
 insert into audit_logs(actor_id,action,entity_type,entity_id,new_value) values(auth.uid(),'CREATE_ROOM','rooms',v_id,jsonb_build_object('room_number',p_room_number,'room_type',p_room_type,'default_price',p_default_price)); return v_id;
end; $$;
grant execute on function public.create_room(text,text,numeric) to authenticated;

create or replace view public.active_payments with (security_invoker = true) as
select p.* from public.payments p
left join public.sales s on s.id = p.sale_id
where s.id is null or s.voided_at is null;
grant select on public.active_payments to authenticated;

create or replace view public.worker_daily_activity with (security_invoker = true) as
select p.id as worker_id, p.full_name,
  coalesce(sum(ap.amount) filter (where ap.payment_method = 'CASH'), 0) as cash_total,
  coalesce(sum(ap.amount) filter (where ap.payment_method = 'MOMO'), 0) as momo_total,
  count(ap.id) as transaction_count,
  coalesce(sum(ap.amount) filter (where ap.sale_id is not null), 0) as product_revenue,
  coalesce(sum(ap.amount) filter (where ap.stay_id is not null), 0) as room_revenue
from public.profiles p
left join public.active_payments ap on ap.received_by = p.id and ap.created_at >= current_date
group by p.id, p.full_name;
grant select on public.worker_daily_activity to authenticated;

