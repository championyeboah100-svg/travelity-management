import { createClient } from "@supabase/supabase-js";
import { NextResponse } from "next/server";

export const runtime = "nodejs";

export async function POST(request: Request) {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL?.replace(/\/rest\/v1\/?$/, "");
  const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !serviceRoleKey) return NextResponse.json({ error: "Worker signup is not configured." }, { status: 503 });
  const body = await request.json() as { fullName?: string; phone?: string; email?: string; password?: string };
  const fullName = body.fullName?.trim() ?? ""; const phone = body.phone?.trim() ?? ""; const email = body.email?.trim().toLowerCase() ?? "";
  if (!fullName || !phone || !email || !body.password || body.password.length < 8) return NextResponse.json({ error: "Name, phone, email, and a password of at least 8 characters are required." }, { status: 400 });
  const admin = createClient(url, serviceRoleKey, { auth: { autoRefreshToken: false, persistSession: false } });
  const { data, error } = await admin.auth.admin.createUser({ email, password: body.password, email_confirm: true });
  if (error || !data.user) return NextResponse.json({ error: error?.message ?? "Unable to create account." }, { status: 400 });
  const { error: profileError } = await admin.from("profiles").insert({ id: data.user.id, full_name: fullName, role: "WORKER", active: true });
  if (profileError) { await admin.auth.admin.deleteUser(data.user.id); return NextResponse.json({ error: "Account could not be linked to a worker profile." }, { status: 500 }); }
  return NextResponse.json({ ok: true });
}

