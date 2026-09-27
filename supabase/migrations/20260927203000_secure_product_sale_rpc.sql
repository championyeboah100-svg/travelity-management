create schema if not exists private;

create or replace function private.complete_product_sale_impl(p_items jsonb, p_payment_method public.payment_method, p_customer_name text default null, p_stay_id uuid default null) returns uuid
language plpgsql security definer set search_path = public, private as $$
declare v_sale uuid; v_item jsonb; v_product products%rowtype; v_qty integer; v_total numeric(12,2) := 0; v_previous integer;
begin
 if auth.uid() is null or not exists (select 1 from profiles where id=auth.uid() and active) then raise exception 'Active authenticated account required'; end if;
 insert into sales(worker_id, customer_name, payment_method, total_amount, stay_id) values(auth.uid(), p_customer_name, p_payment_method, 0, p_stay_id) returning id into v_sale;
 for v_item in select * from jsonb_array_elements(p_items) loop
  v_qty := (v_item->>'quantity')::integer;
  select * into v_product from products where id=(v_item->>'product_id')::uuid and active for update;
  if not found or v_qty <= 0 then raise exception 'Invalid product'; end if;
  if v_product.current_stock < v_qty then raise exception 'Only % available in stock.', v_product.current_stock; end if;
  v_previous := v_product.current_stock;
  update products set current_stock=current_stock-v_qty, updated_at=now() where id=v_product.id;
  insert into sale_items(sale_id, product_id, quantity, unit_price) values(v_sale, v_product.id, v_qty, v_product.selling_price);
  v_total := v_total + (v_qty * v_product.selling_price);
  insert into inventory_movements(product_id,movement_type,quantity_delta,previous_quantity,new_quantity,created_by) values(v_product.id,'SALE',-v_qty,v_previous,v_previous-v_qty,auth.uid());
 end loop;
 if v_total <= 0 then raise exception 'Sale must contain items'; end if;
 update sales set total_amount=v_total where id=v_sale;
 insert into payments(sale_id,amount,payment_method,received_by) values(v_sale,v_total,p_payment_method,auth.uid());
 insert into audit_logs(actor_id,action,entity_type,entity_id,new_value) values(auth.uid(),'PRODUCT_SALE','sales',v_sale,jsonb_build_object('total',v_total));
 return v_sale;
end; $$;

create or replace function public.complete_product_sale(p_items jsonb, p_payment_method public.payment_method, p_customer_name text default null, p_stay_id uuid default null) returns uuid
language sql security invoker set search_path = public, private as $$ select private.complete_product_sale_impl(p_items,p_payment_method,p_customer_name,p_stay_id); $$;

revoke all on function private.complete_product_sale_impl(jsonb, public.payment_method, text, uuid) from public;
grant execute on function private.complete_product_sale_impl(jsonb, public.payment_method, text, uuid) to authenticated;
grant execute on function public.complete_product_sale(jsonb, public.payment_method, text, uuid) to authenticated;

