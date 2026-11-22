"use client";

import { useEffect, useState } from "react";
import Icon from "./Icon";

type Asset = { id: number; name: string; size: number };
type Release = {
  version: string;
  tag_name: string;
  published_at: string | null;
  body: string;
  prerelease: boolean;
  assets: Asset[];
  stable_version: string | null;
  history: { tag_name: string; version: string; published_at: string | null; prerelease: boolean; html_url: string; assets_count: number }[];
};

const platformOrder = ["Android", "Windows", "macOS", "Linux", "iOS", "Web"];

function formatBytes(bytes: number) {
  if (!bytes) return "Size unavailable";
  const mb = bytes / (1024 * 1024);
  return mb >= 100 ? mb.toFixed(0) + " MB" : mb.toFixed(1) + " MB";
}
const platformDescription: Record<string, string> = {
  Android: "Android APK package",
  Windows: "Windows desktop archive",
  macOS: "macOS desktop archive",
  Linux: "Linux desktop archive",
  iOS: "iOS package availability; signing status shown below",
  Web: "Web build archive"
};

function platformFor(name: string) {
  const n = name.toLowerCase();
  if (n.includes("android") || n.endsWith(".apk")) return "Android";
  if (n.includes("web")) return "Web";
  if (n.includes("windows") || n.endsWith(".msi") || n.endsWith(".exe")) return "Windows";
  if (n.includes("macos") || n.includes("darwin") || n.endsWith(".dmg")) return "macOS";
  if (n.includes("linux") || n.endsWith(".appimage") || n.endsWith(".deb") || n.endsWith(".tar.gz")) return "Linux";
  if (n.includes("ios") || n.endsWith(".ipa")) return "iOS";
  return null;
}

export default function ReleaseCenter() {
  const [release, setRelease] = useState<Release | null>(null);
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let live = true;
    async function load() {
      try {
        const response = await fetch("/api/releases/latest", { cache: "no-store" });
        if (!response.ok) throw new Error("Latest release data is temporarily unavailable.");
        const data = await response.json();
        if (live) setRelease(data);
      } catch (reason) {
        if (live) setError(reason instanceof Error ? reason.message : "Update check failed");
      } finally {
        if (live) setLoading(false);
      }
    }
    void load();
    const timer = window.setInterval(load, 300000);
    return () => { live = false; window.clearInterval(timer); };
  }, []);

  const groups = release?.assets.reduce<Record<string, Asset[]>>((result, asset) => {
    const platform = platformFor(asset.name);
    if (platform) (result[platform] ??= []).push(asset);
    return result;
  }, {}) ?? {};
  const iosAssets = groups.iOS ?? [];
  const hasSignedIpa = iosAssets.some(asset => asset.name.toLowerCase().endsWith(".ipa") && !asset.name.toLowerCase().includes("unsigned"));

  return <section className="release-center" aria-labelledby="release-heading">
    <div className="release-topline">
      <span className="eyebrow"><i /> RELEASE CHANNEL</span>
      <span className="release-status">{loading ? "Checking updates" : release ? (release.prerelease ? "Latest preview release" : "Latest stable release") : "Status unavailable"}</span>
    </div>
    <h2 id="release-heading" className="title">{release ? <>Snotee <em>{release.version}</em></> : "Get Snotee"}</h2>
    <p className="lead">{release ? "Published " + (release.published_at ? new Date(release.published_at).toLocaleDateString() : "date unavailable") + " · " + release.assets.length + " verified release assets" : "Checking the latest published version."}</p>
    {error && <p className="release-error" role="status">{error}</p>}
    {release && <>
      <div className="release-meta">
        <span>Release tag <strong>{release.tag_name}</strong></span>
        {release.stable_version && release.prerelease && <span>Latest stable <strong>{release.stable_version}</strong></span>}
        <button className="text-button" onClick={() => {
          setLoading(true);
          fetch("/api/releases/latest", { cache: "no-store" }).then(r => r.json()).then(setRelease).catch(() => setError("Refresh failed.")).finally(() => setLoading(false));
        }}>Refresh <Icon name="refresh" size={15} /></button>
      </div>
      <div className="grid release-grid">
        {platformOrder.map(platform => <article className="card release-card" key={platform}>
          <span className="pill">{platform}</span>
          <h3>{platform} build</h3>
          <p className="muted">{platformDescription[platform]}</p>
          {(groups[platform] ?? []).map(asset => <a className="ghost-cta" href={"/api/download/" + asset.id} key={asset.id}>
            {asset.name} <span className="asset-size">{formatBytes(asset.size)}</span> <Icon name="download" size={15} />
          </a>)}
          {!groups[platform]?.length && <p className="muted">No build is attached to this release. Check the release history for other versions.</p>}
          {platform === "iOS" && !hasSignedIpa && <p className="release-note-warning">{iosAssets.length ? "The current iOS asset is an unsigned archive, not an install-ready IPA. Apple signing and provisioning are required." : "No iOS build or signed IPA is attached to this release."}</p>}
        </article>)}
      </div>
      <section className="release-history">
        <div className="release-topline"><h3>Version history</h3><span className="muted">Latest published versions</span></div>
        <div className="release-history-list">{release.history?.map(item => <article className="release-history-item" key={item.tag_name}>
          <div><strong>{item.tag_name}</strong><span className="muted">{item.published_at ? new Date(item.published_at).toLocaleDateString() : "Date unavailable"} · {item.assets_count} assets · {item.prerelease ? "Preview" : "Stable"}</span></div>
          <a href={item.html_url} target="_blank" rel="noreferrer" aria-label={"Release notes for " + item.tag_name}>Release notes <Icon name="external" size={13} /></a>
        </article>)}</div>
      </section>
      <details className="release-notes"><summary>Release notes</summary><pre>{release.body || "No release notes were published."}</pre></details>
    </>}
  </section>;
}
