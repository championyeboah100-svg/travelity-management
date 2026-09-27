alter table public.guests add column if not exists email text;

create or replace function public.check_in_guest_with_contact(p_guest_name text, p_phone text, p_email text, p_room_id uuid, p_expected_checkout_at timestamptz, p_nights integer, p_room_rate numeric, p_amount_paid numeric, p_payment_method public.payment_method, p_notes text default null) returns uuid language plpgsql security invoker set search_path = public as $$
declare v_guest uuid; v_stay uuid; v_room rooms%rowtype; v_total numeric(12,2);
begin
 if auth.uid() is null then raise exception 'Not authenticated'; end if;
 if nullif(trim(p_phone),'') is null then raise exception 'Phone number is required'; end if;
 if p_amount_paid < 0 or p_amount_paid > p_nights*p_room_rate then raise exception 'Invalid payment amount'; end if;
 select * into v_room from rooms where id=p_room_id for update;
 if not found or v_room.status <> 'AVAILABLE' then raise exception 'Room is not available'; end if;
 insert into guests(full_name,phone,email) values(trim(p_guest_name),trim(p_phone),nullif(trim(p_email),'')) returning id into v_guest;
 v_total := p_nights*p_room_rate;
 insert into stays(guest_id,room_id,expected_checkout_at,nights,room_rate,total_amount,notes,created_by) values(v_guest,p_room_id,p_expected_checkout_at,p_nights,p_room_rate,v_total,p_notes,auth.uid()) returning id into v_stay;
 update rooms set status='OCCUPIED' where id=p_room_id;
 if p_amount_paid > 0 then insert into payments(stay_id,amount,payment_method,received_by) values(v_stay,p_amount_paid,p_payment_method,auth.uid()); end if;
 insert into audit_logs(actor_id,action,entity_type,entity_id,new_value) values(auth.uid(),'CHECK_IN','stays',v_stay,jsonb_build_object('room_id',p_room_id,'amount_paid',p_amount_paid));
 return v_stay;
end; $$;
grant execute on function public.check_in_guest_with_contact(text,text,text,uuid,timestamptz,integer,numeric,numeric,public.payment_method,text) to authenticated;

