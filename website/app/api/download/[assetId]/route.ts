export const runtime = "nodejs";
export const dynamic = "force-dynamic";
export async function GET(_request: Request, context: { params: Promise<{ assetId: string }> }) {
 const { assetId } = await context.params;
 if (!/^\d+$/.test(assetId)) return new Response("Invalid asset identifier.", { status: 400 });
 try {
  const response = await fetch("https://api.github.com/repos/shinuXcode/Snote/releases?per_page=20", { headers: { Accept: "application/vnd.github+json" }, cache: "no-store" });
  if (!response.ok) return new Response("Release metadata unavailable.", { status: 502 });
  const releases = await response.json();
  const release = releases.find((item: any) => !item.draft && item.assets.some((asset: any) => String(asset.id) === assetId));
  const asset = release?.assets.find((item: any) => String(item.id) === assetId);
  if (!asset?.browser_download_url) return new Response("This published asset was not found.", { status: 404 });
  const upstream = await fetch(asset.browser_download_url, { cache: "no-store", redirect: "follow" });
  if (!upstream.ok || !upstream.body) return new Response("The release file is temporarily unavailable.", { status: 502 });
  const filename = asset.name.replace(/[\r\n"]/g, "_");
  return new Response(upstream.body, { status: 200, headers: { "Content-Type": upstream.headers.get("content-type") || "application/octet-stream", "Content-Disposition": "attachment; filename=\"" + filename + "\"; filename*=UTF-8''" + encodeURIComponent(asset.name), "Content-Length": upstream.headers.get("content-length") || String(asset.size), "Cache-Control": "private, no-store", "X-Content-Type-Options": "nosniff" } });
 } catch { return new Response("Download service temporarily unavailable.", { status: 503 }); }
}
