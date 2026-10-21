import type { Metadata } from "next";
import Link from "next/link";
import Reveal from "../../components/Reveal";
export const metadata: Metadata = {
 title: "Snote Features — Handwriting, Notes and Documents",
 description: "Explore Snote's stylus handwriting, digital notebooks, local-first note-taking, PDF reading, annotation, and open-source development.",
 alternates: { canonical: "https://snote-showcase.vercel.app/features" },
 keywords: ["Snote features","stylus handwriting","PDF annotation","local-first notes","digital notebook","open-source notes"],
 openGraph: { title: "Snote Features — Handwriting and PDF Tools", description: "Explore Snote handwriting, stylus input, PDF workflows, and local-first note-taking features.", url: "https://snote-showcase.vercel.app/features", type: "website", images:[{url:"/opengraph-image",width:1200,height:630,alt:"Snote note-taking features"}] },
 twitter: { card: "summary_large_image", title: "Snote Features", description: "Explore handwriting, PDF, and notebook features in Snote.", images:["/opengraph-image"] }
, other: { "article:modified_time": "2026-10-21" }};
const features = [
 ["Handwriting engine","Pressure-aware vector strokes, pen tools, and palm-rejection support where the device allows it."],
 ["Paper and canvas","Use notebook pages and flexible workspaces for different kinds of thinking."],
 ["PDF workspace","Read documents and add annotations while keeping the original document distinct from your notes."],
 ["Local-first writing","Create and edit notes without requiring a constant network connection."],
 ["Open-source foundation","Explore the source, report issues, and contribute improvements on GitHub."],
 ["Portable exports","Use available export options to keep a copy of your work outside the app."]
];
export default function FeaturesPage() {
 return <main className="shell section features-page">
  <Reveal><div className="eyebrow"><i/> THE TOOLKIT</div><h1 className="title">Tools for the way<br/><em>you think.</em></h1><p className="lead">Snote brings writing, organizing, and document workflows into one open-source workspace. Features can vary by platform and release.</p></Reveal>
  <div className="grid features-grid">{features.map(([title,body],i)=><Reveal key={title}><article className="card feature-card"><span className="feature-number">0{i+1} / SNOTE</span><h2>{title}</h2><p className="muted">{body}</p></article></Reveal>)}</div>
  <section className="feature-explainer"><h2>How does Snote support digital note-taking?</h2><p>Snote combines a writing surface with notebook organization and document workflows. The exact behavior of stylus input depends on the device, operating system, and app build, so compatibility claims should be checked against the release notes and tested on your hardware.</p><p>PDF files are useful for reading and reference, while annotations let you add your own marks alongside source material. For background on accessible content and descriptive image alternatives, consult the <a href="https://www.w3.org/WAI/tutorials/images/" target="_blank" rel="noreferrer">W3C WAI Images Tutorial</a>. For PDF document structure and accessibility, see the <a href="https://www.w3.org/WAI/standards-guidelines/" target="_blank" rel="noreferrer">W3C accessibility standards and guidelines</a>.</p><h2>Is Snote open source?</h2><p>Yes. The project source is published on <a href="https://github.com/shinuXcode/Snote" target="_blank" rel="noreferrer">GitHub</a>, where visitors can inspect code, review project documentation, and report issues. The repository is the best place to verify current implementation details instead of relying on marketing copy.</p><h2>Does every platform have the same features?</h2><p>Not necessarily. Feature availability and performance can differ by platform, device capabilities, and release version. Check the <Link href="/download">latest releases</Link> and <Link href="/docs">documentation library</Link> before depending on a particular workflow.</p></section>
  <section className="showcase-cta"><div><span className="eyebrow"><i/> MADE IN THE OPEN</span><h2>See what we're<br/><em>building next.</em></h2><p>Follow releases, report issues, or contribute to the project on GitHub.</p></div><div className="row"><a className="cta" href="https://github.com/shinuXcode/Snote" target="_blank" rel="noreferrer">Explore GitHub ↗</a><a className="ghost-cta" href="/download">Download Snote</a></div></section>
 </main>;
}
