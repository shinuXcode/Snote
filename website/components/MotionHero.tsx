import Link from "next/link";
import Icon from "./Icon";

const features = [
 ["pen","Natural handwriting","A writing surface designed around pen input, quick capture, and staying in flow."],
 ["organize","Notes that make sense","Keep pages, ideas, and reference material together instead of scattered across apps."],
 ["open","Open-source by nature","Follow development, inspect the code, and help shape the next version."],
 ["flow","PDFs and paper","Read, annotate, and build a workflow around the documents you already use."]
];
const steps = [
 ["01","Capture the thought","Open a blank page or bring a document into your workspace."],
 ["02","Work your way","Write with a stylus, type, sketch, and shape ideas into something clear."],
 ["03","Keep what matters","Organize your notes and use available export options to keep control of your work."]
];
function WorkspacePreview() {
 return <div className="workspace-preview" aria-label="Illustration of the Snote writing workspace">
  <div className="preview-window"><div className="preview-window-top"><span className="window-dots"><i/><i/><i/></span><span>Biology / Cell structure</span><span className="preview-status">SAVED</span></div>
   <div className="preview-body"><aside className="preview-rail"><span>⌂</span><span>▤</span><span>✎</span><span>＋</span></aside><div className="preview-paper"><div className="preview-paper-meta">STUDY NOTES · 04</div><h3>Cell structure<br/><em>& function</em></h3><p>Every cell is a small system, built from parts that work together.</p><div className="cell-diagram"><div className="cell-core"><span/></div><div className="diagram-label label-one">NUCLEUS</div><div className="diagram-label label-two">CELL MEMBRANE</div><svg viewBox="0 0 300 90" aria-hidden="true"><path d="M10 55 C30 20 45 80 65 48 S105 22 124 55 165 80 188 45 225 18 245 48 275 60 290 28" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round"/></svg></div><div className="preview-lines"><i/><i/><i/></div></div></div>
  </div><div className="preview-tool-float"><span>✎</span><span>⌁</span><span>◯</span><span>▱</span><i/><span className="preview-ink"/></div><div className="preview-sticker sticker-top">PEN · 0.5</div><div className="preview-sticker sticker-bottom"><Icon name="check" size={13}/> SAVED LOCALLY</div>
 </div>;
}
export default function MotionHero() {
 return <>
  <main>
   <section className="hero" id="home"><div className="hero-inner shell"><div className="hero-copy"><div className="eyebrow"><i/> OPEN-SOURCE NOTE-TAKING</div><h1>Make space<br/>for <em>thinking.</em></h1><p>Snote brings handwriting, documents, and everyday ideas into one calm workspace. Made for people who think on paper — and everywhere else.</p><div className="row hero-actions"><Link className="cta" href="/download">Download Snote <Icon name="arrow" size={16}/></Link><a className="ghost-cta" href="https://github.com/shinuXcode/Snote" target="_blank" rel="noreferrer"><Icon name="github" size={16}/> Explore the source</a></div><div className="hero-proof"><span><Icon name="check" size={14}/> Open source</span><span><Icon name="check" size={14}/> Offline-friendly</span><span><Icon name="check" size={14}/> Built for stylus</span></div></div><WorkspacePreview/></div><div className="hero-bottom shell"><span>DESIGNED FOR THE WAY YOU THINK</span><span>SN / 001 — NOTE SYSTEM</span></div></section>
   <section className="intro-strip shell"><span className="intro-label">MEET YOUR NEW<br/>THINKING SPACE</span><p>Less interface to fight. More room for ideas to become something.</p><Link className="text-link" href="/how-it-works">See how it works <span>↗</span></Link></section>
   <section className="section shell home-features"><div className="section-intro"><div><div className="eyebrow"><i/> MADE FOR THE DETAILS</div><h2 className="title">Your thoughts,<br/><em>without the friction.</em></h2></div><p className="lead">From quick notes to long study sessions, Snote is built to help you capture an idea before it disappears.</p></div><div className="home-feature-grid">{features.map(([icon,title,body],i)=><article className="home-feature-card" key={title}><div className="feature-card-top"><span className="feature-icon"><Icon name={icon as "pen"|"organize"|"open"|"flow"} size={21}/></span><span>0{i+1} / 04</span></div><h3>{title}</h3><p>{body}</p><span className="feature-card-line"/></article>)}</div><div className="section-link-row"><span>THE SNOTE TOOLKIT</span><Link className="text-link" href="/features">Explore all features <span>↗</span></Link></div></section>
   <section className="workflow-section"><div className="shell workflow-inner"><div className="workflow-heading"><div className="eyebrow"><i/> A SIMPLE WORKFLOW</div><h2 className="title">From first mark<br/><em>to finished thought.</em></h2><p className="muted">Your process stays yours. Snote gives your ideas a place to land, grow, and connect.</p></div><div className="workflow-steps">{steps.map(([n,title,body])=><article key={n}><span>{n}</span><div><h3>{title}</h3><p>{body}</p></div><Icon name="arrow" size={18}/></article>)}</div></div></section>
   <section className="shell founder-teaser"><div className="founder-teaser-art"><div className="teaser-paper"><span>THE IDEA</span><strong>Build tools<br/>that get out<br/>of the way.</strong><i>— Snote principles</i></div><div className="teaser-number">SN / NOTEBOOK 001</div></div><div className="founder-teaser-copy"><div className="eyebrow"><i/> BUILT IN THE OPEN</div><h2 className="title">A small project<br/>with <em>big intent.</em></h2><p className="lead">Snote is built by Sadab as an independent open-source project — with a focus on useful tools, thoughtful details, and software that respects your work.</p><Link className="text-link" href="/founder">Meet the founder <span>↗</span></Link></div></section>
   <section className="shell home-cta"><div><div className="eyebrow"><i/> YOUR NEXT IDEA STARTS HERE</div><h2>Ready to make<br/><em>room for it?</em></h2><p>Try the latest build, read the docs, or help improve Snote in public.</p></div><div className="home-cta-actions"><Link className="cta" href="/download">Get Snote <Icon name="arrow" size={16}/></Link><Link className="ghost-cta" href="/docs">Read the docs</Link></div></section>
  </main>
 </>;
}
