export const revalidate = 300;
export async function GET() {
 try {
  const response = await fetch("https://api.github.com/repos/shinuXcode/Snote/releases?per_page=20", { headers: { Accept: "application/vnd.github+json" }, next: { revalidate: 300 } });
  if (!response.ok) return Response.json({ error: "Release service unavailable." }, { status: 502 });
  const releases = await response.json();
  const published = releases.filter((item: any) => !item.draft);
  const release = published[0];
  if (!release) return Response.json({ error: "No published release found.", assets: [], history: [] }, { status: 404 });
  const stable = published.find((item: any) => !item.prerelease);
  return Response.json({
   version: release.tag_name.replace(/^v/i, ""), tag_name: release.tag_name, published_at: release.published_at,
   html_url: release.html_url, body: release.body || "", prerelease: release.prerelease,
   stable_version: stable ? stable.tag_name.replace(/^v/i, "") : null,
   assets: release.assets.map((a: any) => ({ id: a.id, name: a.name, size: a.size, content_type: a.content_type })),
   history: published.slice(0, 8).map((item: any) => ({ tag_name: item.tag_name, version: item.tag_name.replace(/^v/i, ""), published_at: item.published_at, prerelease: item.prerelease, html_url: item.html_url, assets_count: item.assets.length }))
  }, { headers: { "Cache-Control": "public, s-maxage=300, stale-while-revalidate=600" } });
 } catch { return Response.json({ error: "Could not connect to the release service." }, { status: 503 }); }
}
