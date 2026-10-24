export const revalidate = 300;

export async function GET() {
  try {
    const response = await fetch("https://api.github.com/repos/shinuXcode/Snote/releases?per_page=6", {
      headers: { Accept: "application/vnd.github+json", "X-GitHub-Api-Version": "2022-11-28" },
      next: { revalidate: 300 }
    });
    if (!response.ok) return Response.json({ error: "GitHub updates are unavailable." }, { status: 502 });
    const releases = await response.json();
    const notifications = releases.filter((release: any) => !release.draft).map((release: any) => ({
      id: String(release.id),
      title: release.name || release.tag_name,
      body: String(release.body || "A new Snote release is available.").replace(/[#*\x60>]/g, "").slice(0, 180),
      date: release.published_at || null,
      href: release.html_url,
      kind: release.prerelease ? "PREVIEW RELEASE" : "RELEASE"
    }));
    return Response.json({ notifications }, { headers: { "Cache-Control": "public, s-maxage=300, stale-while-revalidate=600" } });
  } catch {
    return Response.json({ error: "Could not connect to GitHub." }, { status: 503 });
  }
}
