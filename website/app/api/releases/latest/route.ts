export const revalidate = 300;
export async function GET() {
 try {
  const response = await fetch("https://api.github.com/repos/shinuXcode/Snote/releases?per_page=20", { headers: { Accept: "application/vnd.github+json" }, next: { revalidate: 300 } });
  if (!response.ok) return Response.json({ error: "Release service unavailable." }, { status: 502 });
  const releases = await response.json();
  const release = releases.find((item: any) => !item.draft && !item.prerelease) || releases.find((item: any) => !item.draft);
  if (!release) return Response.json({ error: "No published release found.", assets: [] }, { status: 404 });
  return Response.json({ version: release.tag_name.replace(/^v/i, ""), tag_name: release.tag_name, published_at: release.published_at, html_url: release.html_url, body: release.body || "", prerelease: release.prerelease, assets: release.assets.map((a: any) => ({ id: a.id, name: a.name, size: a.size, content_type: a.content_type })) }, { headers: { "Cache-Control": "public, s-maxage=300, stale-while-revalidate=600" } });
 } catch { return Response.json({ error: "Could not connect to the release service." }, { status: 503 }); }
}
