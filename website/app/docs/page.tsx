import Link from "next/link";
import type { Metadata } from "next";

export const metadata: Metadata = {
 title: "Snote Documentation — Guides, Licenses and Policies",
 description: "Read Snote user guides, feature documentation, privacy and permissions references, licenses, SDK notes, and repository audit PDFs online.",
 alternates: { canonical: "https://snote-showcase.vercel.app/docs" },
 keywords: ["Snote documentation","Snote user guide","Snote privacy","Snote open source","Snote PDF guides"],
 twitter: { card: "summary_large_image", title: "Snote Documentation", description: "User guides, policies, technical references, and project documentation.", images:["/opengraph-image"] },
 openGraph: { title: "Snote Documentation", description: "Read Snote user guides, technical references, policies, and PDF documentation.", url: "https://snote-showcase.vercel.app/docs", type: "website", images:[{url:"/opengraph-image",width:1200,height:630,alt:"Snote documentation library"}] }
, other: { "article:modified_time": "2026-10-21" }};

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
  <p className="lead">Read the original Snote PDFs directly in your browser or download them for offline reference. Check the release notes if you need documentation for a specific app version.</p>
  <div className="docs-callout card">
   <div><span className="pill">START HERE</span><h2>New to Snote?</h2><p className="muted">Start with the app overview, then explore the feature and repository documentation.</p></div>
   <div className="docs-actions"><a className="cta" href="/docs/app-overview.pdf" target="_blank" rel="noreferrer">Read app overview <span aria-hidden="true">↗</span></a><a className="docs-download" href="/docs/app-overview.pdf" download>Download PDF <span aria-hidden="true">↓</span></a></div>
  </div>
  <div className="docs-library-heading"><div><span className="pill">9 DOCUMENTS</span><h2>Documentation library</h2></div><p className="muted">Each item is available as a browser-viewable PDF and a downloadable copy.</p></div>
  <div className="grid docs-grid">{docs.map(([n,title,body,slug])=><article className="card docs-card" key={slug}>
   <span className="feature-number">{n} / PDF</span><h2>{title}</h2><p className="muted">{body}</p>
   <div className="docs-actions"><a className="docs-view" href={"/docs/"+slug} target="_blank" rel="noreferrer">Read online <span aria-hidden="true">↗</span></a><a className="docs-download" href={"/docs/"+slug} download>Download PDF <span aria-hidden="true">↓</span></a></div>
  </article>)}</div>
  <section className="docs-faq card"><div><span className="pill">HELP CENTRE</span><h2>Where can I find more answers?</h2><p className="muted">Find answers about installation, stylus input, privacy, cloud sync, permissions, SDKs, and releases.</p></div><Link className="cta" href="/faqs">Explore all 28 FAQs <span aria-hidden="true">→</span></Link></section>
  <section className="docs-note"><h2>How should I use these documents?</h2><p>Use the app overview for orientation, the feature catalogue for a summary of workflows, and the permissions and privacy references when reviewing data access. Check the repository and release notes for version-specific implementation details. Legal and security documents are informational and do not replace legal advice, platform-specific permission review, or a production security audit.</p><p>For accessibility guidance on informative images and text alternatives, see the <a href="https://www.w3.org/WAI/tutorials/images/" target="_blank" rel="noreferrer">W3C WAI Images Tutorial</a>. For source code and current project history, visit the <a href="https://github.com/shinuXcode/Snote" target="_blank" rel="noreferrer">Snote repository</a>.</p></section>
 </main>;
}
