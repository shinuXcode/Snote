import Reveal from "../../components/Reveal";

const features = [
  ["Stylus engine","Pressure-aware vector strokes, velocity-based fountain ink, pencil texture and palm rejection."],
  ["Paper & canvas","Infinite-style workspace plus A4, A3, Letter and custom page templates."],
  ["PDF workspace","Keep an annotation layer independent from the original document so handwriting stays editable."],
  ["Local first","The editor writes locally before it talks to the network."],
  ["Account sync","The same Supabase identity can synchronize notes across supported Snote clients."],
  ["Export freedom","Download portable Snote JSON and keep a copy outside the app."],
];

export default function Page() {
  return (
    <main className="shell section">
      <Reveal>
        <div className="eyebrow">Features</div>
        <h1 className="title">Designed around the act of writing.</h1>
        <p className="lead">The interaction model takes cues from serious note apps without copying their UI.</p>
      </Reveal>
      <div className="grid features-grid">
        {features.map(([title,body],i)=>(
          <Reveal key={title}>
            <article className="card feature-card">
              <span className="pill">{String(i+1).padStart(2,"0")}</span>
              <h2>{title}</h2>
              <p className="muted">{body}</p>
            </article>
          </Reveal>
        ))}
      </div>
    </main>
  );
}
