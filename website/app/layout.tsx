import type { Metadata, Viewport } from "next";
import "./globals.css";
import Link from "next/link";
import MobileNav from "../components/MobileNav";
import ThemeToggle from "../components/ThemeToggle";
import Icon from "../components/Icon";
import NotificationCenter from "../components/NotificationCenter";
import FeedbackCenter from "../components/FeedbackCenter";

const siteUrl = "https://snote-showcase.vercel.app";
export const metadata: Metadata = {
 metadataBase: new URL(siteUrl),
 title: { default: "Snote — Open-Source Handwriting Notes & PDF Annotation", template: "%s | Snote" },
 description: "Discover Snote, an open-source note-taking app for stylus handwriting, digital notebooks, PDF reading and annotation, and local-first notes across supported platforms.",
 applicationName: "Snote",
 keywords: ["Snote note-taking app","open-source note-taking app","handwriting notes app","stylus note-taking app","digital notebook","PDF reader and annotation","offline note-taking app","local-first notes","Flutter notes app"],
 authors: [{ name: "Sadab", url: "https://github.com/shinuXcode" }],
 creator: "Sadab", publisher: "Snote", category: "productivity",
 robots: { index: true, follow: true, googleBot: { index: true, follow: true, "max-image-preview": "large", "max-snippet": -1, "max-video-preview": -1 } },
 openGraph: { title: "Snote — Notes that move with you", description: "Open-source notes for handwriting, reading, and thinking.", url: siteUrl, siteName: "Snote", type: "website", locale: "en_US" },
 twitter: { card: "summary_large_image", title: "Snote — Notes that move with you", description: "Open-source note-taking for handwriting, PDFs, and ideas." },
 other: { "geo.region": "IN", "content-language": "en" }
};
export const viewport: Viewport = { width: "device-width", initialScale: 1, themeColor: "#f5f3ee", colorScheme: "light" };
const nav = [["/how-it-works","Showcase"],["/features","Features"],["/docs","Docs"]];
const orgSchema = { "@context":"https://schema.org","@type":"Organization","name":"Snote","url":siteUrl,"logo":siteUrl+"/snote-logo.svg","founder":{"@type":"Person","name":"Sadab"},"sameAs":["https://github.com/shinuXcode/Snote"] };
const appSchema = { "@context":"https://schema.org","@type":"SoftwareApplication","name":"Snote","applicationCategory":"ProductivityApplication","operatingSystem":"Android, iOS, Windows, macOS, Linux, Web","description":"Open-source note-taking for handwriting, stylus input, rich text, and document workflows.","url":siteUrl,"downloadUrl":siteUrl+"/download","author":{"@type":"Person","name":"Sadab"},"license":"https://github.com/shinuXcode/Snote/blob/main/LICENSE","codeRepository":"https://github.com/shinuXcode/Snote","offers":{"@type":"Offer","price":"0","priceCurrency":"USD"} };
export default function RootLayout({children}:{children:React.ReactNode}) {
 return <>
  <script type="application/ld+json" dangerouslySetInnerHTML={{__html:JSON.stringify(orgSchema)}} />
  <script type="application/ld+json" dangerouslySetInnerHTML={{__html:JSON.stringify(appSchema)}} />
  <header className="nav"><div className="navin shell">
   <Link href="/" className="brand" aria-label="Snote home"><img src="/snote-logo.svg" alt="" /><span className="brand-mark">s.</span><span>snote</span></Link>
   <nav className="links" aria-label="Main navigation">{nav.map(([href,label])=><Link key={href} href={href}>{label}</Link>)}</nav>
   <div className="nav-actions"><NotificationCenter/><ThemeToggle/><a className="nav-github" href="https://github.com/shinuXcode/Snote" target="_blank" rel="noreferrer" aria-label="Snote on GitHub"><Icon name="github" size={19}/></a><Link className="nav-start" href="/download">Download <Icon name="arrow" size={15}/></Link></div>
   <MobileNav/>
  </div></header>
  {children}
  <footer className="footer"><div className="shell footerin">
   <Link href="/" className="footer-brand"><span className="brand-mark">s.</span> Snote</Link>
   <p>Make room for better thinking.</p>
   <div className="footer-links"><Link href="/features">Features</Link><Link href="/docs">Docs</Link><Link href="/faqs">FAQs</Link><Link href="/founder">Founder</Link><Link href="/download">Download</Link><a href="https://github.com/shinuXcode/Snote" target="_blank" rel="noreferrer">GitHub ↗</a></div>
   <span className="footer-copy">Open source. Built for your ideas. © {new Date().getFullYear()} Snote.</span>
  </div></footer>
  <FeedbackCenter/>
 </>;
}
