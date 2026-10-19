import type { Metadata, Viewport } from "next";
import "./globals.css";
import Link from "next/link";
import MobileNav from "../components/MobileNav";
import ThemeToggle from "../components/ThemeToggle";
import Icon from "../components/Icon";

const siteUrl = "https://snote-showcase.vercel.app";
export const metadata: Metadata = {
 metadataBase: new URL(siteUrl),
 title: { default: "Snote — Notes for Creators", template: "%s | Snote" },
 description: "Snote is an open-source, local-first note-taking workspace for handwriting, stylus writing, rich text, PDFs, and organized ideas.",
 applicationName: "Snote",
 keywords: ["Snote","open source notes","handwriting notes","stylus note taking","digital notebook","PDF annotation","offline notes","Flutter note taking app","open source note taking app"],
 authors: [{ name: "Sadab", url: "https://github.com/shinuXcode" }],
 creator: "Sadab",
 publisher: "Snote",
 category: "productivity",
 robots: { index: true, follow: true, googleBot: { index: true, follow: true, "max-image-preview": "large", "max-snippet": -1, "max-video-preview": -1 } },
 openGraph: { title: "Snote — Notes for Creators", description: "Ideas, structured beautifully. An open-source, local-first note-taking workspace.", url: siteUrl, siteName: "Snote", type: "website", locale: "en_US" },
 twitter: { card: "summary_large_image", title: "Snote — Notes for Creators", description: "Open-source, local-first notes for handwriting, stylus writing, and ideas." },
 other: { "geo.region": "IN", "content-language": "en" }
};
export const viewport: Viewport = { width: "device-width", initialScale: 1, themeColor: "#080808", colorScheme: "dark light" };

const nav = [["/","Home"],["/features","Features"],["/how-it-works","Showcase"],["/docs","Docs"],["/faqs","FAQs"],["/download","Download"]];
const orgSchema = {
 "@context":"https://schema.org","@type":"Organization","name":"Snote","url":siteUrl,
 "logo":siteUrl+"/snote-logo.svg","founder":{"@type":"Person","name":"Sadab"},
 "sameAs":["https://github.com/shinuXcode/Snote"]
};
const appSchema = {
 "@context":"https://schema.org","@type":"SoftwareApplication","name":"Snote",
 "applicationCategory":"ProductivityApplication","operatingSystem":"Android, iOS, Windows, macOS, Linux, Web",
 "description":"Open-source, local-first note-taking for handwriting, stylus input, rich text, and document workflows.",
 "url":siteUrl,"downloadUrl":siteUrl+"/download","author":{"@type":"Person","name":"Sadab"},
 "license":"https://github.com/shinuXcode/Snote/blob/main/LICENSE","codeRepository":"https://github.com/shinuXcode/Snote",
 "offers":{"@type":"Offer","price":"0","priceCurrency":"USD"}
};

export default function RootLayout({children}:{children:React.ReactNode}){
 return <>
  <script type="application/ld+json" dangerouslySetInnerHTML={{__html:JSON.stringify(orgSchema)}} />
  <script type="application/ld+json" dangerouslySetInnerHTML={{__html:JSON.stringify(appSchema)}} />
  <header className="nav"><div className="shell navin">
   <Link href="/" className="brand" aria-label="Snote home"><img src="/snote-logo.svg" alt="" /><span>snote</span></Link>
   <nav className="links" aria-label="Main navigation">{nav.map(([href,label])=><Link key={href} href={href}>{label}</Link>)}</nav>
   <div className="nav-actions"><ThemeToggle /><a className="nav-github" href="https://github.com/shinuXcode/Snote" target="_blank" rel="noreferrer" aria-label="Snote on GitHub"><Icon name="github" size={23}/></a><Link className="nav-start" href="/download">Get Started <Icon name="arrow" size={16}/></Link></div>
   <MobileNav />
  </div></header>
  {children}
  <footer className="footer"><div className="shell footerin">
   <span>Snote · Open source · Offline first</span><span>Android · iOS · Windows · macOS · Linux · Web</span>
   <span className="footer-links"><Link href="/docs">Docs</Link><Link href="/faqs">FAQs</Link><Link href="/features">Features</Link><Link href="/founder">Founder</Link><Link href="/download">Download</Link><a href="https://github.com/shinuXcode/Snote/blob/main/LICENSE">License</a></span>
  </div></footer>
 </>;
}
