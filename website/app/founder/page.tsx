import type { Metadata } from "next";
import Link from "next/link";
export const metadata: Metadata = {
 title: "About Sadab — Creator of Snote",
 description: "Meet Sadab, the independent creator of Snote, an open-source note-taking project focused on stylus handwriting, digital notebooks, PDF reading, and local-first workflows.",
 alternates: { canonical: "https://snote-showcase.vercel.app/founder" },
 openGraph: { title: "About Sadab — Creator of Snote", description: "Meet the independent creator and learn about the principles behind the open-source Snote note-taking project.", url: "https://snote-showcase.vercel.app/founder", type: "profile", images: [{ url: "/opengraph-image", width:1200, height:630, alt: "Snote and its open-source creator" }] },
 twitter: { card: "summary_large_image", title: "About Sadab — Creator of Snote", description: "Meet the independent creator behind Snote.", images:["/opengraph-image"] }
};
export default function FounderPage() {
 return <main className="shell section founder-page">
  <div className="eyebrow"><i/> THE PERSON BEHIND THE PROJECT</div>
  <div className="founder-layout">
   <div className="founder-photo-wrap"><img className="founder-photo" src="https://images.unsplash.com/photo-1500648767791-00dcc994a43e?auto=format&fit=crop&w=1000&q=85" alt="Temporary stock portrait placeholder; replace with Sadab's own photo"/><span className="photo-note">SNOTE · FOUNDER</span><span className="founder-index">SN / FOUNDER — 001</span></div>
   <div className="founder-copy"><span className="pill">FOUNDER · OPEN-SOURCE BUILDER</span><h1 className="title">Built by <em>Sadab.</em></h1><p className="lead">Snote started with a simple belief: writing should feel natural, your notes should remain yours, and useful software should be open to everyone.</p><p className="muted">I'm building Snote as an independent, open-source project: a place for handwriting, reading PDFs, collecting ideas, and turning scattered thoughts into something useful. The goal is a calm workspace that respects the person using it.</p><div className="row founder-actions"><a className="cta" href="https://github.com/shinuXcode/Snote" target="_blank" rel="noreferrer">Follow the project <span>↗</span></a><Link className="ghost-cta" href="/download">Explore Snote</Link></div></div>
  </div>
  <section className="founder-principles"><article><span>01 / PRINCIPLE</span><h2>Fast by design.</h2><p className="muted">Writing and reading should stay responsive, even when the network is not available.</p></article><article><span>02 / PRINCIPLE</span><h2>Open by default.</h2><p className="muted">Transparent code, community feedback, and a project that can improve in public.</p></article><article><span>03 / PRINCIPLE</span><h2>Your work, your choice.</h2><p className="muted">Local-first workflows and exportable data keep the user in control.</p></article></section>
  <section className="feature-explainer"><h2>Where can I verify project details?</h2><p>Read the <Link href="/docs">Snote documentation</Link> for project guides and policy references, or inspect the <a href="https://github.com/shinuXcode/Snote" target="_blank" rel="noreferrer">source repository</a> for implementation details. Bug reports and project questions can be submitted through <a href="https://github.com/shinuXcode/Snote/issues" target="_blank" rel="noreferrer">GitHub Issues</a>.</p></section>
 </main>;
}
