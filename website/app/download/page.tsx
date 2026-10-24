import type { Metadata } from "next";
export const metadata: Metadata = { title: "Download Snotee — Latest Releases", description: "Check the latest published Snotee version, release notes, and direct downloads for available platforms.", alternates: { canonical: "https://snotee.vercel.app/download" } };
import Link from "next/link";
import ReleaseCenter from "../../components/ReleaseCenter";
export default function DownloadPage(){
 return <main className="shell section download-page"><ReleaseCenter/><section className="download-help card"><div><span className="eyebrow"><i/> KEEP YOUR BUILD CURRENT</span><h2>Release tracking, without guesswork.</h2><p className="muted">This page checks the published Snotee releases automatically. Download links are served through this website, and previous versions remain available from the release notes when published.</p></div><div className="row"><Link className="ghost-cta" href="/docs">Read the docs →</Link><Link className="ghost-cta" href="/features">Explore features →</Link></div></section></main>
}
