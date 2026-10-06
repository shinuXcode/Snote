import Link from "next/link";

export default function MotionHero() {
  return (
    <section className="hero">
      <div className="orb orb-a" />
      <div className="orb orb-b" />
      <div className="hero-grid" />
      <div className="shell hero-content">
        <img className="hero-logo hero-logo-float" src="/snote-logo.svg" alt="" />
        <div className="hero-copy hero-copy-in">
          <div className="eyebrow">Open source · offline first · cross platform</div>
          <h1>
            Write
            <br />
            <span>without limits.</span>
          </h1>
          <p>
            A calm handwriting workspace for stylus, rich text, PDFs and ideas —
            designed around ownership, speed and continuity.
          </p>
          <div className="row hero-actions">
            <Link className="cta" href="/download">Get Snote</Link>
            <Link className="ghost-cta" href="/features">Explore features</Link>
          </div>
        </div>
        <div className="hero-ribbon">
          {["Vector ink", "Paper templates", "PDF layers", "Cloud identity", "Local first"].map((item) => (
            <span key={item}>{item}</span>
          ))}
        </div>
      </div>
    </section>
  );
}
