import type { Metadata } from "next";
import Link from "next/link";
import Reveal from "../../components/Reveal";
export const metadata: Metadata = { title: "Snote Showcase — How It Works and Features", description: "Explore Snote's writing engine, stylus input, local-first storage, PDF workflows, and cross-platform note-taking.", alternates: { canonical: "https://snote-showcase.vercel.app/how-it-works" } };

const steps=[
 ["01","Create","Start a notebook, pick a paper template and write with a stylus or type rich text."],
 ["02","Create freely","Use strokes, images, PDFs, shapes, lasso selection and free-form pages."],
 ["03","Stay local","Your notes remain usable offline. Changes are saved locally before any cloud request."],
 ["04","Sync","When you sign in and reconnect, queued changes move to your private account space."],
 ["05","Continue","Open Snote on another supported device or use the web account portal to reach your notes and exports."]
];
const features=[
 ["Stylus engine","Pressure-aware vector strokes, velocity-based fountain ink, pencil texture and palm rejection."],
 ["Paper & canvas","Infinite-style workspace plus A4, A3, Letter and custom page templates."],
 ["PDF workspace","Keep an annotation layer independent from the original document so handwriting stays editable."],
 ["Local first","The editor writes locally before it talks to the network."],
 ["Account sync","The same Supabase identity can synchronize notes across supported Snote clients."],
 ["Export freedom","Download portable Snote JSON and keep a copy outside the app."]
];
export default function Page(){return <main className="section shell">
 <Reveal><div className="sectionHead"><span className="eyebrow">Snote showcase</span><h1 className="title">Local first.<br/><em>Cloud when useful.</em></h1><p className="lead">See how Snote fits writing, organizing, annotating documents, and continuing across devices.</p></div></Reveal>
 <div className="grid">{steps.map(([n,t,d])=><Reveal key={n}><article className="card"><span className="pill">{n}</span><h2>{t}</h2><p className="muted">{d}</p></article></Reveal>)}</div>
 <section className="section"><Reveal><div className="sectionHead"><span className="eyebrow">Features</span><h2 className="title">Designed around the act of writing.</h2><p className="lead">The interaction model takes cues from serious note apps without copying their UI.</p></div></Reveal>
  <div className="grid features-grid">{features.map(([title,body],i)=><Reveal key={title}><article className="card feature-card"><span className="pill">{String(i+1).padStart(2,"0")}</span><h3>{title}</h3><p className="muted">{body}</p></article></Reveal>)}</div>
 </section>
 <div className="card" style={{marginTop:25}}><h2>Designed around real note-taking</h2><p className="muted">Snote focuses on fast capture, clean organization, strong stylus support and an interface that does not turn every action into a settings hunt.</p><Link className="cta" href="/download">Choose your platform →</Link></div>
 </main>}
