import type { Metadata } from "next";
import Reveal from "../../components/Reveal";
export const metadata: Metadata = { title: "Snotee Features — Handwriting, Notes and Documents", description: "Explore Snotee's handwriting engine, stylus input, local-first storage, organization, and document workflows.", alternates: { canonical: "https://snotee.vercel.app/features" } };
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
  <Reveal><div className="eyebrow"><i/> THE TOOLKIT</div><h1 className="title">Tools for the way<br/><em>you think.</em></h1><p className="lead">Snotee brings writing, organizing, and document workflows into one open-source workspace. Features can vary by platform and release.</p></Reveal>
  <div className="grid features-grid">{features.map(([title,body],i)=><Reveal key={title}><article className="card feature-card"><span className="feature-number">0{i+1} / SNOTE</span><h2>{title}</h2><p className="muted">{body}</p></article></Reveal>)}</div>
  <section className="showcase-cta"><div><span className="eyebrow"><i/> MADE IN THE OPEN</span><h2>See what we're<br/><em>building next.</em></h2><p>Follow releases, report issues, or contribute to the project on GitHub.</p></div><div className="row"><a className="cta" href="https://github.com/shinuXcode/Snotee" target="_blank" rel="noreferrer">Explore GitHub ↗</a><a className="ghost-cta" href="/download">Download Snotee</a></div></section>
 </main>;
}