import type {Metadata} from "next";
import "./globals.css";
import Link from "next/link";
import MobileNav from "../components/MobileNav";

export const metadata:Metadata={
  title:"Snote — Notes for Creators",
  description:"A minimal, open-source note-taking space for handwriting, rich text, PDFs and ideas.",
  openGraph:{
    title:"Snote — Notes for Creators",
    description:"Ideas, structured beautifully. An open-source note-taking workspace.",
    type:"website"
  }
};

const nav=[
  ["/","Home"],
  ["/features","Features"],
  ["/how-it-works","Showcase"],
  ["/download","Download"],
];

export default function RootLayout({children}:{children:React.ReactNode}){
  return <>
    <header className="nav">
      <div className="shell navin">
        <Link href="/" className="brand" aria-label="Snote home">
          <img src="/snote-logo.svg" alt="" />
          <span>snote</span>
        </Link>
        <nav className="links" aria-label="Main navigation">
          {nav.map(([href,label])=><Link key={href} href={href}>{label}</Link>)}
        </nav>
        <div className="nav-actions">
          <a className="nav-github" href="https://github.com/shinuXcode/Snote" target="_blank" rel="noreferrer" aria-label="Snote on GitHub">◉</a>
          <Link className="nav-start" href="/download">Get Started <span aria-hidden="true">→</span></Link>
        </div>
        <MobileNav />
      </div>
    </header>
    {children}
    <footer className="footer">
      <div className="shell footerin">
        <span>Snote · Open source · Offline first</span>
        <span>Android · iOS · Windows · macOS · Linux · Web</span>
        <span className="footer-links"><Link href="/founder">Founder</Link><Link href="/account">Account</Link><Link href="/download">Download</Link></span>
      </div>
    </footer>
  </>;
}
