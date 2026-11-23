import type { Metadata, Viewport } from "next";
import "./globals.css";
import "./brand-overrides.css";
import Link from "next/link";
import MobileNav from "../components/MobileNav";
import ThemeToggle from "../components/ThemeToggle";
import Icon from "../components/Icon";
import NotificationCenter from "../components/NotificationCenter";
import FeedbackCenter from "../components/FeedbackCenter";
import BrandLoader from "../components/BrandLoader";

const siteUrl = "https://snotee.vercel.app";
export const metadata: Metadata = {
  metadataBase: new URL(siteUrl),
  icons: { icon: "/snote-logo.png", apple: "/snote-logo.png" },
  title: {
    default: "Snotee — Open-source handwriting & PDF notes",
    template: "%s | Snotee"
  },
  description: "Snotee is a free, open-source, local-first note-taking app for handwritten study notes, stylus input, PDF reading and annotation, and rich-text notes on Android and desktop.",
  applicationName: "Snotee",
  keywords: [
    "Snotee", "handwriting notes app", "Android note taking app with stylus",
    "digital note taking app", "free note taking app", "PDF annotation app",
    "open source note taking app", "offline note taking app", "student note taking app",
    "digital notebook", "stylus note taking app", "Goodnotes alternative for Android"
  ],
  authors: [{ name: "Sadab", url: "https://github.com/shinuXcode" }],
  creator: "Sadab",
  publisher: "Snotee",
  category: "productivity",
  alternates: { canonical: "/" },
  robots: {
    index: true,
    follow: true,
    googleBot: {
      index: true,
      follow: true,
      "max-image-preview": "large",
      "max-snippet": -1,
      "max-video-preview": -1
    }
  },
  openGraph: {
    title: "Snotee — Open-source handwriting & PDF notes",
    description: "A local-first workspace for handwritten notes, PDFs, and ideas. Explore Snotee releases and source code.",
    url: siteUrl,
    siteName: "Snotee",
    type: "website",
    locale: "en_US",
    images: [{ url: "/snote-logo.png", width: 512, height: 512, alt: "Snotee note-taking app logo" }]
  },
  twitter: {
    card: "summary",
    title: "Snotee — Open-source handwriting & PDF notes",
    description: "A local-first workspace for handwritten notes, PDFs, and ideas.",
    images: ["/snote-logo.png"]
  }
};

export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
  themeColor: "#160f0b",
  colorScheme: "dark"
};

const nav = [
  ["/how-it-works", "Showcase"],
  ["/features", "Features"],
  ["/docs", "Docs"],
  ["/faqs", "FAQs"]
];

const orgSchema = {
  "@context": "https://schema.org",
  "@type": "Organization",
  name: "Snotee",
  url: siteUrl,
  logo: siteUrl + "/snote-logo.png",
  founder: { "@type": "Person", name: "Sadab" },
  sameAs: ["https://github.com/shinuXcode/Snote"]
};

const appSchema = {
  "@context": "https://schema.org",
  "@type": "SoftwareApplication",
  name: "Snotee",
  applicationCategory: "ProductivityApplication",
  operatingSystem: "Android, Windows, macOS, Linux",
  description: "Open-source, local-first note-taking for handwriting, stylus input, rich text, and PDF workflows.",
  url: siteUrl,
  downloadUrl: siteUrl + "/download",
  author: { "@type": "Person", name: "Sadab" },
  license: "https://github.com/shinuXcode/Snote/blob/main/LICENSE",
  codeRepository: "https://github.com/shinuXcode/Snote",
  isAccessibleForFree: true
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return <>
    <script type="application/ld+json" dangerouslySetInnerHTML={{ __html: JSON.stringify(orgSchema) }} />
    <script type="application/ld+json" dangerouslySetInnerHTML={{ __html: JSON.stringify(appSchema) }} />
    <header className="nav">
      <div className="navin shell">
        <Link href="/" className="brand" aria-label="Snotee home">
          <img src="/snote-logo.png" alt="" /><span>snotee</span>
        </Link>
        <nav className="links" aria-label="Main navigation">
          {nav.map(([href, label]) => <Link key={href} href={href}>{label}</Link>)}
        </nav>
        <div className="nav-actions">
          <NotificationCenter /><ThemeToggle />
          <a className="nav-github" href="https://github.com/shinuXcode/Snote" target="_blank" rel="noreferrer" aria-label="Snotee on GitHub"><Icon name="github" size={19} /></a>
          <Link className="nav-start" href="/download">Download <Icon name="arrow" size={15} /></Link>
        </div>
        <MobileNav />
      </div>
    </header>
    <BrandLoader />
    {children}
    <footer className="footer">
      <div className="shell footerin">
        <Link href="/" className="footer-brand"><img src="/snote-logo.png" alt="" /> Snotee</Link>
        <p>Make room for better thinking.</p>
        <div className="footer-links">
          <Link href="/features">Features</Link><Link href="/docs">Docs</Link>
          <Link href="/faqs">FAQs</Link><Link href="/about-snotee">About Snotee</Link>
          <Link href="/download">Downloads</Link><Link href="/android-note-taking-app">Android App</Link><Link href="/free-note-taking-app">Free Notes App</Link><Link href="/student-note-taking-app">Student Notes</Link><Link href="/handwriting-notes">Handwriting</Link><Link href="/pdf-annotation">PDF Annotation</Link><Link href="/goodnotes-alternative">Goodnotes Alternative</Link><Link href="/open-source-notes-app">Open Source</Link>
          <a href="https://github.com/shinuXcode/Snote" target="_blank" rel="noreferrer">GitHub ↗</a>
        </div>
        <span className="footer-copy">Open source. Built for your ideas. © {new Date().getFullYear()} Snotee.</span>
      </div>
    </footer>
    <FeedbackCenter />
  </>;
}
