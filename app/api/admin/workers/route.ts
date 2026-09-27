import { createServerClient } from "@supabase/ssr";
import { createClient } from "@supabase/supabase-js";
import { NextResponse, type NextRequest } from "next/server";

export const runtime = "nodejs";

function projectUrl() {
  return process.env.NEXT_PUBLIC_SUPABASE_URL?.replace(/\/rest\/v1\/?$/, "");
}

async function getAdmin(request: NextRequest) {
  const url = projectUrl();
  const anonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
  const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !anonKey || !serviceRoleKey) return null;
  let response = NextResponse.next({ request });
  const client = createServerClient(url, anonKey, {
    cookies: {
      getAll: () => request.cookies.getAll(),
      setAll(cookies) {
        cookies.forEach(({ name, value }) => request.cookies.set(name, value));
        response = NextResponse.next({ request });
        cookies.forEach(({ name, value, options }) => response.cookies.set(name, value, options));
      },
    },
  });
  const { data: { user } } = await client.auth.getUser();
  if (!user) return null;
  const { data: profile } = await client.from("profiles").select("role,active").eq("id", user.id).maybeSingle();
  if (profile?.role !== "ADMIN" || !profile.active) return null;
  return { user, admin: createClient(url, serviceRoleKey, { auth: { autoRefreshToken: false, persistSession: false } }) };
}

export async function GET(request: NextRequest) {
  const context = await getAdmin(request);
  if (!context) return NextResponse.json({ error: "Admin access required" }, { status: 403 });
  const { data, error } = await context.admin.from("profiles").select("id,full_name,role,active,created_at").eq("role", "WORKER").order("full_name");
  if (error) return NextResponse.json({ error: error.message }, { status: 500 });
  return NextResponse.json({ workers: data ?? [] });
}

export async function POST(request: NextRequest) {
  const context = await getAdmin(request);
  if (!context) return NextResponse.json({ error: "Admin access required" }, { status: 403 });
  const body = await request.json() as { fullName?: string; email?: string; password?: string; confirmPassword?: string };
  const fullName = body.fullName?.trim() ?? "";
  const email = body.email?.trim().toLowerCase() ?? "";
  if (!fullName || !email || !body.password || body.password !== body.confirmPassword || body.password.length < 8) {
    return NextResponse.json({ error: "Provide a name, valid email, and matching password of at least 8 characters." }, { status: 400 });
  }
  const { data: created, error: createError } = await context.admin.auth.admin.createUser({ email, password: body.password, email_confirm: true });
  if (createError || !created.user) return NextResponse.json({ error: createError?.message ?? "Unable to create worker account." }, { status: 400 });
  const { error: profileError } = await context.admin.from("profiles").insert({ id: created.user.id, full_name: fullName, role: "WORKER", active: true });
  if (profileError) {
    await context.admin.auth.admin.deleteUser(created.user.id);
    return NextResponse.json({ error: "Worker account could not be linked to a profile." }, { status: 500 });
  }
  return NextResponse.json({ worker: { id: created.user.id, full_name: fullName, email, role: "WORKER", active: true } }, { status: 201 });
}

export async function PATCH(request: NextRequest) {
  const context = await getAdmin(request);
  if (!context) return NextResponse.json({ error: "Admin access required" }, { status: 403 });
  const body = await request.json() as { id?: string; active?: boolean };
  if (!body.id || typeof body.active !== "boolean") return NextResponse.json({ error: "Worker ID and active status are required." }, { status: 400 });
  const { error } = await context.admin.from("profiles").update({ active: body.active }).eq("id", body.id).eq("role", "WORKER");
  if (error) return NextResponse.json({ error: error.message }, { status: 400 });
  return NextResponse.json({ ok: true });
}

