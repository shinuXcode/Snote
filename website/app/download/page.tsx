import Link from "next/link";
import Reveal from "../../components/Reveal";

const version = "0.4.0";
const releasePage = "https://github.com/shinuXcode/Snote/releases/latest";
const web = process.env.NEXT_PUBLIC_SNOTE_WEB_APP_URL || "/";

const builds = [
  ["Android", "APK", "Snote-Android.apk", "Android release will appear here when the verified v0.4.0 build is published."],
  ["Windows", "ZIP", "Snote-Windows.zip", "Windows desktop release."],
  ["macOS", "ZIP", "Snote-macOS.zip", "macOS desktop release."],
  ["Linux", "TAR.GZ", "Snote-Linux.tar.gz", "Linux desktop bundle."],
  ["iOS", "UNSIGNED ZIP", "Snote-iOS-unsigned.zip", "Development build; App Store signing is required."],
  ["Web", "Browser", web, "Open the browser app."],
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
            Direct installer links stay disabled until GitHub publishes a verified
            release asset. This prevents the download page from sending users to
            dead 404 URLs.
          </p>
          <a className="cta" href={releasePage}>
            Open Snote releases
          </a>
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
                <a className="ghost-cta" href={releasePage}>
                  View release
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
