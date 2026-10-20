import feed from "../../data/notifications.json";

type Notice = {
  id: string;
  number: number;
  type: "banner" | "text" | "card" | "release";
  status: "published" | "draft";
  category: string;
  title: string;
  text: string;
  date?: string;
  version?: string;
  platform?: string;
  actionLabel?: string;
  actionUrl?: string;
};

const notices = (feed.notifications as Notice[])
  .filter((notice) => notice.status === "published")
  .sort((a, b) => a.number - b.number);

function safeHref(value?: string) {
  if (!value) return null;
  try {
    const url = new URL(value);
    return url.protocol === "https:" ? url.toString() : null;
  } catch {
    return null;
  }
}

export default function NotificationsPage() {
  return (
    <main style={{ maxWidth: 1040, margin: "0 auto", padding: "150px 24px 100px", minHeight: "70vh" }}>
      <div style={{ fontSize: 11, letterSpacing: ".24em", color: "#d0d6e5", textTransform: "uppercase" }}>SNOTE / UPDATES</div>
      <h1 style={{ fontSize: "clamp(40px,7vw,76px)", lineHeight: 1, letterSpacing: "-.06em", margin: "20px 0" }}>
        Notification centre<span style={{ color: "#999" }}>.</span>
      </h1>
      <p style={{ color: "#d0d5df", maxWidth: 640, lineHeight: 1.7 }}>
        Announcements, feature updates, maintenance notices and releases, published in sequence from the project notification feed.
      </p>
      {notices.length === 0 ? (
        <section style={panel}><h2>No announcements yet</h2><p style={muted}>Check back when the next Snote update is published.</p></section>
      ) : (
        <div style={{ display: "grid", gap: 14, marginTop: 34 }}>
          {notices.map((n) => {
            const href = safeHref(n.actionUrl);
            const meta = <div style={{ display: "flex", gap: 10, flexWrap: "wrap", alignItems: "center", color: "#596174", fontSize: 12 }}>
              <span style={tag}>#{String(n.number).padStart(3, "0")}</span><span style={tag}>{n.category}</span>{n.date && <time dateTime={n.date}>{n.date}</time>}
            </div>;
            if (n.type === "banner") return <article key={n.id} style={{ ...panel, background: "#e8edff", color: "#101321", borderColor: "#cbd4ff" }}>
              {meta}<h2 style={{ fontSize: 23, margin: "14px 0 8px" }}>{n.title}</h2><p style={{ lineHeight: 1.7, margin: 0 }}>{n.text}</p>
              {href && <a href={href} style={link}>{n.actionLabel || "Learn more"} ↗</a>}
            </article>;
            if (n.type === "release") return <article key={n.id} style={{ ...panel, borderColor: "#ffffff35" }}>
              {meta}<div style={{ display: "flex", gap: 12, alignItems: "center", flexWrap: "wrap", marginTop: 14 }}><span style={{ fontSize: 11, letterSpacing: ".16em", color: "#aaa" }}>RELEASE</span>{n.version && <span style={tag}>v{n.version}</span>}{n.platform && <span style={tag}>{n.platform}</span>}</div>
              <h2 style={{ fontSize: 25, margin: "12px 0 8px" }}>{n.title}</h2><p style={body}>{n.text}</p>
              {href && <a href={href} style={link}>{n.actionLabel || "View release"} ↗</a>}
            </article>;
            if (n.type === "card") return <article key={n.id} style={{ ...panel, background: "linear-gradient(135deg,#ffffff0b,#ffffff03)" }}>
              {meta}<h2 style={{ fontSize: 23, margin: "14px 0 8px" }}>{n.title}</h2><p style={body}>{n.text}</p>
              {href && <a href={href} style={link}>{n.actionLabel || "Read more"} ↗</a>}
            </article>;
            return <article key={n.id} style={{ ...panel, padding: "18px 22px" }}>
              {meta}<p style={{ margin: "12px 0 0", lineHeight: 1.75, whiteSpace: "pre-wrap" }}>{n.text}</p>
              {n.title && <h2 style={{ fontSize: 19, margin: "12px 0 0" }}>{n.title}</h2>}
              {href && <a href={href} style={link}>{n.actionLabel || "Read more"} ↗</a>}
            </article>;
          })}
        </div>
      )}

      <section className="updates-faq" aria-labelledby="updates-faq-title">
        <div className="eyebrow">HELP / QUICK ANSWERS</div>
        <h2 id="updates-faq-title" className="title">Frequently asked<br/><em>questions.</em></h2>
        <p className="lead">Quick answers about Snote, supported workflows and releases.</p>
        <div className="faq-list">
          <details className="faq-item"><summary><span className="faq-index">01</span><strong>What is Snote?</strong><span className="faq-plus">+</span></summary><p>Snote is an open-source, local-first note-taking project focused on handwriting, stylus input, rich text and documents.</p></details>
          <details className="faq-item"><summary><span className="faq-index">02</span><strong>Is Snote open source?</strong><span className="faq-plus">+</span></summary><p>Yes. Check the repository LICENSE and third-party notices before redistribution.</p></details>
          <details className="faq-item"><summary><span className="faq-index">03</span><strong>Which platforms are supported?</strong><span className="faq-plus">+</span></summary><p>The project targets Android, iOS, Windows, macOS, Linux and Web; availability varies by release.</p></details>
          <details className="faq-item"><summary><span className="faq-index">04</span><strong>Does Snote work offline?</strong><span className="faq-plus">+</span></summary><p>Snote is designed for local-first use. Optional cloud features need configuration and connectivity.</p></details>
          <details className="faq-item"><summary><span className="faq-index">05</span><strong>Do I need an account?</strong><span className="faq-plus">+</span></summary><p>Local-first workflows are intended to work without a mandatory cloud account; account features vary by build.</p></details>
          <details className="faq-item"><summary><span className="faq-index">06</span><strong>Does Snote support stylus and handwriting?</strong><span className="faq-plus">+</span></summary><p>The source includes a custom canvas and stylus-oriented input handling. Actual behavior depends on the device and release.</p></details>
          <details className="faq-item"><summary><span className="faq-index">07</span><strong>Can I import and annotate PDFs?</strong><span className="faq-plus">+</span></summary><p>PDF workflows vary by platform and release. Keep an original copy and verify export behavior.</p></details>
          <details className="faq-item"><summary><span className="faq-index">08</span><strong>How do I back up notes?</strong><span className="faq-plus">+</span></summary><p>Use the backup or export options in your installed release and keep an independent copy.</p></details>
          <details className="faq-item"><summary><span className="faq-index">09</span><strong>How do I report a bug?</strong><span className="faq-plus">+</span></summary><p>Open an issue in the repository with app version, device, expected and actual results, and minimal reproduction steps. Remove private data and secrets.</p></details>
          <details className="faq-item"><summary><span className="faq-index">10</span><strong>Where can I find updates?</strong><span className="faq-plus">+</span></summary><p>This page lists published notices and release announcements from the website notification feed.</p></details>
        </div>
      </section>
      <p style={{ marginTop: 28, fontSize: 12, color: "#b0b7c6" }}>This feed is generated from a public JSON file. Updates appear after the website rebuilds and deploys.</p>
    </main>
  );
}

const panel = { border: "1px solid #ffffff20", borderRadius: 20, background: "#ffffff06", padding: 24 } as const;
const muted = { color: "#d0d5df", lineHeight: 1.7 } as const;
const body = { whiteSpace: "pre-wrap" as const, lineHeight: 1.75, color: "#e0e4ed", margin: 0 };
const tag = { border: "1px solid #ffffff25", borderRadius: 99, padding: "5px 10px", fontSize: 11, textTransform: "uppercase" as const, letterSpacing: ".08em" };
const link = { display: "inline-block", marginTop: 16, color: "inherit", textDecoration: "underline", textUnderlineOffset: 4 };
