import type { Metadata } from "next";
const faqs = [
["What is Snote?","Snote is an open-source, local-first note-taking project built with Flutter, focused on handwriting, stylus input, rich text, pages, and document workflows."],
["Is Snote open source?","Yes. The repository README states that the project uses the MIT License. Review the LICENSE file and third-party notices before redistribution."],
["Who created Snote?","Snote documentation credits Sadab as founder and creator."],
["Which platforms are supported?","The repository describes Android, iOS, Windows, macOS, Linux, and Web. Check the specific release assets and notes for current availability."],
["Does Snote work offline?","Snote is designed for local-first use. Optional cloud features require appropriate configuration and connectivity."],
["Do I need an account?","Local-first functionality is intended to work without a required cloud account. Account and cloud behavior depends on the build and configuration."],
["Does Snote support handwriting?","The source contains a custom canvas and ink pipeline. Exact controls and behavior vary by release and device."],
["Does it support stylus input?","The codebase includes stylus-oriented input handling, sample buffering, smoothing, prediction, and palm-rejection modules. Device hardware affects results."],
["Why does writing feel delayed?","Check the app version, device load, operating-system updates, and pen settings. Report reproducible steps and device details if the issue persists."],
["Can I organize notes into folders?","The repository includes folder and local document repository modules. Check your installed version for the available organization controls."],
["Can I import PDFs?","The project includes a PDF rendering dependency and document-related code. Import and annotation capabilities can vary by platform and release."],
["Are PDF annotations separate from the original PDF?","This depends on the particular workflow implemented in your release. Keep an original copy and verify export behavior before relying on it."],
["Where are my notes stored?","Local-first data may be stored on the device using SQLite and filesystem-backed storage. Cloud-enabled workflows may also use the configured Supabase project."],
["Does Snote automatically upload my notes?","Cloud behavior depends on whether cloud features are configured and used. Review the privacy documentation and your installation's account/sync settings."],
["How do I back up my notes?","Use the export or backup options available in your release and keep a separate copy. Test that the backup can be opened before deleting originals."],
["What if a note opens as a blank page?","Do not immediately clear app data or uninstall. Record app version and reproduction steps, preserve available backups, restart once, and report sanitized logs."],
["What permissions does Snote use?","File picking, image selection, camera scanning, sharing, and related features may invoke platform capabilities. The final permission set must be checked for the exact build."],
["Does Snote need camera access?","Camera access may be needed if you use a scanning feature. It should be requested only when that feature is invoked and supported on your platform."],
["Is cloud sync enabled by default?","Cloud support is optional in the architecture and requires configuration. Behavior depends on the build and deployment settings."],
["How is cloud data protected?","The repository includes Supabase migrations with row-level security for core tables. This does not replace a full deployment security review or guarantee that every endpoint is correctly configured."],
["Can I contribute code?","Yes. Read the open-source guide, create a focused change, add tests, and avoid committing credentials or private note data."],
["How do I report a bug?","Use the repository issue tracker and include version, operating system, device, expected and actual results, and minimal reproduction steps. Remove secrets and personal content."],
["How do app updates work?","The website reads published release information where configured. Always check release notes and download artifacts labelled for your platform."],
["Are all platform builds signed?","Not necessarily. Signing and store requirements vary by platform. Review the exact release asset notes before installing."],
["Can Snote guarantee privacy or security?","No software can make that blanket guarantee. Local-first design and access policies are useful controls, but device security and backend configuration still matter."],
["Where can I find guides and legal documents?","Visit the Documentation page for downloadable user, feature, open-source, privacy, permissions, license, app overview, and audit PDFs."],
["Does Snote use AI to write or analyze notes?","Do not assume AI features are available unless they are listed in the release notes for your installed version."],
["How can I contact the project?","Use the official Snote GitHub repository for issues and project discussions. Do not include private note content or access tokens."]
];
export const metadata: Metadata = {
 title: "Snote FAQs — Installation, Writing, Privacy and Updates",
 description: "Answers to common questions about Snote installation, offline use, handwriting, PDFs, backups, permissions, cloud sync, licensing, and updates.",
 alternates: { canonical: "https://snote-showcase.vercel.app/faqs" },
 keywords: ["Snote FAQ","Snote offline","Snote handwriting","Snote PDF annotation","Snote privacy","Snote troubleshooting"],
 openGraph: { title: "Snote FAQs — Answers and Troubleshooting", description: "Answers about Snote installation, handwriting, PDFs, privacy, backups, and releases.", url: "https://snote-showcase.vercel.app/faqs", type: "website" },
 twitter: { card: "summary", title: "Snote FAQs", description: "Answers about installing, using, and troubleshooting Snote." },
};
const schema = { "@context":"https://schema.org", "@type":"FAQPage", mainEntity: faqs.map(([q,a])=>({ "@type":"Question", name:q, acceptedAnswer:{ "@type":"Answer", text:a } })) };
export default function FaqPage() {
 return <main className="shell section docs-page faq-page">
  <script type="application/ld+json" dangerouslySetInnerHTML={{__html:JSON.stringify(schema)}} />
  <div className="eyebrow"><i/> HELP CENTRE</div>
  <h1 className="title">Questions, <em>answered.</em></h1>
  <p className="lead">Practical answers about installation, writing, data, permissions, releases, and contributing. Details can vary by version and platform.</p>
  <div className="faq-list">{faqs.map(([q,a],i)=><details className="card faq-item" key={q}><summary><span className="feature-number">{String(i+1).padStart(2,"0")}</span><strong>{q}</strong><span className="faq-plus" aria-hidden="true">+</span></summary><p className="muted">{a}</p></details>)}</div>
 </main>;
}
