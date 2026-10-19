import Link from "next/link";
import type { Metadata } from "next";
export const metadata: Metadata = {
 title: "Snote Documentation — User Guides, Licenses and Policies",
 description: "Download Snote user guides, feature catalogue, open-source documentation, privacy and data handling, permissions, license notices, app overview, and repository audit.",
 alternates: { canonical: "https://snote-showcase.vercel.app/docs" },
 openGraph: { title: "Snote Documentation", description: "Guides, project documentation, policies, and PDF downloads for Snote.", url: "https://snote-showcase.vercel.app/docs", type: "website" }
};
const docs = [
 ["01","User Guide","Installation, handwriting, pages, PDF workflows, backup, and troubleshooting.","user-guide"],
 ["02","Feature Catalogue","Code-informed feature areas, ink architecture, storage, and platform notes.","features"],
 ["03","Open Source Guide","Repository structure, local development, contribution standards, CI, and releases.","open-source"],
 ["04","Privacy & Data Handling","Local-first storage, optional cloud data, third parties, retention, and review notes.","privacy"],
 ["05","Permissions & Authorization","File, image, camera, network, account authorization, and release verification.","permissions"],
 ["06","License & Third-party Notices","MIT license summary, redistribution requirements, and dependency notices.","license"],
 ["07","App Overview","Product description, platform support, versioning, and upgrade guidance.","app-overview"],
 ["08","SDKs & Toolchains","Declared Flutter/Dart, Next.js, React, Supabase, and platform build requirements.","sdks"],
 ["09","Terms of Use","Plain-language usage, user content, backups, cloud services, and disclaimers.","terms"],
 ["10","Security & Disclosure","Secret handling, authorization tests, release safety, and responsible vulnerability reporting.","security"],
 ["11","Repository Audit","Source-level findings, security-sensitive areas, and outstanding verification checklist.","repository-audit"]
];
export default function DocsPage(){
 return <main className="shell section docs-page">
  <div className="eyebrow"><i/> DOCUMENTATION</div>
  <h1 className="title">A clear path from<br/><em>first note to flow.</em></h1>
  <p className="lead">Downloadable guides and project documents for users, contributors, and administrators. Documents distinguish source-observed behavior from platform-dependent features and outstanding verification.</p>
  <div className="docs-callout card"><div><span className="pill">START HERE</span><h2>New to Snote?</h2><p className="muted">Read the user guide, then review privacy and permissions before enabling cloud features.</p></div><Link className="cta" href="/api/docs/user-guide">Download user guide PDF <span aria-hidden="true">↓</span></Link></div>
  <div className="grid docs-grid">{docs.map(([n,title,body,slug])=><article className="card docs-card" key={slug}><span className="feature-number">{n} / PDF</span><h2>{title}</h2><p className="muted">{body}</p><a className="docs-download" href={"/api/docs/"+slug} download><span>Download PDF</span><span aria-hidden="true">↓</span></a></article>)}</div>
  <section className="docs-faq card"><div><span className="pill">HELP CENTRE</span><h2>Need a quick answer?</h2><p className="muted">Browse common questions about installation, stylus input, privacy, cloud sync, permissions, and releases.</p></div><Link className="cta" href="/faqs">Browse 28 FAQs <span aria-hidden="true">→</span></Link></section>
  <p className="docs-note">Legal and security documents are informational and do not replace legal advice, platform-specific permission review, or a production security audit. Features can vary by version. PDF covers credit Sadab as founder/creator; interior pages carry Snote and author footers.</p>
 </main>;
}
