# Tranquility Lodge

Mobile-first internal hotel operations app built with Next.js, TypeScript, Tailwind CSS and Supabase.

## Setup

1. Create a Supabase project and run `supabase/migrations/20260927170000_initial_schema.sql` in the SQL editor.
2. Create the first user in Supabase Authentication, then insert its profile as an admin:

```sql
insert into public.profiles (id, full_name, role) values ('AUTH_USER_UUID', 'Hotel Admin', 'ADMIN');
```

3. Copy `.env.example` to `.env.local` and set `NEXT_PUBLIC_SUPABASE_URL` and `NEXT_PUBLIC_SUPABASE_ANON_KEY`. Set `SUPABASE_SERVICE_ROLE_KEY` only in Vercel/server environments for the admin-only worker account API; never expose or commit it.
4. Run `npm install`, then `npm run dev`.

The database migration includes RLS, role checks, inventory movement history, audit records, and an atomic product-sale RPC. The browser never receives a service-role key.

## Deploy to Vercel

Import the repository into Vercel, add the two public variables and the server-only `SUPABASE_SERVICE_ROLE_KEY` for Production/Preview, and deploy. Run the Supabase migration before inviting workers. Worker profiles should use role `WORKER`; only admins can be granted `ADMIN`.

## Current V1 scope

The foundation, authentication gate, responsive shell, offline warning, schema, RLS, and atomic sale function are implemented. The remaining UI work is wiring room/stay/product/admin CRUD screens to the already-defined database tables and RPCs; no fake operational figures are displayed.

