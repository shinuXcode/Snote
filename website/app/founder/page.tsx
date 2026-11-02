import type { Metadata } from "next";
import Link from "next/link";
export const metadata: Metadata = { title: "About Sadab — Snotee Founder", description: "Meet Sadab, founder and creator of Snotee, an open-source note-taking project.", alternates: { canonical: "https://snotee-showcase.vercel.app/founder" } };
export default function FounderPage() {
 return <main className="shell section founder-page">
  <div className="eyebrow"><i/> THE PERSON BEHIND THE PROJECT</div>
  <div className="founder-layout">
   <div className="founder-photo-wrap"><img className="founder-photo founder-logo-placeholder" src="/snote-logo.png" alt="Snotee logo in the founder image placeholder" /><span className="photo-note">SNOTE / OPEN-SOURCE PROJECT</span><span className="founder-index">SN / FOUNDER — 001</span></div>
   <div className="founder-copy"><span className="pill">FOUNDER · OPEN-SOURCE BUILDER</span><h1 className="title">Built by <em>Sadab.</em></h1><p className="lead">Snotee started with a simple belief: writing should feel natural, your notes should remain yours, and useful software should be open to everyone.</p><p className="muted">I'm building Snotee as an independent, open-source project: a place for handwriting, reading PDFs, collecting ideas, and turning scattered thoughts into something useful. The goal is a calm workspace that respects the person using it.</p><div className="row founder-actions"><a className="cta" href="https://github.com/shinuXcode/Snotee" target="_blank" rel="noreferrer">Follow the project <span>↗</span></a><Link className="ghost-cta" href="/download">Explore Snotee</Link></div></div>
  </div>
  <section className="founder-principles"><article><span>01 / PRINCIPLE</span><h2>Fast by design.</h2><p className="muted">Writing and reading should stay responsive, even when the network is not available.</p></article><article><span>02 / PRINCIPLE</span><h2>Open by default.</h2><p className="muted">Transparent code, community feedback, and a project that can improve in public.</p></article><article><span>03 / PRINCIPLE</span><h2>Your work, your choice.</h2><p className="muted">Local-first workflows and exportable data keep the user in control.</p></article></section>
 </main>;
}
