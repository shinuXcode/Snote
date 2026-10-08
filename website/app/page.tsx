import Link from "next/link";
import MotionHero from "../components/MotionHero";
import Reveal from "../components/Reveal";

const features=[
  ["08","PDF workspace","Import, read, search and select PDF text; highlight, underline and strikeout text; write with pressure-aware ink; insert, rotate, crop and reorder pages."],
  ["09","Secure by design","Optional AES-256-GCM end-to-end encryption protects note payloads before local storage and cloud sync."],
  ["10","Live vector ink","Raw stylus samples stream into a separate live renderer with pressure, tilt and prediction before final commit."],
  ["11","Smart Templates","Study, Math, Lecture, Meeting, Revision and Daily layouts sit beside the core paper templates."],
  ["00","Folders","Nested folders live outside the note editor so notebooks stay organized."],
  ["05","Floating tools","Move the pen palette anywhere and snap it to an edge like a dock."],
  ["06","Secure notes","Per-note passwords stay separate from the device lock."],
  ["07","E-Ink comfort","Warm-paper, grayscale and reduced-motion reading modes."],
  ["01","Stylus engine","Pressure-aware vector strokes, velocity-based fountain ink, pencil texture and palm rejection."],
  ["02","Paper & canvas","A calm page system with lined, grid, dotted and Cornell templates plus zoomable workspaces."],
  ["03","PDF workspace","Keep annotation content separate from the source document so your handwriting remains editable."],
  ["04","One identity","The same account can carry your notes between supported Snote clients and the website portal."],
];

export default function Home(){
  return <>
    <MotionHero />
    <section className="shell">
      <div className="card accent-panel" style={{marginTop:24}}>
        <div className="eyebrow">Notification center</div>
        <h2>What’s new in Snote 1.1.0</h2>
        <p className="muted">PDF annotation, live ink controls, Smart Templates, writing gestures and optional end-to-end encryption.</p>
        <div className="row"><Link className="cta" href="/download">View 1.1.0 downloads</Link><Link className="ghost-cta" href="https://instagram.com/">Instagram</Link></div>
      </div>
    </section>
    <main className="shell">
      <section className="section">
        <Reveal>
          <div className="eyebrow">The workspace</div>
          <h2 className="title">A notebook that gets out of the way.</h2>
          <p className="lead">Inspired by the calmness of Apple Notes, the pen-first focus of Samsung Notes and the page feeling of dedicated handwriting apps.</p>
        </Reveal>
        <div className="grid">
          {features.map(([n,title,body])=><Reveal key={title}><article className="card feature-card"><span className="pill">{n}</span><h3>{title}</h3><p className="muted">{body}</p></article></Reveal>)}
        </div>
      </section>
      <section className="section split">
        <Reveal className="card accent-panel">
          <div className="eyebrow">Built for continuity</div>
          <h2 className="title">Write offline. Continue everywhere.</h2>
          <p className="muted">Local changes stay available immediately. When you sign in and reconnect, the sync queue reconciles the notebook with your account.</p>
          <Link className="cta" href="/account">Open your account</Link>
        </Reveal>
        <Reveal className="card">
          <div className="demo-page">
            <span className="demo-line demo-small" />
            <span className="demo-line" />
            <span className="demo-line demo-short" />
            <span className="demo-stroke stroke-one" />
            <span className="demo-stroke stroke-two" />
            <span className="demo-dot" />
          </div>
        </Reveal>
      </section>
    </main>
  </>;
}
