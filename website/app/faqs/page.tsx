import type { Metadata } from "next";
const faqs = [
["What is Snotee?","Snotee is an open-source, local-first note-taking project built with Flutter, focused on handwriting, stylus input, rich text, pages, and document workflows."],
["Is Snotee open source?","Yes. Snotee is distributed under the MIT License. Read the root LICENSE file and third-party notices before redistribution."],
["Who created Snotee?","Snotee documentation credits Sadab as founder and creator."],
["Which platforms are supported?","The repository describes Android, iOS, Windows, macOS, Linux, and Web. Check the specific release assets and notes for current availability."],
["Does Snotee work offline?","Snotee is designed for local-first use. Core note-taking does not require a Snotee-hosted server or constant network access."],
["Do I need an account?","No account is required for the documented local-first workflow. The project README states that there is no mandatory Snotee account or hosted sync service."],
["Does Snotee support handwriting?","The source contains a custom canvas and ink pipeline. Exact controls and behavior vary by release and device."],
["Does it support stylus input?","The codebase includes stylus-oriented input handling, sample buffering, smoothing, prediction, and palm-rejection modules. Device hardware affects results."],
["Why does writing feel delayed?","Check the app version, device load, operating-system updates, and pen settings. Report reproducible steps and device details if the issue persists."],
["Can I organize notes into folders?","The repository includes folder and local document repository modules. Check your installed version for the available organization controls."],
["Can I import PDFs?","The project includes a PDF rendering dependency and document-related code. Import and annotation capabilities can vary by platform and release."],
["Are PDF annotations separate from the original PDF?","This depends on the particular workflow implemented in your release. Keep an original copy and verify export behavior before relying on it."],
["Where are my notes stored?","The project README describes SQLite metadata and local filesystem storage for notes."],
["Does Snotee automatically upload my notes?","No automatic upload or cross-device sync is required by the current local-first architecture. Keep backups under your control."],
["How do I back up my notes?","Use the export or backup options available in your release and keep a separate copy. Test that the backup can be opened before deleting originals."],
["What if a note opens as a blank page?","Do not immediately clear app data or uninstall. Record app version and reproduction steps, preserve available backups, restart once, and report sanitized logs."],
["What permissions does Snotee use?","File picking, image selection, camera scanning, sharing, and related features may invoke platform capabilities. The final permission set must be checked for the exact build."],
["Does Snotee need camera access?","Camera access may be needed if you use a scanning feature. It should be requested only when that feature is invoked and supported on your platform."],
["Does Snotee automatically sync notes between devices?","The current project README says automatic cross-device sync is not required. Transfer notes using a user-controlled backup workflow and verify restore compatibility."],
["How do I move notes to another device?","The README describes a user-controlled encrypted .snote backup for transfers. Verify that the backup restores correctly in your exact app version before deleting the original notes."],
["Can I contribute code?","Yes. Read the open-source guide, create a focused change, add tests, and avoid committing credentials or private note data."],
["How do I report a bug?","Use the repository issue tracker and include version, operating system, device, expected and actual results, and minimal reproduction steps. Remove secrets and personal content."],
["How do app updates work?","The website reads published release information where configured. Always check release notes and download artifacts labelled for your platform."],
["Are all platform builds signed?","Not necessarily. Signing and store requirements vary by platform. Review the exact release asset notes before installing."],
["Can Snotee guarantee privacy or security?","No software can make that blanket guarantee. Local-first design and access policies are useful controls, but device security and backend configuration still matter."],
["Where can I find guides and legal documents?","Visit the Documentation page for downloadable user, feature, open-source, privacy, permissions, license, app overview, and audit PDFs."],
["Does Snotee use AI to write or analyze notes?","Do not assume AI features are available unless they are listed in the release notes for your installed version."],
["How can I contact the project?","Use the official Snotee GitHub repository for issues and project discussions. Do not include private note content or access tokens."]
];
export const metadata: Metadata = {
 title: "Snotee FAQs: Installation & Privacy",
 description: "Answers to common questions about Snotee installation, offline use, handwriting, PDFs, backups, permissions, cloud sync, licensing, and updates.",
 alternates: { canonical: "https://snotee.vercel.app/faqs" },
 openGraph: { title: "Snotee FAQs", description: "Clear answers about using, installing, and contributing to Snotee.", url: "https://snotee.vercel.app/faqs", type: "website" }
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
