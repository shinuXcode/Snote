import type { Metadata } from "next";
import Link from "next/link";
import ReleaseCenter from "../../components/ReleaseCenter";

export const metadata: Metadata = {
  title: "Download Snotee for All Platforms",
  description: "Get official Snotee Android and desktop releases. Check iOS signing, package sizes, and version notes.",
  alternates: { canonical: "https://snotee.vercel.app/download" },
  openGraph: {
    title: "Download Snotee — All platform releases",
    description: "Find the latest published Snotee builds and platform-specific installation notes.",
    url: "https://snotee.vercel.app/download",
    type: "website"
  }
};

export default function DownloadPage() {
  return <main className="shell section download-page">
    <div className="download-intro">
      <span className="eyebrow"><i /> OFFICIAL RELEASES</span>
      <h1 className="title">Your workspace.<br /><em>On your platform.</em></h1>
      <p className="lead">Choose a published build for your device. Every download below is matched to an actual GitHub release asset; platform availability and signing status are shown honestly.</p>
    </div>
    <ReleaseCenter />
    <section className="download-help card">
      <div>
        <span className="eyebrow"><i /> INSTALLATION & SIGNING</span>
        <h2>Know what you are installing.</h2>
        <p className="muted">Android packages are distributed as APK files. Windows, macOS, and Linux builds are published as platform-specific archives. The current iOS release contains an unsigned archive, not an install-ready IPA; normal iOS installation requires an Apple-signed build and valid provisioning. Always choose the package that matches your operating system and processor architecture.</p>
      </div>
      <div className="row">
        <Link className="ghost-cta" href="/docs">Read the docs →</Link>
        <a className="ghost-cta" href="https://github.com/shinuXcode/Snote/releases" target="_blank" rel="noreferrer">All GitHub releases ↗</a>
      </div>
    </section>
    <section className="download-guide">
      <div className="eyebrow"><i /> BEFORE YOU INSTALL</div>
      <h2 className="title">A safer, cleaner <em>update.</em></h2>
      <div className="download-guide-grid">
        <article className="card"><h3>1. Choose the right build</h3><p className="muted">Android users need the APK. Windows, macOS, and Linux users should download the archive matching their platform. Web is a separate browser build, not a native installer.</p></article>
        <article className="card"><h3>2. Read the release notes</h3><p className="muted">Check the version number, publication date, and changes before installing. If you are updating an existing installation, keep your notes backed up first.</p></article>
        <article className="card"><h3>3. Verify before trusting</h3><p className="muted">Use release checksums or signatures when the project publishes them. Download from this page or the official GitHub repository, not from third-party APK mirrors.</p></article>
      </div>
      <p className="muted download-guide-note">Snotee is a local-first project. A software update should not be treated as a backup: export or copy your notes using the backup method documented for your installed version before making major changes.</p>
    </section>
  </main>;
}
