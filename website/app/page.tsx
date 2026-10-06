export default function Home() {
  return (
    <main style={{fontFamily: "system-ui", minHeight: "100vh", padding: "64px", maxWidth: 1100, margin: "auto"}}>
      <p>SNOTE</p>
      <h1>Write without limits.</h1>
      <p>Offline-first handwriting, rich text and PDF annotation for every device.</p>
      <section style={{display: "grid", gridTemplateColumns: "repeat(auto-fit,minmax(220px,1fr))", gap: 16, marginTop: 40}}>
        <article><h2>Low latency</h2><p>Vector strokes designed for responsive stylus input.</p></article>
        <article><h2>Offline first</h2><p>Your notes remain usable without an internet connection.</p></article>
        <article><h2>Open source</h2><p>No mandatory subscription or proprietary cloud dependency.</p></article>
      </section>
    </main>
  );
}
