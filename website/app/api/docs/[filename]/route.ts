import { NextRequest } from "next/server";

export const runtime = "nodejs";
export const revalidate = 86400;

const allowed = new Set([
  "app-overview.pdf",
  "features.pdf",
  "notifications-admin.pdf",
  "open-source.pdf",
  "permissions.pdf",
  "license.pdf",
  "sdks.pdf",
  "terms.pdf",
  "repository-audit.pdf",
]);
const sourceRevision = "449b8f4a2ebd4f96c95d564add556935b2dd5248";

export async function GET(request: NextRequest, context: { params: Promise<{ filename: string }> }) {
  const { filename } = await context.params;
  if (!allowed.has(filename)) return new Response("Document not found", { status: 404 });

  const sourceUrl = `https://raw.githubusercontent.com/shinuXcode/Snote/${sourceRevision}/website/public/docs/${filename}`;
  try {
    const upstream = await fetch(sourceUrl, { next: { revalidate: 86400 } });
    if (!upstream.ok || !upstream.body) {
      return new Response("This document is temporarily unavailable.", { status: 502 });
    }
    const download = request.nextUrl.searchParams.get("download") === "1";
    return new Response(upstream.body, {
      status: 200,
      headers: {
        "Content-Type": "application/pdf",
        "Content-Disposition": `${download ? "attachment" : "inline"}; filename="${filename}"`,
        "Cache-Control": "public, s-maxage=86400, stale-while-revalidate=604800",
        "X-Content-Type-Options": "nosniff",
      },
    });
  } catch {
    return new Response("This document is temporarily unavailable.", { status: 502 });
  }
}
