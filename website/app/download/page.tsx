import type { Metadata } from "next";
import Link from "next/link";
import ReleaseCenter from "../../components/ReleaseCenter";

export const metadata: Metadata = {
 title: "Download Snote — Latest Releases",
 description: "Download Snote releases for supported platforms, review version notes, and check available builds from the official open-source project.",
 alternates: { canonical: "https://snote-showcase.vercel.app/download" },
 keywords: ["download Snote","Snote releases","Snote Android","open-source notes app"],
 openGraph: { title: "Download Snote — Latest Releases", description: "Find Snote builds, release notes, and supported platform downloads.", url: "https://snote-showcase.vercel.app/download", type: "website", images: [{url:"/opengraph-image",width:1200,height:630,alt:"Download Snote releases"}] },
 twitter: { card: "summary_large_image", title: "Download Snote — Latest Releases", description: "Find Snote builds, release notes, and supported platform downloads.", images:["/opengraph-image"] }
, other: { "article:modified_time": "2026-10-21" }};

export default function DownloadPage(){
 return <main className="shell section download-page">
  <header className="download-intro"><div className="eyebrow"><i/> OFFICIAL RELEASES</div><h1 className="title">Download Snote.<br/><em>Your ideas, in reach.</em></h1><p className="lead">Find published Snote builds, check version history, and read release notes before installing. Availability depends on which assets have been published for each release.</p></header>
  <ReleaseCenter/>
  <section className="download-help card"><div><span className="eyebrow"><i/> KEEP YOUR BUILD CURRENT</span><h2>How should I choose a release?</h2><p className="muted">Review the release tag and notes first. Preview releases may contain unfinished changes; choose a stable release when one is available and follow the installation instructions for your platform.</p><p className="muted">Snote is an open-source project. You can review the source and report release problems in the <a href="https://github.com/shinuXcode/Snote" target="_blank" rel="noreferrer">GitHub repository</a> or its <a href="https://github.com/shinuXcode/Snote/issues" target="_blank" rel="noreferrer">issue tracker</a>.</p></div><div className="row"><Link className="ghost-cta" href="/docs">Read the docs →</Link><Link className="ghost-cta" href="/features">Explore features →</Link></div></section>
  <section className="download-safety"><h2>Before installing</h2><p>Use official release assets and review the requested permissions on your device. Do not install a build if its source or origin cannot be verified. For general web security guidance, see the <a href="https://owasp.org/www-project-top-ten/" target="_blank" rel="noreferrer">OWASP Top 10</a>; for software project details, consult the <a href="https://github.com/shinuXcode/Snote" target="_blank" rel="noreferrer">Snote source repository</a>.</p><h2>Where can I get help?</h2><p>Read the <Link href="/docs">documentation</Link>, check <Link href="/faqs">frequently asked questions</Link>, or contact the maintainers through <a href="https://github.com/shinuXcode/Snote/issues" target="_blank" rel="noreferrer">GitHub Issues</a>.</p></section>
 </main>
}
