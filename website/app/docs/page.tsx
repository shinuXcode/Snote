import Link from "next/link";
import type { Metadata } from "next";

export const metadata: Metadata = {
 title: "Snote Documentation — User Guides, Licenses and Policies",
 description: "Read online or download Snote user guides, feature catalogue, open-source documentation, privacy and data handling, permissions, license notices, app overview, SDK reference, and repository audit.",
 alternates: { canonical: "https://snote-showcase.vercel.app/docs" },
 keywords: ["Snote documentation","Snote user guide","Snote privacy","Snote open source","Snote PDF guides"],
 twitter: { card: "summary_large_image", title: "Snote Documentation", description: "User guides, policies, technical references, and project documentation.", images: ["/og-image.svg"] },
 openGraph: { title: "Snote Documentation", description: "Read online or download guides, project documentation, policies, and PDF references for Snote.", url: "https://snote-showcase.vercel.app/docs", type: "website", images: [{ url: "/og-image.svg", width: 1200, height: 630, alt: "Snote documentation library" }] },
 other: { "article:modified_time": "2026-10-21" }
};

const docs = [
 ["01","App Overview","Product overview, platform support, and upgrade guidance.","app-overview.pdf"],
 ["02","Feature Catalogue","Snote features, handwriting, storage, and platform notes.","features.pdf"],
 ["03","Notifications Admin","Notification behavior and administration reference.","notifications-admin.pdf"],
 ["04","Open Source Guide","Repository structure, development, contributions, CI, and releases.","open-source.pdf"],
 ["05","Permissions & Authorization","File access, permissions, and authorization reference.","permissions.pdf"],
 ["06","License & Third-party Notices","License terms and third-party notices.","license.pdf"],
 ["07","SDKs & Toolchains","SDKs, dependencies, and platform build requirements.","sdks.pdf"],
 ["08","Terms of Use","Usage terms, content, backups, and service disclaimers.","terms.pdf"],
 ["09","Repository Audit","Repository findings and verification checklist.","repository-audit.pdf"]
] as const;

export default function DocsPage() {
 return <main className="shell section docs-page">
  <div className="eyebrow"><i/> DOCUMENTATION LIBRARY</div>
  <h1 className="title">Everything about Snote.<br/><em>In one place.</em></h1>
  <p className="lead">Read the original Snote PDFs directly in your browser or download them for offline reference.</p>
  <div className="docs-callout card">
   <div><span className="pill">START HERE</span><h2>New to Snote?</h2><p className="muted">Start with the app overview, then explore the feature and repository documentation.</p></div>
   <div className="docs-actions"><a className="cta" href="/docs/app-overview.pdf" target="_blank" rel="noreferrer">Read app overview <span aria-hidden="true">↗</span></a><a className="docs-download" href="/docs/app-overview.pdf" download>Download PDF <span aria-hidden="true">↓</span></a></div>
  </div>
  <div className="docs-library-heading"><div><span className="pill">9 DOCUMENTS</span><h2>Documentation library</h2></div><p className="muted">Each item is available as a browser-viewable PDF and a downloadable copy.</p></div>
  <div className="grid docs-grid">{docs.map(([n,title,body,slug])=><article className="card docs-card" key={slug}>
   <span className="feature-number">{n} / PDF</span><h2>{title}</h2><p className="muted">{body}</p>
   <div className="docs-actions"><a className="docs-view" href={"/docs/"+slug} target="_blank" rel="noreferrer">Read online <span aria-hidden="true">↗</span></a><a className="docs-download" href={"/docs/"+slug} download>Download PDF <span aria-hidden="true">↓</span></a></div>
  </article>)}</div>
  <section className="docs-faq card"><div><span className="pill">HELP CENTRE</span><h2>Frequently asked questions</h2><p className="muted">Quick answers about installation, stylus input, privacy, cloud sync, permissions, SDKs, and releases.</p></div><Link className="cta" href="/faqs">Explore all 28 FAQs <span aria-hidden="true">→</span></Link></section>
  <section className="card source-note"><h2>Official references</h2><p className="muted">For authoritative project details, compare these documents with the published repository and license. The PDFs on this page are project documentation and should not be treated as a substitute for a security review or legal advice.</p><ul><li><a href="https://github.com/shinuXcode/Snote" target="_blank" rel="noreferrer">Snote source repository</a> — code, releases, and issue history.</li><li><a href="https://github.com/shinuXcode/Snote/blob/main/LICENSE" target="_blank" rel="noreferrer">Published license</a> — license text in the repository.</li></ul></section>
  <p className="docs-note">Legal and security documents are informational and do not replace legal advice, platform-specific permission review, or a production security audit. Features can vary by version. PDF covers credit Sadab as founder/creator; interior pages carry Snote and author footers.</p>
 </main>;
}
