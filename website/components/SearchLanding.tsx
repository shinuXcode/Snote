import Link from "next/link";

type Section = { title: string; body: string; bullets?: string[] };
type FAQ = { question: string; answer: string };
type Props = {
  path: string;
  eyebrow: string;
  title: string;
  accent: string;
  intro: string;
  sections: Section[];
  faqs: FAQ[];
};

export default function SearchLanding({ path, eyebrow, title, accent, intro, sections, faqs }: Props) {
  const schema = [
    {
      "@context": "https://schema.org",
      "@type": "WebPage",
      name: title + " " + accent + " | Snotee",
      description: intro,
      url: "https://snotee.vercel.app" + path,
      about: { "@type": "SoftwareApplication", name: "Snotee", applicationCategory: "ProductivityApplication" }
    },
    {
      "@context": "https://schema.org",
      "@type": "BreadcrumbList",
      itemListElement: [
        { "@type": "ListItem", position: 1, name: "Home", item: "https://snotee.vercel.app/" },
        { "@type": "ListItem", position: 2, name: eyebrow, item: "https://snotee.vercel.app" + path }
      ]
    },
    {
      "@context": "https://schema.org",
      "@type": "FAQPage",
      mainEntity: faqs.map(item => ({
        "@type": "Question",
        name: item.question,
        acceptedAnswer: { "@type": "Answer", text: item.answer }
      }))
    }
  ];
  return <main className="shell section search-landing">
    <nav className="breadcrumbs" aria-label="Breadcrumb"><Link href="/">Home</Link><span>/</span><span>{eyebrow}</span></nav>
    <header className="search-landing-head">
      <span className="eyebrow"><i /> {eyebrow}</span>
      <h1 className="title">{title}<br /><em>{accent}</em></h1>
      <p className="lead">{intro}</p>
      <div className="row search-landing-actions">
        <Link className="cta" href="/download">Explore downloads <span aria-hidden="true">↗</span></Link>
        <a className="ghost-cta" href="https://github.com/shinuXcode/Snote" target="_blank" rel="noreferrer">View source code <span aria-hidden="true">↗</span></a>
      </div>
    </header>
    <div className="search-landing-grid">
      {sections.map((section, index) => <article className="search-landing-card" key={section.title}>
        <span className="feature-number">0{index + 1} / SNOTEE</span>
        <h2>{section.title}</h2>
        <p>{section.body}</p>
        {section.bullets && <ul>{section.bullets.map(item => <li key={item}>{item}</li>)}</ul>}
      </article>)}
    </div>
    <section className="search-landing-faq">
      <div className="eyebrow"><i /> QUICK ANSWERS</div>
      <h2 className="title">Before you <em>install.</em></h2>
      {faqs.map(item => <details className="search-faq-item" key={item.question}>
        <summary>{item.question}<span aria-hidden="true">+</span></summary>
        <p>{item.answer}</p>
      </details>)}
    </section>
    <section className="search-landing-bottom">
      <div><span className="eyebrow"><i /> OPEN SOURCE · LOCAL FIRST</span><h2>Make room for <em>better thinking.</em></h2><p>Check the current release, read the documentation, and decide whether Snotee fits your workflow.</p></div>
      <Link className="cta" href="/download">See current releases <span aria-hidden="true">↗</span></Link>
    </section>
    <script type="application/ld+json" dangerouslySetInnerHTML={{ __html: JSON.stringify(schema).replace(/</g, "\\u003c") }} />
  </main>;
}
