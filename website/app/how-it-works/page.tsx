import type { Metadata } from "next";
import Link from "next/link";
import Reveal from "../../components/Reveal";
export const metadata: Metadata = { title: "Snotee Showcase — A notebook built for thinking", description: "Explore Snotee's handwriting, stylus input, local-first storage, PDF annotation, and note-taking workflows.", alternates: { canonical: "https://snotee.vercel.app/how-it-works" } };
const steps = [
 ["01","Capture","Start with a blank page, a paper template, or a PDF. Write by hand or type your thoughts."],
 ["02","Make it yours","Use stylus tools, rich text, shapes, images, lasso selection, and page layouts to express ideas."],
 ["03","Keep your flow","Snotee is designed around a responsive writing surface and an interface that stays out of the way."],
 ["04","Stay in control","Keep working offline and export your notes in portable formats. Available sync features depend on the app version."],
];
const features = [
 ["Natural handwriting","Pressure-aware strokes, pen tools, and palm-rejection support where the device allows it."],
 ["Paper and canvas","Use notebook pages and flexible workspaces for different kinds of thinking."],
 ["PDF annotation","Read documents and add annotations while keeping the original file distinct from your notes."],
 ["Local-first workflows","Create and edit notes without requiring a constant network connection."],
 ["Open-source foundation","Explore the source, report issues, and contribute improvements on GitHub."],
 ["Portable work","Keep a copy of your work with the available export options."],
];
export default function ShowcasePage() { return <main className="shell section showcase-page">
 <Reveal><div className="eyebrow"><i/> A CLOSER LOOK AT SNOTE</div><h1 className="title">A little less friction.<br/><em>A lot more thinking.</em></h1><p className="lead">From the first stroke to the final annotation, Snotee is being built to make digital note-taking feel more natural.</p></Reveal>
 <section className="showcase-feature"><div className="showcase-copy"><span className="pill">THE WORKSPACE</span><h2>One place for<br/><em>all your thinking.</em></h2><p className="muted">Handwritten notes, typed ideas, sketches, and documents belong in the same workspace. Snotee brings these tools together without making the interface the main event.</p><Link className="text-link" href="/features">Explore the features <span>↗</span></Link></div><div className="workspace-art" aria-label="Illustration of a Snotee notebook workspace"><div className="workspace-toolbar"><span>○</span><span>✎</span><span>⌁</span><span>□</span><i/></div><div className="workspace-paper"><small>FIELD NOTES / 001</small><h3>Ideas begin<br/>with a mark.</h3><svg viewBox="0 0 420 130" aria-hidden="true"><path d="M8 80 C35 10 60 120 93 60 S150 25 177 75 230 112 255 55 315 10 345 60 390 80 410 30" fill="none" stroke="currentColor" strokeWidth="2.4" strokeLinecap="round"/><path d="M15 110 Q85 88 130 108 T240 105 T400 96" fill="none" stroke="currentColor" strokeWidth="1" opacity=".35"/></svg><div className="workspace-lines"><i/><i/><i/><i/></div><span className="paper-page">01 / 12</span></div><div className="workspace-float">PEN · 0.5 mm <span>●</span></div></div></section>
 <section className="process-section"><div className="section-intro"><span className="eyebrow"><i/> THE FLOW</span><h2 className="title">From blank page<br/><em>to clear thinking.</em></h2></div><div className="process-grid">{steps.map(([n,title,body])=><article className="process-card" key={n}><span className="process-number">{n}</span><h3>{title}</h3><p className="muted">{body}</p></article>)}</div></section>
 <section className="feature-showcase"><div className="section-intro"><span className="eyebrow"><i/> MADE FOR REAL WORK</span><h2 className="title">Tools that feel<br/><em>like they belong.</em></h2></div><div className="grid features-grid">{features.map(([title,body],i)=><Reveal key={title}><article className="card feature-card"><span className="feature-number">0{i+1} / SNOTE</span><h3>{title}</h3><p className="muted">{body}</p></article></Reveal>)}</div></section>
 <section className="showcase-cta"><div><span className="eyebrow"><i/> READY WHEN YOU ARE</span><h2>Make space for<br/><em>your next idea.</em></h2><p>Explore the latest build, read the docs, or help shape the project.</p></div><div className="row"><Link className="cta" href="/download">Download Snotee <span>↗</span></Link><a className="ghost-cta" href="https://github.com/shinuXcode/Snotee" target="_blank" rel="noreferrer">View source <span>↗</span></a></div></section>
 </main>; }
