import { createHmac, timingSafeEqual } from "node:crypto";
import { createClient } from "@supabase/supabase-js";
import { NextRequest, NextResponse } from "next/server";

export const runtime = "nodejs";
const COOKIE = "snote_control_room";
const MAX_AGE = 60 * 60 * 8;

function secret() {
  const value = process.env.SNOTE_ADMIN_SESSION_SECRET;
  if (!value || value.length < 32) throw new Error("SNOTE_ADMIN_SESSION_SECRET must be at least 32 characters.");
  return value;
}
function signature(value: string) {
  return createHmac("sha256", secret()).update(value).digest("base64url");
}
function makeSession() {
  const payload = Buffer.from(JSON.stringify({ exp: Date.now() + MAX_AGE * 1000 })).toString("base64url");
  return payload + "." + signature(payload);
}
function validSession(req: NextRequest) {
  const token = req.cookies.get(COOKIE)?.value || "";
  const [payload, sig] = token.split(".");
  if (!payload || !sig) return false;
  const expected = signature(payload);
  const a = Buffer.from(sig), b = Buffer.from(expected);
  if (a.length !== b.length || !timingSafeEqual(a, b)) return false;
  try { return Number(JSON.parse(Buffer.from(payload, "base64url").toString()).exp) > Date.now(); } catch { return false; }
}
function safeActionUrl(value: unknown) {\n  if (!value) return null;\n  try { const url = new URL(String(value)); return url.protocol === "https:" || url.protocol === "http:" ? url.toString().slice(0, 1000) : null; } catch { return null; }\n}\nfunction db() {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !key) throw new Error("Configure NEXT_PUBLIC_SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY in Vercel.");
  return createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });
}
function fail(error: unknown, status = 500) {
  const message = error instanceof Error ? error.message : "Notification service error.";
  return NextResponse.json({ error: message }, { status });
}
export async function POST(req: NextRequest) {
  try {
    const body = await req.json();
    if (body?.action === "login") {
      const expected = process.env.SNOTE_ADMIN_PASSWORD;
      if (!expected || expected.length < 12) return fail(new Error("Configure SNOTE_ADMIN_PASSWORD (12+ characters) in Vercel."), 503);
      const supplied = Buffer.from(String(body.password || ""));
      const target = Buffer.from(expected);
      if (supplied.length !== target.length || !timingSafeEqual(supplied, target)) return fail(new Error("Incorrect password."), 401);
      const response = NextResponse.json({ ok: true });
      response.cookies.set(COOKIE, makeSession(), { httpOnly: true, secure: process.env.NODE_ENV === "production", sameSite: "strict", path: "/", maxAge: MAX_AGE });
      return response;
    }
    if (!validSession(req)) return fail(new Error("Session expired. Sign in again."), 401);
    const title = String(body?.title || "").trim();
    const message = String(body?.body || "").trim();
    if (!title || title.length > 120 || !message || message.length > 2000) return fail(new Error("Title is required (max 120 characters) and message must be 1–2000 characters."), 400);
    const publishedAt = body?.published ? new Date().toISOString() : null;
    const record = { title, body: message, category: String(body?.category || "announcement").slice(0,40), action_url: safeActionUrl(body?.actionUrl), published_at: publishedAt, expires_at: body?.expiresAt || null, updated_at: new Date().toISOString() };
    const { data, error } = await db().from("website_notifications").insert(record).select().single();
    if (error) throw error;
    return NextResponse.json({ notification: data }, { status: 201 });
  } catch (error) { return fail(error); }
}
export async function GET(req: NextRequest) {
  if (!validSession(req)) return fail(new Error("Session expired. Sign in again."), 401);
  try {
    const { data, error } = await db().from("website_notifications").select("*").order("created_at", { ascending: false }).limit(100);
    if (error) throw error;
    return NextResponse.json({ notifications: data || [] });
  } catch (error) { return fail(error); }
}
export async function PATCH(req: NextRequest) {
  if (!validSession(req)) return fail(new Error("Session expired. Sign in again."), 401);
  try {
    const body = await req.json();
    if (!body?.id) return fail(new Error("Notification ID is required."), 400);
    const patch: Record<string, unknown> = { updated_at: new Date().toISOString() };
    if (typeof body.published === "boolean") patch.published_at = body.published ? new Date().toISOString() : null;
    if (typeof body.title === "string") patch.title = body.title.trim().slice(0,120);
    if (typeof body.body === "string") patch.body = body.body.trim().slice(0,2000);
    if (typeof body.category === "string") patch.category = body.category.slice(0,40);
    if (typeof body.actionUrl === "string") patch.action_url = safeActionUrl(body.actionUrl);
    if (body.expiresAt === null || typeof body.expiresAt === "string") patch.expires_at = body.expiresAt || null;
    const { data, error } = await db().from("website_notifications").update(patch).eq("id", body.id).select().single();
    if (error) throw error;
    return NextResponse.json({ notification: data });
  } catch (error) { return fail(error); }
}
export async function DELETE(req: NextRequest) {
  if (!validSession(req)) return fail(new Error("Session expired. Sign in again."), 401);
  try {
    const id = new URL(req.url).searchParams.get("id");
    if (!id) return fail(new Error("Notification ID is required."), 400);
    const { error } = await db().from("website_notifications").delete().eq("id", id);
    if (error) throw error;
    return NextResponse.json({ ok: true });
  } catch (error) { return fail(error); }
}
