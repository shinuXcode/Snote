import Link from "next/link";
import Reveal from "../../components/Reveal";

const version = "1.1.0";
const releasePage = "https://github.com/shinuXcode/Snote/releases/tag/v1.1.0";
const assetBase = "https://github.com/shinuXcode/Snote/releases/download/v1.1.0";
const web = process.env.NEXT_PUBLIC_SNOTE_WEB_APP_URL || assetBase + "/Snote-Web.tar.gz";

const builds = [
  ["Android", "APK", assetBase + "/Snote-Android.apk", "Verified Android APK."],
  ["Windows", "ZIP", assetBase + "/Snote-Windows.zip", "Verified Windows desktop bundle."],
  ["macOS", "ZIP", assetBase + "/Snote-macOS.zip", "Verified macOS desktop bundle."],
  ["Linux", "TAR.GZ", assetBase + "/Snote-Linux.tar.gz", "Verified Linux desktop bundle."],
  ["iOS", "UNSIGNED ZIP", assetBase + "/Snote-iOS-unsigned.zip", "Unsigned iOS build; App Store distribution still requires Apple signing."],
  ["Web", "WEB", web, "Launch the web app when configured, or download the verified web bundle."],
] as const;

export default function Page() {
  return (
    <main className="shell section">
      <Reveal>
        <div className="eyebrow">Download center</div>
        <h1 className="title">Snote {version}</h1>
        <p className="lead">
          One notebook format, one account identity, multiple platforms.
        </p>
      </Reveal>

      <Reveal>
        <div className="card" style={{ marginTop: 28, marginBottom: 18 }}>
          <div className="eyebrow">Release status</div>
          <h2>Verified builds only.</h2>
          <p className="muted">
            Downloads are published only after the v1.1.0 production release workflow completes.
          </p>
          <a className="cta" href={releasePage}>
            Open Snote releases
          </a>
        </div>
      </Reveal>

      <Reveal>
        <div className="card" style={{ marginTop: 18, marginBottom: 18 }}>
          <div className="eyebrow">Release history</div>
          <p className="muted">Snote keeps previous releases available so users can stay on an older build when needed.</p>
          <div className="row">
            <a className="ghost-cta" href="https://github.com/shinuXcode/Snote/releases/tag/v1.1.0">Snote 1.1.0</a>
            <a className="ghost-cta" href="https://github.com/shinuXcode/Snote/releases/tag/v0.6.0">Snote 0.6.0</a>
          </div>
        </div>
      </Reveal>

      <div className="grid">
        {builds.map(([name, type, url, desc]) => (
          <Reveal key={name}>
            <article className="card feature-card">
              <span className="pill">{type}</span>
              <h2>{name}</h2>
              <p className="muted">{desc}</p>
              {name === "Web" ? (
                <a className="cta" href={url}>Launch</a>
              ) : (
                <a className="ghost-cta" href={url}>
                  Download
                </a>
              )}
            </article>
          </Reveal>
        ))}
      </div>

      <Reveal>
        <div className="card" style={{ marginTop: 18 }}>
          <div className="eyebrow">Version {version}</div>
          <p className="muted">
            The release pipeline runs dependency installation, launcher-icon generation,
            static analysis, tests and a release build before publishing artifacts.
          </p>
          <Link href="/account">Open the note portal →</Link>
        </div>
      </Reveal>
    </main>
  );
}