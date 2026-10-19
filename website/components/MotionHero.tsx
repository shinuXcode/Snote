import Link from "next/link";
import SectionIndex from "./SectionIndex";

const panels = [
  { n: "01", title: "Write Freely", body: "A clean, distraction-free editor.", icon: "✳" },
  { n: "02", title: "Organize Beautifully", body: "Keep your thoughts in check.", icon: "◎" },
  { n: "03", title: "Open Source", body: "Built by the community, for everyone.", icon: "◇" },
  { n: "04", title: "Designed for Flow", body: "A seamless and intuitive experience.", icon: "⌁" },
];

function BlueprintArtwork() {
  return (
    <div className="blueprint-art" aria-label="Monochrome architectural blueprint with a rolled drawing and stylus" role="img">
      <div className="art-halo" />
      <svg className="art-orbits" viewBox="0 0 800 700" aria-hidden="true">
        <ellipse cx="420" cy="350" rx="330" ry="230" transform="rotate(-24 420 350)" />
        <ellipse cx="420" cy="350" rx="270" ry="160" transform="rotate(28 420 350)" />
        <path d="M35 535 C190 340 290 610 430 360 S680 170 770 75" />
        <path d="M95 120 L700 570 M180 50 L590 650" />
        <path d="M385 22v28m-14-14h28 M690 480v34m-17-17h34" />
        <circle cx="93" cy="530" r="4" /><circle cx="710" cy="95" r="4" /><circle cx="555" cy="590" r="3" />
      </svg>
      <div className="roll roll-back"><span /><span /><span /></div>
      <div className="blueprint-sheet">
        <div className="sheet-grid" />
        <svg className="sheet-drawing" viewBox="0 0 600 440" aria-hidden="true">
          <g fill="none" stroke="currentColor" strokeWidth=".8">
            <path d="M40 60L520 20 565 350 85 410Z M80 95L485 60 520 320 110 365Z" />
            <path d="M80 95L520 320 M485 60L110 365 M280 78L305 350 M90 220L505 190" />
            <circle cx="305" cy="220" r="90" /><circle cx="305" cy="220" r="55" />
            <path d="M215 220h180M305 130v180M245 160l120 120M365 160L245 280" />
            <rect x="120" y="125" width="92" height="58" /><rect x="390" y="245" width="88" height="54" />
            <path d="M120 115v-18m0 9h92m0 9v-18M100 125h-18m9 0v58m9 0h-18" />
            <path d="M145 205v40h65v-40z M420 100h65v40h-65z" />
            <path d="M90 390l-14 2m8-8l4 14 M540 345l14-2m-8-8l-4 14" />
          </g>
          <g fill="currentColor" fontFamily="monospace" fontSize="8" letterSpacing="2">
            <text x="40" y="40">SN / 001 — FIELD NOTES</text><text x="390" y="42">FIG. 01 / STUDY</text>
            <text x="120" y="115">AXIS A</text><text x="390" y="235">SECTION B</text>
            <text x="80" y="430">SCALE 1:24</text><text x="445" y="395">REV. 01</text>
          </g>
        </svg>
        <div className="sheet-brand"><strong>Snote</strong><span>IDEAS<br />STRUCTURED.<br />BEAUTIFULLY.</span></div>
        <div className="sheet-stamp">STUDIO / NOTE<br />SYSTEM 001</div>
      </div>
      <div className="stylus"><span className="stylus-tip" /><span className="stylus-band" /></div>
      <div className="roll roll-front"><span /><span /><span /></div>
      <div className="roll-end" />
      <div className="art-tag">IDEA<br />SKETCH<br />NOTE<br />ORGANIZE<br />CREATE</div>
      <div className="art-version"><strong>v1.0</strong><span>// OPEN SOURCE</span><span>// BUILT FOR CREATORS</span><span>// DESIGNED TO FLOW</span></div>
    </div>
  );
}

export default function MotionHero() {
  return (
    <>
      <section className="hero" id="home">
        <div className="hero-grid" aria-hidden="true" />
        <div className="blueprint-glow" aria-hidden="true" />
        <SectionIndex />
        <div className="hero-inner">
          <div className="hero-copy">
            <div className="eyebrow"><i /> YOUR IDEAS, BEAUTIFULLY ORGANIZED</div>
            <h1><span className="headline-sans">Notes for</span><em>Creators.</em></h1>
            <p>Snote is a minimal, powerful note-taking space for modern minds. Write, organize, and bring your ideas to life — beautifully.</p>
            <div className="row hero-actions">
              <Link className="cta" href="/download">Get Started <span aria-hidden="true">→</span></Link>
              <a className="ghost-cta" href="https://github.com/shinuXcode/Snote" target="_blank" rel="noreferrer"><svg className="github-mark" viewBox="0 0 24 24" aria-hidden="true"><path fill="currentColor" d="M12 .9a11.1 11.1 0 0 0-3.51 21.63c.56.1.76-.24.76-.54v-2.13c-3.1.68-3.75-1.31-3.75-1.31-.5-1.29-1.24-1.63-1.24-1.63-1.02-.7.08-.69.08-.69 1.13.08 1.73 1.16 1.73 1.16 1 .1.78 2.1 3.16 1.5.1-.72.4-1.2.7-1.48-2.48-.28-5.08-1.24-5.08-5.52 0-1.22.44-2.22 1.16-3-.12-.29-.5-1.42.11-2.96 0 0 .95-.3 3.05 1.15a10.6 10.6 0 0 1 5.55 0c2.1-1.43 3.05-1.15 3.05-1.15.61 1.54.23 2.67.11 2.96.72.78 1.16 1.78 1.16 3 0 4.3-2.6 5.24-5.1 5.51.4.35.75 1.02.75 2.06v3.06c0 .3.2.65.77.54A11.1 11.1 0 0 0 12 .9Z"/></svg> View on GitHub</a>
            </div>
            <div className="hero-ribbon"><span><b>ϟ</b> Fast</span><span><b>◇</b> Open Source</span><span><b>▣</b> Privacy First</span></div>
          </div>
          <BlueprintArtwork />
        </div>
      </section>
      <section className="blueprint-roll" id="blueprint-roll" aria-label="Snote highlights">
        <div className="roll-metal roll-metal-left" />
        {panels.map((panel) => <Link href="/features" className="roll-panel" key={panel.n}>
          <span className="panel-number">{panel.n}</span><span className="panel-glyph" aria-hidden="true">{panel.icon}</span>
          <span className="panel-copy"><strong>{panel.title}</strong><small>{panel.body}</small></span>
          <span className="panel-arrow" aria-hidden="true">↗</span>
        </Link>)}
        <div className="roll-metal roll-metal-right" />
      </section>
      <main className="shell">
        <section className="section feature-intro" id="features">
          <div><div className="eyebrow"><i /> FEATURES</div><h2 className="title">Designed for<br /><em>Modern Thinkers.</em></h2></div>
          <p className="lead">Everything you need to capture, organize, and grow your ideas — in one beautifully minimal workspace.</p>
          <Link className="see-features" href="/features">See All Features <span aria-hidden="true">→</span></Link>
        </section>
        <div className="grid feature-grid">
          {[
            ["✎","Minimal Editor","A quiet writing surface that keeps your attention on the page."],
            ["⬡","Smart Organization","Folders, templates and tools that keep thoughts in order."],
            ["↗","Open & Extendable","Open-source foundations built to grow with your workflow."],
            ["☼","Beautiful by Default","Thoughtful details, calm surfaces and a distraction-free feel."]
          ].map(([icon,title,body], i) => <article className="card feature-card" key={title}>
            <span className="feature-icon">{icon}<i /></span><span className="feature-number">0{i+1} / SYSTEM</span><h3>{title}</h3><p className="muted">{body}</p><span className="card-cross" aria-hidden="true">+</span>
          </article>)}
        </div>
        <section className="section lower-section" id="lower-section">
          <div className="eyebrow"><i /> BUILT FOR CONTINUITY</div><h2 className="title">Your notes. Your space.</h2>
          <p className="lead">Write offline, keep ownership of your work, and continue across supported Snote clients.</p>
          <div className="row hero-actions"><Link className="cta" href="/download">Explore Snote →</Link><Link className="ghost-cta" href="/account">Open your account</Link></div>
        </section>
      </main>
    </>
  );
}
