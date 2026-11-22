import type { Metadata } from "next";
import Link from "next/link";
import ReleaseCenter from "../../components/ReleaseCenter";

export const metadata: Metadata = {
  title: "Download Snotee for Android, Windows, macOS and Linux",
  description: "Download the latest published Snotee Android APK and desktop builds for Windows, macOS, and Linux. Check iOS signing status, release notes, and verified platform assets.",
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
        <p className="muted">Android and desktop packages are distributed through published releases. The current iOS artifact is an unsigned build archive, not an install-ready IPA. iOS installation requires an Apple-signed build and appropriate provisioning.</p>
      </div>
      <div className="row">
        <Link className="ghost-cta" href="/docs">Read the docs →</Link>
        <a className="ghost-cta" href="https://github.com/shinuXcode/Snote/releases" target="_blank" rel="noreferrer">All GitHub releases ↗</a>
      </div>
    </section>
  </main>;
}
