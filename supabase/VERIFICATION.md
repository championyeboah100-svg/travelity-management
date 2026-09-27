# Supabase acceptance checks

Run these checks after applying the migration and creating an admin profile. Use a real worker account for worker checks; do not seed production with fake transactions.

1. As admin, call `create_product('Coke', 8, 100, 10)`. Confirm `products.current_stock = 100` and one `OPENING` movement exists.
2. As admin, call `add_stock(product_id, 20, null, null, 'Delivery')`. Confirm stock is `120` and the movement records `previous_quantity = 100`, `new_quantity = 120`.
3. As worker, call `complete_product_sale('[{"product_id":"PRODUCT_UUID","quantity":3}]'::jsonb, 'CASH', 'Test customer', null)`. Confirm stock is `117`, the sale worker is the authenticated worker, and a payment exists.
4. As worker, call `check_in_guest('Test guest', null, 'AVAILABLE_ROOM_UUID', now() + interval '1 day', 1, 300, 300, 'CASH', null)`. Confirm the room is `OCCUPIED` and a stay/payment/audit row exists.
5. Repeat the check-in against the same room. It must fail with `Room is not available` or the unique active-stay constraint.
6. As a second worker, query the first worker's sale. RLS must return no row.
7. As admin, call `void_product_sale('SALE_UUID', 'Test correction')`. Confirm stock returns to `120`, the sale has `voided_at`, and the restore movement/audit row exists.
8. Query `active_payments`. Payments belonging to voided product sales must be excluded from active totals.

## Manual Vercel smoke test

Configure `NEXT_PUBLIC_SUPABASE_URL` and `NEXT_PUBLIC_SUPABASE_ANON_KEY` in the Vercel project, deploy, sign in as the seeded admin, then create a worker profile in Supabase Auth and `public.profiles`. Confirm that the worker only sees Dashboard, Rooms, and New sale, and that direct admin RPC calls fail with `Admin access required`.

