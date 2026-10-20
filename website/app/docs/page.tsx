import Link from "next/link";
import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "Snote Documentation — Original PDFs",
  description:
    "Read or download the original Snote app overview, feature catalogue, open-source guide, notifications and admin guide, permissions, license, SDK reference, terms, and repository audit PDFs.",
  alternates: { canonical: "https://snote-showcase.vercel.app/docs" },
  openGraph: {
    title: "Snote Documentation",
    description: "Browse and download the original Snote documentation PDFs.",
    url: "https://snote-showcase.vercel.app/docs",
    type: "website",
  },
};

const docs = [
  {
    number: "01",
    title: "App Overview",
    description: "Product overview, platform support, versioning, and release guidance.",
    slug: "app-overview",
  },
  {
    number: "02",
    title: "Feature Catalogue",
    description: "Feature areas, writing engine, storage, and platform notes.",
    slug: "features",
  },
  {
    number: "03",
    title: "Notifications & Admin",
    description: "The original Snote notifications and administration reference.",
    slug: "notifications-admin",
  },
  {
    number: "04",
    title: "Open Source Guide",
    description: "Repository structure, development, contributions, CI, and releases.",
    slug: "open-source",
  },
  {
    number: "05",
    title: "Permissions & Authorization",
    description: "Permission inventory, account boundaries, and release verification.",
    slug: "permissions",
  },
  {
    number: "06",
    title: "License & Notices",
    description: "Project license summary and third-party redistribution notices.",
    slug: "license",
  },
  {
    number: "07",
    title: "SDKs & Toolchains",
    description: "Declared SDK versions and platform build requirements.",
    slug: "sdks",
  },
  {
    number: "08",
    title: "Terms of Use",
    description: "The source terms document covering use, content, backups, and services.",
    slug: "terms",
  },
  {
    number: "09",
    title: "Repository Audit",
    description: "Source-level findings, risk areas, and verification checklist.",
    slug: "repository-audit",
  },
] as const;

const pdfUrl = (slug: (typeof docs)[number]["slug"]) => `/docs/${slug}.pdf`;

export default function DocsPage() {
  return (
    <main className="shell section docs-page">
      <div className="eyebrow">
        <i /> DOCUMENTATION LIBRARY
      </div>
      <h1 className="title">
        Snote documentation.
        <br />
        <em>Original PDFs, in one place.</em>
      </h1>
      <p className="lead">
        Open the original documents in your browser or download the same PDF for
        offline reference. Each action uses the original PDF file; no document is
        generated on request.
      </p>

      <div className="docs-library-heading">
        <div>
          <span className="pill">9 ORIGINAL PDFS</span>
          <h2>Documentation library</h2>
        </div>
        <p className="muted">
          Read online opens the PDF in a new tab. Download PDF saves that same file.
        </p>
      </div>

      <div className="grid docs-grid">
        {docs.map(({ number, title, description, slug }) => {
          const url = pdfUrl(slug);
          return (
            <article className="card docs-card" key={slug}>
              <span className="feature-number">{number} / PDF</span>
              <h2>{title}</h2>
              <p className="muted">{description}</p>
              <div className="docs-actions">
                <a
                  className="docs-view"
                  href={url}
                  target="_blank"
                  rel="noopener noreferrer"
                >
                  Read online <span aria-hidden="true">↗</span>
                </a>
                <a className="docs-download" href={url} download>
                  Download PDF <span aria-hidden="true">↓</span>
                </a>
              </div>
            </article>
          );
        })}
      </div>

      <section className="docs-faq card">
        <div>
          <span className="pill">HELP CENTRE</span>
          <h2>Frequently asked questions</h2>
          <p className="muted">
            Quick answers about installation, stylus input, privacy, cloud sync,
            permissions, SDKs, and releases.
          </p>
        </div>
        <Link className="cta" href="/faqs">
          Explore all 28 FAQs <span aria-hidden="true">→</span>
        </Link>
      </section>
      <p className="docs-note">
        These links serve the original PDF files. Documentation is informational
        and does not replace legal advice, platform-specific permission review, or
        a production security audit.
      </p>
    </main>
  );
}
