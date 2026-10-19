import Link from "next/link";
const guides = [
 ["01","Getting started","Install Snote, create your first notebook, and learn the workspace."],
 ["02","Writing and drawing","Choose a pen, tune ink settings, and work with stylus input."],
 ["03","Pages and paper","Pick paper templates, add pages, and navigate a notebook."],
 ["04","PDF annotation","Import PDFs and keep annotations separate from the original document."],
 ["05","Organizing notes","Build a system with notebooks, folders, search, and naming."],
 ["06","Backup and privacy","Understand local storage, exports, and optional connected sync."],
 ["07","Accessibility","Use keyboard focus and reduced-motion preferences where supported."],
 ["08","Troubleshooting","Find help for blank pages, stylus issues, downloads, and installation."]
];
export default function DocsPage(){return <main className="shell section docs-page"><div className="eyebrow"><i/> DOCUMENTATION</div><h1 className="title">A clear path from<br/><em>first note to flow.</em></h1><p className="lead">Guides for getting started, writing, organizing, annotating PDFs, and keeping your work safe. Details can vary by platform and release.</p><div className="docs-callout card"><div><span className="pill">START HERE</span><h2>New to Snote?</h2><p className="muted">Start with the basics, then explore the tools that fit your workflow.</p></div><Link className="cta" href="/download">Get Snote →</Link></div><div className="grid docs-grid">{guides.map(([n,title,body])=><article className="card docs-card" key={n}><span className="feature-number">{n} / GUIDE</span><h2>{title}</h2><p className="muted">{body}</p><span className="docs-arrow">↗</span></article>)}</div><p className="docs-note">If a feature is missing in your installed version, check the release notes before troubleshooting.</p></main>}
